# Daily Summaries

> When to use this runbook: operating the admin-only daily-summary feature that produces a Markdown snapshot of key operational metrics per account each day.

## Table of Contents

- [Prerequisites](#prerequisites)
- [When to use this](#when-to-use-this)
- [Overview](#overview)
- [Procedure — generate on demand](#procedure--generate-on-demand)
- [Admin API](#admin-api)
- [Service](#service)
- [Scheduled Job](#scheduled-job)
- [Frontend](#frontend)
- [Verification](#verification)
- [Rollback](#rollback)
- [Troubleshooting](#troubleshooting)
- [Key Files](#key-files)

## Prerequisites

- Backend (`powernode-backend@default`) and worker (`powernode-worker@default`) services running.
- An admin user (one with the `admin.access` permission).
- At least one published `Page` author resolvable (admin-role user, otherwise first user in the account).

## When to use this

- Confirming the daily 6 AM run produced summaries for every active account.
- Generating an on-demand summary for a specific date for audit / governance.
- Investigating why a date is missing a summary.

## Overview

Daily Summaries is an admin-only feature that produces a Markdown snapshot of key operational metrics for an account each day. Each summary is persisted as a regular `Page` record (slug pattern `daily-summary-{ISO8601-date}`, status `published`), so it inherits the platform's content-linking, permissions, and CMS tooling. A scheduled worker job generates yesterday's summary across all accounts every night; admins can also trigger on-demand generation for a specific date via the UI.

A summary includes up to four sections; sections without data for the day are omitted (never stubbed):

- **Subscriptions** — active count, new today, cancelled today
- **AI Agent Executions** — total runs, completed, failed, avg duration, total tokens, total cost
- **Knowledge Growth** — new learnings, verified, deprecated, new shared knowledge
- **Knowledge Graph** — new nodes today, new edges today, total active nodes, total edges

## Procedure — generate on demand

1. Navigate to **Daily Summaries** in the admin panel.
2. Click **Generate Now**. The frontend POSTs to `/api/v1/admin/daily_summaries/generate` with `date` defaulting to `Date.yesterday`.
3. Inspect the rendered Markdown in the detail pane.

CLI alternative:

```bash
curl -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"date":"2026-05-16"}' \
  https://api.powernode.example.com/api/v1/admin/daily_summaries/generate
```

`POST /generate` is **idempotent by slug** — calling it twice for the same date returns the existing `Page` record rather than creating a duplicate.

## Admin API

All endpoints require the `admin.access` permission.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/admin/daily_summaries` | Paginated list of past summaries |
| `GET` | `/api/v1/admin/daily_summaries/latest` | Most recent summary with full content |
| `POST` | `/api/v1/admin/daily_summaries/generate` | Generate (or fetch idempotent existing). Accepts `date` (ISO8601); defaults to `Date.yesterday` |

### Response shape

```json
{
  "success": true,
  "data": {
    "summaries": [
      {
        "id": "uuid",
        "title": "Daily Summary — April 16, 2026",
        "slug": "daily-summary-2026-04-16",
        "date": "2026-04-16",
        "published_at": "2026-04-17T06:00:00Z",
        "word_count": 142,
        "estimated_read_time": 1,
        "created_at": "2026-04-17T06:00:00Z"
      }
    ],
    "meta": {
      "current_page": 1,
      "per_page": 10,
      "total_count": 37,
      "total_pages": 4
    }
  }
}
```

`GET /latest` and `POST /generate` also include a `content` field with the full Markdown body.

## Service

`DailySummaryService` lives at `server/app/services/daily_summary_service.rb`.

```ruby
service = DailySummaryService.new(account: account, date: Date.yesterday)
page = service.generate!
# Returns existing Page if slug already exists for that date;
# otherwise creates and returns a new one.
```

### Author resolution

The summary is authored by the first admin-role user in the account, or the first user if no admin exists. This mirrors how other system-generated Pages attribute content.

### Section generation

Each section helper returns `nil` when the underlying dataset is empty, so the rendered Markdown only contains sections with meaningful data. The `build_markdown` method compacts and joins surviving sections with `---` separators.

## Scheduled Job

`DailySummaryJob` lives at `worker/app/jobs/daily_summary_job.rb`.

```ruby
DailySummaryJob.perform_async                # All accounts for yesterday
DailySummaryJob.perform_async(account.id)    # Single account
```

- Queue: `maintenance`
- Retry: 2
- Schedule: daily via sidekiq-cron (see `worker/config/sidekiq.yml`)

The job operates via the worker → server HTTP API only — it never touches Rails models directly. Account enumeration goes through `GET /api/v1/admin/accounts`; per-account generation calls `POST /api/v1/admin/daily_summaries/generate` with `date: Date.yesterday.iso8601`.

## Frontend

| Component | Path | Purpose |
|-----------|------|---------|
| `DailySummariesPage` | `frontend/src/pages/app/content/DailySummariesPage.tsx` | Route container for the admin UI |
| `DailySummariesPanel` | `frontend/src/features/content/pages/components/DailySummariesPanel.tsx` | Timeline sidebar + detail view |

The panel auto-loads the list + latest summary on mount, supports on-demand generation via a "Generate Now" button, and renders selected summaries via `MarkdownRenderer` (admin variant, advanced features enabled).

## Verification

After running the scheduled job (or manual generate):

```bash
# Confirm Page record exists for the date
rails runner "
puts ::Page.where('slug LIKE ?', 'daily-summary-%').order(created_at: :desc).limit(5).map { |p|
  \"#{p.slug} (#{p.status})\"
}
"

# Confirm worker logged the run
journalctl -u powernode-worker@default --since "1 day ago" | grep DailySummary
```

Expected:
- A `Page` with slug `daily-summary-YYYY-MM-DD` and status `published` for the target date.
- Worker logs show `DailySummaryJob` completion within ~5 minutes of scheduled time.

## Rollback

To unpublish a problematic summary:

```bash
rails runner "::Page.find_by(slug: 'daily-summary-2026-05-16')&.update!(status: 'archived')"
```

Or delete:

```bash
rails runner "::Page.find_by(slug: 'daily-summary-2026-05-16')&.destroy"
```

Re-run on-demand generation afterwards if needed.

## Troubleshooting

| Symptom | Likely cause | First action |
|---------|--------------|--------------|
| Daily run produced no summaries | Worker scheduler not running | Restart `powernode-worker@default` and verify sidekiq-cron schedule |
| `generate` returns the same `Page` repeatedly | Slug already exists for that date (idempotent behaviour) | Expected — pass a different `date` or delete the existing Page first |
| Author resolution fails | Account has zero users | Create at least one user before retrying |
| Section omitted unexpectedly | Empty dataset for that account on that day | Verify by querying source data directly; section helpers return `nil` on empty datasets |

## Key Files

| Role | Path |
|------|------|
| Controller | `server/app/controllers/api/v1/admin/daily_summaries_controller.rb` |
| Service | `server/app/services/daily_summary_service.rb` |
| Worker job | `worker/app/jobs/daily_summary_job.rb` |
| Routes | `server/config/routes.rb` (under `namespace :admin`) |
| Frontend page | `frontend/src/pages/app/content/DailySummariesPage.tsx` |
| Frontend panel | `frontend/src/features/content/pages/components/DailySummariesPanel.tsx` |

---

## Related runbooks

- [ai-operations.md](ai-operations.md) — AI metrics that feed the summary
- [worker-operations.md](worker-operations.md) — Sidekiq schedule reference

## Materials previously at

- `docs/platform/DAILY_SUMMARIES.md`

_Last verified: 2026-05-17_
