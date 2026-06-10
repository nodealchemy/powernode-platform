# Workload: tech-radar — Emerging AI Technique Review

Weekly research sweep over AI agent / loop / prompt-engineering developments,
distilled into platform knowledge and (at most one) actionable proposal.
Budget ~20–30 minutes of work.

**Two execution modes:**
- **Cloud routine** (`Powernode Tech Radar (weekly)`, Mondays 07:07 Anchorage,
  https://claude.ai/code/routines/trig_01YDrvVX7AnYFbzPwVmhrJqA) — runs the research
  in an isolated cloud sandbox with a self-contained prompt; no platform MCP access,
  so it DELIVERS a report with ready-to-ingest knowledge blocks. The maintainer
  reviews the report and ingests entries locally (steps 3–5 below).
- **Local run** (this file, any Claude Code session on this machine) — full procedure
  including direct `platform.create_knowledge` ingestion.

## Scope (pick 3–5 topics per run, rotate)

1. **Loop & harness engineering** — agent loop patterns, verification harnesses,
   completion criteria, unattended/overnight runs, failure-mode mitigation.
2. **Claude platform capabilities** — Claude Code releases (hooks, skills, agents,
   workflows, scheduled routines), Agent SDK, Anthropic engineering posts, new models.
3. **Prompt/context engineering** — context compaction, external memory, automatic
   prompt optimization (DSPy/GEPA-style), spec-driven development tooling.
4. **Multi-agent orchestration** — MCP ecosystem developments, A2A, agent fleets,
   coordination patterns relevant to the platform's swarm/team/mission substrate.
5. **Wildcard** — anything notable since the last run (check the previous
   `tech-radar-*` knowledge tags first to avoid re-reporting).

## Procedure

1. `platform.search_knowledge` for last run's `tech-radar-` tags — know what's
   already captured; only report what's NEW or materially changed.
2. WebSearch each chosen topic (prefer primary sources: Anthropic docs/engineering
   blog, original papers, maintainer blogs/repos). WebFetch the 1–2 best sources
   per topic; extract concretely (what it is, evidence, applicability here).
3. For each finding worth keeping (aim 3–6 total):
   `platform.create_knowledge` — content_type `reference`, tagged
   `tech-radar-<YYYY>-W<week>` plus topic tags. Include source URLs and a
   "Platform applicability" paragraph (which subsystem could use it: dev-loop
   harness, Ralph loops, missions, skills evolution, knowledge lifecycle...).
4. If exactly one finding is actionable enough to pilot now:
   `platform.create_proposal` (proposal_type feature/architecture) referencing the
   knowledge entries — include scope, expected benefit, smallest viable experiment.
   Zero proposals is fine; two is not.
5. `platform.send_proactive_notification` — one summary: topics covered, findings
   count, proposal (if any), with the knowledge tag for retrieval.

## Guardrails

- Primary sources over SEO content; no speculation presented as fact — mark
  unverified claims as such.
- Each knowledge entry must be self-contained (a reader who missed the run can act
  on it) and must NOT duplicate existing entries — search before writing.
- No code changes, no platform mutations beyond knowledge/proposal/notification.
- If the platform MCP server is unreachable, write findings to
  `docs/research/tech-radar-<date>.md` instead and note the outage in the summary.
