# UI smoke report

- base: `https://dev.powernode.org`
- routes crawled: 142
- routes with findings: 8
- by severity: {"high":7,"low":1}
- detail pages sampled (dropped 156 `…/<uuid>` beyond 2/listing)

## [high] `/app/ai/cost/finops/budget`
- uncaught: budgets is not iterable

## [high] `/app/ai/cost/finops/cost-explorer`
- uncaught: Cannot read properties of undefined (reading 'length')

## [high] `/app/marketing/analytics`
- uncaught: channels.map is not a function

## [high] `/app/marketing/calendar`
- uncaught: Cannot read properties of undefined (reading 'forEach')

## [high] `/app/marketing/campaigns`
- uncaught: Cannot read properties of undefined (reading 'filter')

## [high] `/app/marketing/email-lists`
- uncaught: Cannot read properties of undefined (reading 'length')

## [high] `/app/marketing/social`
- uncaught: Cannot read properties of undefined (reading 'length')

## [low] `/app/ai`
- console.error: AI Orchestration monitor error: Event

