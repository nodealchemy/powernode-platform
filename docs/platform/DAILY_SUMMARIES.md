# Daily Summaries

**Auto-generated daily operational summary pages**

**Version**: 1.0 | **Last Updated**: April 2026

---

## Overview

Daily Summaries is an admin-only feature that produces a Markdown snapshot of key operational metrics for an account each day. Each summary is persisted as a regular `Page` record (slug pattern `daily-summary-{ISO8601-date}`, status `published`), so it inherits the platform's content-linking, permissions, and CMS tooling. A scheduled worker job generates yesterday's summary across all accounts every night; admins can also trigger on-demand generation for a specific date via the UI.

The summary includes up to four sections:

- **Subscriptions** — active count, new today, canceled today
- **AI Agent Executions** — total runs, completed, failed, avg duration, total tokens, total cost
- **Knowledge Growth** — new learnings, verified, deprecated, new shared knowledge
- **Knowledge Graph** — new nodes today, new edges today, total active nodes, total edges

Sections without data for the day are omitted, not stubbed.

---

## Admin API

All endpoints require the `admin.access` permission.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/admin/daily_summaries` | Paginated list of past summaries |
| `GET` | `/api/v1/admin/daily_summaries/latest` | Most recent summary with full content |
| `POST` | `/api/v1/admin/daily_summaries/generate` | Generate (or fetch idempotent existing) summary. Accepts `date` param (ISO8601); defaults to `Date.yesterday` |

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

`POST /generate` is **idempotent by slug** — calling it twice for the same date returns the existing `Page` record rather than creating a duplicate.

---

## Service

`DailySummaryService` (`server/app/services/daily_summary_service.rb`)

```ruby
service = DailySummaryService.new(account: account, date: Date.yesterday)
page = service.generate!
# => Returns existing Page if slug already exists for that date; otherwise creates and returns a new one.
```

### Author resolution

The summary is authored by the first admin-role user in the account, or the first user if no admin exists. This mirrors how other system-generated Pages attribute content.

### Section generation

Each section helper returns `nil` when the underlying dataset is empty, so the rendered Markdown only contains sections with meaningful data. The `build_markdown` method compacts and joins surviving sections with `---` separators.

---

## Scheduled Job

`DailySummaryJob` (`worker/app/jobs/daily_summary_job.rb`)

```ruby
DailySummaryJob.perform_async                 # Generate yesterday's summary for all accounts
DailySummaryJob.perform_async(account.id)    # Generate for a single account
```

- Queue: `maintenance`
- Retry: 2
- Scheduled: daily via sidekiq-cron (see `worker/config/sidekiq.yml`)

The job operates via the worker → server HTTP API only — it never touches Rails models directly. Account enumeration goes through `GET /api/v1/admin/accounts`; per-account generation calls `POST /api/v1/admin/daily_summaries/generate` with `date: Date.yesterday.iso8601`.

---

## Frontend Integration

| Component | Path | Purpose |
|-----------|------|---------|
| `DailySummariesPage` | `frontend/src/pages/app/content/DailySummariesPage.tsx` | Route container for the admin UI |
| `DailySummariesPanel` | `frontend/src/features/content/pages/components/DailySummariesPanel.tsx` | Timeline sidebar + detail view with Markdown rendering |

The panel auto-loads the list + latest summary on mount, supports on-demand generation via a "Generate Now" button, and renders selected summaries via `MarkdownRenderer` (admin variant, advanced features enabled).

---

## Key Files

| Role | Path |
|------|------|
| Controller | `server/app/controllers/api/v1/admin/daily_summaries_controller.rb` |
| Service | `server/app/services/daily_summary_service.rb` |
| Worker job | `worker/app/jobs/daily_summary_job.rb` |
| Routes | `server/config/routes.rb` (under `namespace :admin`) |
| Frontend page | `frontend/src/pages/app/content/DailySummariesPage.tsx` |
| Frontend panel | `frontend/src/features/content/pages/components/DailySummariesPanel.tsx` |

## See Also

- [AI_ORCHESTRATION_GUIDE.md](AI_ORCHESTRATION_GUIDE.md) — AI platform architecture
- [CONTENT_LINKING.md](CONTENT_LINKING.md) — Wikilinks + backlinks (summaries are linkable as Pages)
- [API_RESPONSE_STANDARDS.md](API_RESPONSE_STANDARDS.md) — Response format used by the controller
