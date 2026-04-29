# Put Grafana behind nginx with TLS

## Project context

You are working on the Conbiz central observability stack — a Docker Compose deployment of OpenTelemetry Collector + Tempo + Loki + Prometheus + Grafana. Read `CLAUDE.md` for orientation. The host already runs **nginx** as a reverse proxy for other services. Grafana is currently exposed at `0.0.0.0:3000` over plain HTTP.

## Goal

Front Grafana with the existing nginx reverse proxy, terminate TLS at nginx, and stop binding Grafana's port to `0.0.0.0` directly. Result: users hit `https://observability.<internal-domain>/` and get Grafana with a valid cert.

## Why this matters

Plain HTTP for an admin UI is a footgun even on an internal network — credentials and session cookies travel in cleartext. Adding nginx in front also gives you a single point to add IP allow-lists, basic auth, or rate limiting later.

## Constraints

- nginx runs **on the host**, not in the compose stack — this prompt does NOT add nginx as a container
- TLS cert source: assume internal CA or self-signed for the closed network. Path placeholders: `/etc/nginx/certs/observability.crt`, `/etc/nginx/certs/observability.key`
- After the change, Grafana port `3000` should bind to `127.0.0.1:3000` (not `0.0.0.0`) so only nginx can reach it
- Keep WebSocket support working (Grafana Live needs it)
- Keep Grafana's own `GF_SERVER_ROOT_URL` and `GF_SERVER_DOMAIN` correct so generated links use HTTPS

## Implementation hints

### Files to create / modify

1. `nginx/observability.conf` — nginx server block (new file in repo, host-installed manually OR mounted)
2. `docker-compose.yml` — change Grafana port binding from `0.0.0.0:3000:3000` to `127.0.0.1:3000:3000`; add `GF_SERVER_ROOT_URL` and `GF_SERVER_DOMAIN` env vars
3. `.env.example` — add `OBSERVABILITY_DOMAIN=observability.example.internal`
4. `docs/nginx-setup.md` — short instructions: where to put the cert, how to install the conf, how to reload nginx

### Suggested nginx block (template)

```nginx
upstream grafana_upstream {
    server 127.0.0.1:3000;
    keepalive 32;
}

server {
    listen 443 ssl http2;
    server_name observability.example.internal;

    ssl_certificate     /etc/nginx/certs/observability.crt;
    ssl_certificate_key /etc/nginx/certs/observability.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    # Grafana root
    location / {
        proxy_pass http://grafana_upstream/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Grafana Live (WebSockets) — needed for live dashboards
    location /api/live/ {
        proxy_pass http://grafana_upstream/api/live/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}

server {
    listen 80;
    server_name observability.example.internal;
    return 301 https://$host$request_uri;
}
```

### Grafana env vars to add (compose)

```yaml
- GF_SERVER_ROOT_URL=https://${OBSERVABILITY_DOMAIN}/
- GF_SERVER_DOMAIN=${OBSERVABILITY_DOMAIN}
- GF_SERVER_SERVE_FROM_SUB_PATH=false
```

## Acceptance criteria

- [ ] `docker compose config` validates
- [ ] `make up` brings the stack up healthy
- [ ] `ss -tlnp | grep 3000` (or `netstat -an`) shows Grafana bound to `127.0.0.1:3000`, NOT `0.0.0.0`
- [ ] `curl -k https://<domain>/api/health` returns `{"database":"ok"...}`
- [ ] Grafana UI loads at `https://<domain>/` with valid TLS handshake
- [ ] Grafana Live works (Live indicator in dashboards stays connected)
- [ ] `nginx -t` passes
- [ ] `docs/nginx-setup.md` clearly states where the cert files go and how to reload

## Out of scope

- Don't add nginx as a container — host nginx is the convention here
- Don't add basic auth in nginx unless the user asks — Grafana has its own auth
- Don't expose Tempo/Loki/Prometheus through nginx — those stay internal
- Don't issue the cert itself — that's an ops task; the prompt assumes the cert exists

## Definition of done

Commit with: `feat(grafana): proxy via nginx with TLS, bind container port to localhost only`
