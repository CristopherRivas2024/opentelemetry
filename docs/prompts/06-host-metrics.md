# Add host metrics: cadvisor + node-exporter

## Project context

You are working on the Conbiz central observability stack — a Docker Compose deployment of OpenTelemetry Collector + Tempo + Loki + Prometheus + Grafana. Read `CLAUDE.md` for orientation. Currently the only metrics in Prometheus are application-level (RED metrics from Tempo's spanmetrics) and the collector's own self-metrics. There is **nothing** about the host: no CPU, no RAM, no disk space, no network, no per-container resource usage.

## Goal

Add two services to the stack:
- **node-exporter** — host-level metrics (CPU, RAM, disk, network, filesystem, load)
- **cadvisor** — per-container metrics (CPU, memory, network, IO per container)

Then add a Grafana dashboard for each, and add a disk-space alert that was deferred from the original alerting rules because it required this prerequisite.

## Why this matters

Right now you have no answer to:
- "Is the host CPU pegged?"
- "Is `/var/lib/docker` filling up?" (this is where named volumes live!)
- "Which container is eating all the memory?"
- "Is the network saturated?"

The disk question is critical — your Tempo / Loki / Prometheus volumes have no upper bound, so without a disk-space alert you'll find out the hard way.

## Constraints

- node-exporter and cadvisor go in the same `docker-compose.yml`, on the `observability` network
- Bind their ports to `127.0.0.1` only — internal scrape targets, not user-facing
- node-exporter mounts `/`, `/proc`, `/sys` from the host as read-only (standard pattern)
- cadvisor mounts `/var/run/docker.sock`, `/sys`, `/var/lib/docker/` (read-only)
- Add scrape jobs for both in `config/prometheus.yml`
- Provision dashboards via `grafana/provisioning/dashboards/` (one for host, one for containers)
- Add the disk-space alert in `grafana/provisioning/alerting/rules.yaml` under a new group `host-resources`

## Implementation hints

### Compose snippets (template)

```yaml
node-exporter:
  image: prom/node-exporter:v1.8.2
  container_name: node-exporter
  restart: unless-stopped
  pid: host
  network_mode: host  # OR observability network with port binding — choose one
  command:
    - "--path.procfs=/host/proc"
    - "--path.sysfs=/host/sys"
    - "--path.rootfs=/host/root"
    - "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc|rootfs/var/lib/docker/containers|rootfs/var/lib/docker/overlay2)($$|/)"
  volumes:
    - /proc:/host/proc:ro
    - /sys:/host/sys:ro
    - /:/host/root:ro,rslave

cadvisor:
  image: gcr.io/cadvisor/cadvisor:v0.49.1
  container_name: cadvisor
  restart: unless-stopped
  privileged: true
  ports:
    - "127.0.0.1:8080:8080"
  volumes:
    - /:/rootfs:ro
    - /var/run:/var/run:ro
    - /sys:/sys:ro
    - /var/lib/docker/:/var/lib/docker:ro
    - /dev/disk/:/dev/disk:ro
  networks:
    - observability
```

> Note: `network_mode: host` for node-exporter is the standard recommendation but **does not work on Docker Desktop on Windows/macOS**. If the host is Windows (it is — see `CLAUDE.md`), use the `observability` network and bind `127.0.0.1:9100:9100` instead. Filesystem metrics will be limited but the rest works.

### Prometheus scrape jobs to add

```yaml
- job_name: "node-exporter"
  static_configs:
    - targets: ["node-exporter:9100"]   # OR localhost:9100 if host network
- job_name: "cadvisor"
  static_configs:
    - targets: ["cadvisor:8080"]
```

### Disk-space alert rule (add to `rules.yaml`)

```yaml
- orgId: 1
  name: "host-resources"
  folder: "Conbiz Alerts"
  interval: 1m
  rules:
    - uid: "alert-disk-space-low"
      title: "Disk space < 20% free"
      condition: "C"
      data:
        - refId: "A"
          datasourceUid: "prometheus"
          relativeTimeRange: { from: 300, to: 0 }
          model:
            expr: |
              100 * (
                node_filesystem_avail_bytes{mountpoint="/",fstype!~"tmpfs|overlay"}
                /
                node_filesystem_size_bytes{mountpoint="/",fstype!~"tmpfs|overlay"}
              )
            refId: "A"
        - refId: "C"
          datasourceUid: "__expr__"
          model:
            type: "threshold"
            expression: "A"
            conditions:
              - evaluator: { params: [20], type: "lt" }
                operator: { type: "and" }
                query: { params: ["C"] }
                reducer: { type: "last" }
                type: "query"
            refId: "C"
      noDataState: "OK"
      execErrState: "Error"
      for: "10m"
      labels:
        severity: "warning"
        component: "host"
      annotations:
        summary: "Host disk usage high — {{ $values.A | printf \"%.1f\" }}% free"
        description: "Less than 20% free on the root filesystem for 10 minutes. Check large files in /var/lib/docker/volumes."
```

### Dashboards

Two dashboards:
- `host-overview.json` — CPU, load avg, memory used/available, network in/out, disk space per mountpoint, IO util — using `node_*` metrics
- `containers.json` — per-container CPU, memory (rss), network — using `container_*` metrics from cadvisor, with a variable `$container`

Use existing dashboards in `grafana/provisioning/dashboards/` as style reference.

## Acceptance criteria

- [ ] `docker compose config` validates
- [ ] `make up` brings the new services up healthy
- [ ] `curl -s http://127.0.0.1:9100/metrics | head` returns node metrics (or via `docker exec` if not on host network)
- [ ] `curl -s http://127.0.0.1:8080/metrics | head` returns cadvisor metrics
- [ ] Prometheus targets page shows both jobs UP
- [ ] New dashboards appear in Grafana → Dashboards → Conbiz
- [ ] The disk-space alert shows up in Grafana → Alerting and is in OK state on a healthy host

## Out of scope

- Don't add Windows-host-specific exporters (this stack runs on Linux even if dev is Windows — verify before assuming)
- Don't add per-process metrics (process-exporter) — overkill
- Don't add SNMP/IPMI exporters — different use case
- Don't replicate every dashboard from grafana.com — focus on the dimensions the user actually asks about

## Definition of done

Commit with: `feat(metrics): add host (node-exporter) and container (cadvisor) metrics with dashboards and disk-space alert`
