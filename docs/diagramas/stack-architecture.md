# Stack Architecture — opentelemetry

Topología del Compose stack `observability`: cómo entran los datos por el gateway, cómo se reparten a cada backend y qué expone Grafana al usuario.

```mermaid
graph LR
    Track([conbiz-track]) -->|OTLP/HTTP :4318| Gateway
    Auto([conbiz-auto]) -->|OTLP/HTTP :4318| Gateway
    Trucks([conbiz-trucks]) -->|OTLP/HTTP :4318| Gateway
    N8N([n8n host]) -->|OTLP/HTTP :4318| Gateway

    Gateway[OTel Collector Gateway]
    Gateway -->|traces| Tempo[(Tempo :3200)]
    Gateway -->|logs| Loki[(Loki :3100)]
    Gateway -->|metrics + remote-write| Prom[(Prometheus :9090)]

    Tempo -->|spanmetrics| Prom

    User([Operator]) -->|HTTPS :3000| Grafana[Grafana UI]
    Grafana --> Tempo
    Grafana --> Loki
    Grafana --> Prom
```

## Notas

- Sólo `:4318` (gateway OTLP/HTTP) y `:3000` (Grafana) están bind a `0.0.0.0`. El resto queda en `127.0.0.1`.
- `spanmetrics` en el gateway genera RED metrics derivadas de los spans y las publica a Prometheus vía remote-write — por eso Prometheus tiene una flecha desde Tempo en los dashboards lógicos, aunque físicamente las series viajan por el gateway.
- Cada servicio cliente corre un OTel Agent local que reenvía al gateway. Este diagrama omite ese hop para mantener foco en el stack central.
