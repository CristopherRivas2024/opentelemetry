# Central Observability Stack — Makefile
# Requires: docker compose v2, curl

.PHONY: up down logs status test-ingest

## up: Start all observability services in the background
up:
	docker compose up -d --remove-orphans

## down: Stop and remove all containers (data volumes are preserved)
down:
	docker compose down

## logs: Tail logs for all services (Ctrl-C to stop)
logs:
	docker compose logs -f

## status: Show running containers and their health status
status:
	docker compose ps

## test-ingest: Send a minimal OTLP trace payload to the gateway and verify HTTP 200
test-ingest:
	@echo "Sending test OTLP trace to http://localhost:4318/v1/traces ..."
	@RESPONSE=$$(curl -s -o /dev/null -w "%{http_code}" \
		-X POST http://localhost:4318/v1/traces \
		-H "Content-Type: application/json" \
		-d '{ \
			"resourceSpans": [{ \
				"resource": { \
					"attributes": [{ \
						"key": "service.name", \
						"value": {"stringValue": "test-service"} \
					}] \
				}, \
				"scopeSpans": [{ \
					"scope": {"name": "test"}, \
					"spans": [{ \
						"traceId": "aabbccddeeff00112233445566778899", \
						"spanId": "aabbccddeeff0011", \
						"name": "test-span", \
						"kind": 1, \
						"startTimeUnixNano": "1700000000000000000", \
						"endTimeUnixNano":   "1700000001000000000", \
						"status": {"code": 1} \
					}] \
				}] \
			}] \
		}'); \
	if [ "$$RESPONSE" = "200" ]; then \
		echo "SUCCESS: Gateway accepted the trace (HTTP 200)"; \
	else \
		echo "FAILED: Gateway returned HTTP $$RESPONSE"; \
		exit 1; \
	fi
