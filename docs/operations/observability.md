# Observability: Logs, Metrics, Traces

> Status: active
>
> **When to use this runbook**: deploying log aggregation for a Powernode environment, adding a new service to log routing, debugging why expected logs aren't showing up in Grafana.

## Contents

- [Stack overview](#stack-overview)
- [Loki + Promtail deployment](#loki--promtail-deployment)
- [Grafana datasource wiring](#grafana-datasource-wiring)
- [Retention](#retention)
- [Log labels and queries](#log-labels-and-queries)
- [Application logging conventions](#application-logging-conventions)
- [Metrics (Prometheus)](#metrics-prometheus)
- [Troubleshooting](#troubleshooting)

## Stack overview

Powernode ships configuration scaffolding for a Grafana-Loki-Promtail-Prometheus stack. Operators run the actual containers themselves — the repo does not deploy them.

| Component | Repo config | Role |
|-----------|-------------|------|
| **Loki** | `configs/logging/loki-config.yml` | Log storage + query (port 3100) |
| **Promtail** | `configs/logging/promtail-config.yml` | Log shipper, scrapes Docker container stdout (port 9080) |
| **Grafana** | `configs/monitoring/grafana-datasources.yml`, `configs/monitoring/grafana-dashboards.yml` | UI + alerting |
| **Prometheus** | (operator-deployed) | Metrics scrape + storage (port 9090, default Grafana datasource) |

The configs assume single-node defaults (`replication_factor: 1`, filesystem storage). For multi-host fleets, scale via the Loki [microservices mode](https://grafana.com/docs/loki/latest/setup/install/) — repo configs are operator-extensible.

## Loki + Promtail deployment

### Single-host Docker Compose (recommended for first deploy)

Create `docker-compose.observability.yml` adjacent to the existing Powernode compose:

```yaml
services:
  loki:
    image: grafana/loki:2.9.0
    ports:
      - "3100:3100"
    volumes:
      - ./configs/logging/loki-config.yml:/etc/loki/local-config.yaml:ro
      - loki-data:/tmp/loki
    command: -config.file=/etc/loki/local-config.yaml
    restart: unless-stopped

  promtail:
    image: grafana/promtail:2.9.0
    volumes:
      - ./configs/logging/promtail-config.yml:/etc/promtail/config.yml:ro
      - /var/log:/var/log:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    command: -config.file=/etc/promtail/config.yml
    depends_on:
      - loki
    restart: unless-stopped

volumes:
  loki-data:
```

Bring it up:

```bash
docker compose -f docker-compose.observability.yml up -d
docker compose -f docker-compose.observability.yml logs -f loki | head -30   # smoke
```

### Container-tag opt-in

Promtail only scrapes containers labeled `logging=promtail` (per the config's `docker_sd_configs.filters`). When deploying Powernode services, tag them:

```yaml
services:
  backend:
    image: powernode/backend
    labels:
      - logging=promtail
```

This avoids accidentally shipping infrastructure-component logs to Loki and ballooning storage.

### Swarm deployment

For Docker Swarm, deploy as a global service so Promtail runs on every node:

```yaml
deploy:
  mode: global
  placement:
    constraints:
      - node.platform.os == linux
```

See `docs/operations/docker-swarm.md` for the broader Swarm operations runbook.

## Grafana datasource wiring

The shipped `configs/monitoring/grafana-datasources.yml` provisions Prometheus as the default datasource. **Loki is commented out** — uncomment when deploying Loki:

```yaml
# Edit configs/monitoring/grafana-datasources.yml — uncomment:
  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    isDefault: false
    version: 1
    editable: true
```

Mount the file into your Grafana container at `/etc/grafana/provisioning/datasources/datasources.yml` and restart Grafana to pick it up.

## Retention

| Layer | Default | Configured in | How to change |
|-------|---------|---------------|---------------|
| Loki logs | **7 days** | `configs/logging/loki-config.yml` (`retention_period: 168h`) | Edit value, restart Loki |
| Loki compactor sweep | every 10 min | same file (`compaction_interval`) | rarely changed |
| Promtail positions | persistent | `/tmp/positions.yaml` inside Promtail container | use a named volume to survive restarts |

For compliance regimes that require longer retention (PCI: 1 year minimum), increase `retention_period` and ensure storage volume is sized accordingly. The compactor will free disk space automatically once `retention_delete_delay: 2h` has elapsed.

## Log labels and queries

Promtail's relabel rules surface these labels for every scraped container log line:

| Label | Source | Example |
|-------|--------|---------|
| `container` | Docker container name | `powernode-backend-1` |
| `logstream` | `stdout` / `stderr` | `stderr` |
| `service_name` | Swarm service label | `powernode_backend` |
| `stack` | Swarm stack label | `powernode-production` |

Common LogQL queries (paste into Grafana → Explore → Loki):

```logql
# All ERROR lines from backend in the last hour
{service_name="powernode_backend"} |= "ERROR"

# Worker job failures
{service_name="powernode_worker"} |~ "Failed .* Job after"

# Backend 5xx
{service_name="powernode_backend"} |~ "Completed 5\\d\\d"

# Audit log writes from the model layer
{service_name="powernode_backend"} |= "AuditLog" |= "created"

# Report request lifecycle for a specific id
{service_name=~"powernode_(backend|worker)"} |= "019e3c6c-9e1a"
```

## Application logging conventions

Powernode services follow consistent log emission to make LogQL queries reliable:

- **Rails backend** uses `Rails.logger` only (per `feedback_clean_implementations` and `frontend/CLAUDE.md` — no `puts`/`print`). Output is JSON-ish lines on stdout.
- **Worker** uses `BaseJob` helpers (`log_info`, `log_error`) that emit structured fields including job class + JID.
- **Frontend** (browser) uses `logger` from `@/shared/utils/logger` — no `console.log` in production (caught by `scripts/cleanup-all-console-logs.sh`).
- **Request IDs**: each HTTP request gets a `request.uuid` Rails sets. Include it when logging from a request path so cross-service traces correlate.

If you add a new component that should ship logs to Loki:
1. Add the `logging=promtail` label.
2. Ensure stdout/stderr is unbuffered (Ruby: `STDOUT.sync = true`; Node: `process.stdout.write` is line-buffered when TTY).
3. Use a structured format (JSON or `key=value` pairs) so LogQL can `| logfmt`-parse fields.

## Metrics (Prometheus)

The repo ships `configs/monitoring/grafana-dashboards.yml` and a `grafana-dashboards/` directory. Prometheus scrape config is operator-owned — point Prometheus at:

> **Status: not yet implemented** — there is no `yabeda-rails`/`yabeda-prometheus`-backed `/metrics` endpoint today, and no yabeda gem (active or commented) exists in `server/Gemfile`. The actual APM/monitoring gems are `sentry-ruby`/`sentry-rails`, `skylight` (optional), and OpenTelemetry (opt-in via `OTEL_ENABLED=true` + `bundle install --with opentelemetry`). The Rails-app Prometheus `/metrics` path below is planned; adding the yabeda gems is the intended path to enable it.

| Endpoint | What it exposes |
|----------|-----------------|
| `http://backend:3000/metrics` | Rails app metrics (request counts, latency histograms via `yabeda-rails`) — _planned_; requires adding the `yabeda-prometheus` gem to `server/Gemfile` and re-bundling. Not present today (see status callout above). |
| `http://worker:4567/metrics` | Worker HTTP API metrics (job dispatch counts, queue depth) |
| `cAdvisor`, `node_exporter` | Standard host + container metrics — deploy via the same observability compose file |

## Troubleshooting

### "I don't see any logs in Grafana"

1. **Is Loki receiving them?**
   ```bash
   curl -s http://localhost:3100/ready
   curl -s http://localhost:3100/metrics | grep ingester_streams_total
   ```
   `ingester_streams_total` should be non-zero and growing.
2. **Is Promtail scraping?**
   ```bash
   curl -s http://localhost:9080/targets | head -30
   ```
   Expected: one entry per `logging=promtail`-labeled container.
3. **Is the container actually labeled?**
   ```bash
   docker ps --format '{{.Names}}\t{{.Labels}}' | grep -i logging
   ```
4. **Datasource configured in Grafana?** Grafana → Configuration → Data Sources → Loki should show "Data source is working".

### "Some lines have no labels"

Promtail's `relabel_configs` only attach Swarm labels if Swarm metadata is present. For plain Docker Compose deploys, `service_name` and `stack` are empty — query by `container` instead.

### "Disk filling up on Loki host"

The compactor needs time to free space (`retention_delete_delay: 2h`). If disk is filling faster than retention deletes free, either:
- Reduce `retention_period`
- Increase the host volume
- Add more aggressive label filters in `promtail-config.yml` to drop noisy logs at the ingest boundary

## See also

- [production-deployment.md](./production-deployment.md) — overall production setup
- [docker-swarm.md](./docker-swarm.md) — Swarm-specific deploys
- [incident-response.md](./incident-response.md) — uses these logs during incidents
- [performance-tuning.md](./performance-tuning.md) — metrics-driven tuning

_Last verified: 2026-06-04_
