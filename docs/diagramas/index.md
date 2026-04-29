# Diagramas — opentelemetry

Catálogo de diagramas Mermaid del proyecto. Cada diagrama vive en su propio archivo `.md` con bloque `mermaid` embebido.

## Lista

| Diagrama | Descripción | Archivo |
|----------|-------------|---------|
| Stack Architecture | Topología del Compose stack: gateway, Tempo, Loki, Prometheus, Grafana, red interna y puertos externos | [stack-architecture.md](stack-architecture.md) |
| Backup Flow | Flujo completo de backup por volumen: disparador → side-car alpine → tar.gz → retención en BACKUP_DIR | [backup-flow.md](backup-flow.md) |

## Convención

Ver [how-to.md](how-to.md) para las reglas de creación de diagramas.
