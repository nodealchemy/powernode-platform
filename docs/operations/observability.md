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
| **Promtail** | `configs/logging/promtail-config.yml` | Log shipper, reads the systemd journal + service log files (port 9080) |
| **Grafana** | `configs/monitoring/grafana-datasources.yml`, `configs/monitoring/grafana-dashboards.yml` | UI + alerting |
| **Prometheus** | (operator-deployed) | Metrics scrape + storage (port 9090, default Grafana datasource) |

The configs assume single-node defaults (`replication_factor: 1`, filesystem storage). For multi-host fleets, scale via the Loki [microservices mode](https://grafana.com/docs/loki/latest/setup/install/) — repo configs are operator-extensible.

## Loki + Promtail deployment

### Running the stack

Loki, Promtail, and Grafana are third-party services, independent of Powernode's own
systemd deployment — run them however you like (containers are simplest). A minimal
single-host Compose file for just these tools:

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
      - /var/log/journal:/var/log/journal:ro
      - /etc/machine-id:/etc/machine-id:ro
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

### What Promtail collects

Promtail's `powernode-journal` job keeps only `powernode-*.service` units from the systemd
journal (via a `relabel_configs` `keep`), so the platform's own logs flow in automatically —
no per-service opt-in. Separate file/syslog jobs cover apt-installed dependencies (nginx,
PostgreSQL, Redis). This scoping avoids shipping unrelated journal noise to Loki and
ballooning storage.

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

Promtail's relabel rules surface these labels for every Powernode journal line:

| Label | Source | Example |
|-------|--------|---------|
| `unit` | systemd unit (`__journal__systemd_unit`) | `powernode-backend@default.service` |
| `level` | journal priority (`__journal_priority_keyword`) | `err` |
| `host` | journal hostname | `powernode-hub` |
| `job` | static job label | `powernode` |

Common LogQL queries (paste into Grafana → Explore → Loki):

```logql
# All ERROR lines from backend in the last hour
{unit=~"powernode-backend.*"} |= "ERROR"

# Worker job failures
{unit=~"powernode-worker.*"} |~ "Failed .* Job after"

# Backend 5xx
{unit=~"powernode-backend.*"} |~ "Completed 5\\d\\d"

# Audit log writes from the model layer
{unit=~"powernode-backend.*"} |= "AuditLog" |= "created"

# Report request lifecycle for a specific id
{unit=~"powernode-(backend|worker).*"} |= "019e3c6c-9e1a"
```

## Application logging conventions

Powernode services follow consistent log emission to make LogQL queries reliable:

- **Rails backend** uses `Rails.logger` only (per `feedback_clean_implementations` and `frontend/CLAUDE.md` — no `puts`/`print`). Output is JSON-ish lines on stdout.
- **Worker** uses `BaseJob` helpers (`log_info`, `log_error`) that emit structured fields including job class + JID.
- **Frontend** (browser) uses `logger` from `@/shared/utils/logger` — no `console.log` in production (caught by `scripts/cleanup-all-console-logs.sh`).
- **Request IDs**: each HTTP request gets a `request.uuid` Rails sets. Include it when logging from a request path so cross-service traces correlate.

If you add a new component that should ship logs to Loki:
1. If it runs as a `powernode-*` systemd unit, journald collects it automatically. Otherwise add a dedicated scrape job (journal `matches`, file `__path__`, or syslog) in `promtail-config.yml`.
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
   Expected: the `powernode-journal` job plus the file/syslog jobs, all `up`.
3. **Are the journal units flowing?**
   ```bash
   journalctl -u 'powernode-*' -n 5 --no-pager   # confirm units log to journald
   ```
4. **Datasource configured in Grafana?** Grafana → Configuration → Data Sources → Loki should show "Data source is working".

### "Some lines have no labels"

The `powernode-journal` job only keeps `powernode-*.service` units. Logs from the file/syslog jobs carry their own `job` label — query by `job` (e.g. `{job="nginx"}`) instead.

### "Disk filling up on Loki host"

The compactor needs time to free space (`retention_delete_delay: 2h`). If disk is filling faster than retention deletes free, either:
- Reduce `retention_period`
- Increase the host volume
- Add more aggressive label filters in `promtail-config.yml` to drop noisy logs at the ingest boundary

## See also

- [production-deployment.md](./production-deployment.md) — overall production setup
- [single-node-bootstrap.md](./single-node-bootstrap.md) — the systemd install these logs come from
- [incident-response.md](./incident-response.md) — uses these logs during incidents
- [performance-tuning.md](./performance-tuning.md) — metrics-driven tuning
- [ops-hub-watchdog.md](./ops-hub-watchdog.md) — external watchdog that emits into this stack's journal scrape + textfile-collector conventions

_Last verified: 2026-06-04_
