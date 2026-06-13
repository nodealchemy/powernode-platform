# Stability Tiers

> Maintainer-declared maturity for Powernode subsystems. This is a description of
> where we put our effort and what you can lean on — not a contractual SLA. See the
> footer for the date and standing.

Powernode is a broad platform, and not every part of it is equally settled. Some
subsystems carry production load and have stable contracts; others are real and
useful but still moving; a few are early and would genuinely benefit from outside
help. This document sorts the major subsystems into three tiers and states, per
tier, what "supported" actually means — how quickly we respond, whether the API
surface is allowed to change, and how breaking changes are handled.

**When you file an issue, tell us which tier it lands in.** The bug, feature, and
deployment-help issue templates ask reporters to pick a tier (`tier:stable`,
`tier:beta`, `tier:experimental`). That one field sets our response expectation and
routes the issue to the right place, so it is worth getting right. If you are not
sure, make your best guess from the tables below and we will re-label if needed.
(The issue templates and triage labels are being built alongside this document; if
they are not on the repository yet, just name the tier in the issue body.)

Every major subsystem appears in **exactly one** tier below — no subsystem is listed
twice, and nothing material is left untiered. If you find a subsystem you cannot
locate here, that is a documentation gap; please open an issue.

---

## What the tiers mean

| | **Stable** | **Beta** | **Experimental** |
|---|---|---|---|
| **Response target** | Triaged fast; regressions are treated as priority work. | Triaged on a best-effort cadence; fixes are scheduled, not immediate. | Triaged when we can; no response-time expectation. |
| **API / contract stability** | Public contracts (HTTP endpoints, MCP tool signatures, model interfaces) are held stable. | Contracts are mostly stable but may shift between minor releases. | Contracts can change without notice, including shape and naming. |
| **Breaking-change policy** | Breaking changes are avoided; when unavoidable they ship with a deprecation window and a documented migration path. | Breaking changes are allowed at minor-version boundaries and called out in release notes. | Breaking changes can land at any time; no deprecation window is promised. |
| **Who maintains it** | Core maintainers. | Core maintainers, contributions welcome. | Open to **community maintainers** — see below. |

"Supported" is strongest in Stable and deliberately lighter as you move right. A
subsystem being in Beta or Experimental is not a warning that it is broken — much of
it works well. It is a statement about how much we are willing to promise about its
*contract* and *response time* today.

Two cross-cutting notes that apply regardless of tier:

- **Security issues are handled outside the tier system.** A security report against
  any subsystem — Stable, Beta, or Experimental — follows the process in
  [`SECURITY.md`](../SECURITY.md), not the response targets above.
- **Core mode is the supported baseline.** Powernode runs in *core mode* (single-user,
  self-hosted, all core capabilities unlocked) when the private commercial business
  extension is absent. Tiering below describes the open-source core and the public
  extensions. The private commercial business extension is out of scope for this
  document.

---

## Stable

Subsystems that carry production load, have settled contracts, and are first in line
for regression fixes. These are the parts of Powernode you can build on.

| Subsystem | Where it lives | Notes |
|-----------|----------------|-------|
| Authentication & permissions | `server/app/services/auth/`, `server/app/services/permissions/`, `security/` | JWT auth, permission-based access control, encryption/guardrails. The access-control model the rest of the platform depends on. |
| Agents & autonomy | `server/app/services/ai/` (agents, missions, autonomy, goals, approvals) | Agent orchestration, mission lifecycle, approval-gated autonomy, kill-switch/emergency-halt. The core product surface. |
| MCP tools & runtime | `server/app/services/mcp/`, `server/app/services/ai/tools/` | Model Context Protocol execution engine and tool registry — the `platform.*` tool surface. Broad, actively used coverage. |
| Agent-to-Agent (A2A) | `server/app/services/a2a/` | A2A protocol — agent cards, skill registry, message handling, streaming. |
| DevOps / CI-CD | `server/app/services/devops/`, `server/app/models/devops/` | Pipelines, Git integration, deployment, container registry, and Docker Swarm *cluster lifecycle* (provisioning and node operations). |
| System extension — core paths | `extensions/system/` (`models/system/`, `services/system/`) | The substrate layer and Powernode's primary differentiator: node lifecycle, module CRUD and assignment, provisioning, templates, and the on-node agent. PXE-to-production bare-metal provisioning through to K3s. |
| Cost optimization / FinOps | `server/app/services/cost_optimization/` | Budget tracking, cost analysis, provider optimization, multi-provider routing economics. |

**Support:** Issues are triaged quickly and regressions treated as priority work.
Public contracts (HTTP endpoints, MCP tool signatures, model interfaces) are held
stable; breaking changes are avoided, and when unavoidable they ship with a
deprecation window and a documented migration path.

---

## Beta

Real, useful, and in active use — but the contracts are still firming up and we
reserve the right to move them at minor-version boundaries. Expect best-effort
support rather than priority response.

| Subsystem | Where it lives | Notes |
|-----------|----------------|-------|
| Knowledge graph & RAG tuning surfaces | `server/app/services/ai/rag/` (graph-RAG, hybrid search), `server/app/models/knowledge_base/`, knowledge-graph services | Core retrieval works; the *tuning* surfaces (ranking, graph construction, embedding strategy) are where the contract is still moving. |
| Swarm coordination | `server/app/services/devops/docker/` (swarm manager, service/stack managers), `server/app/models/devops/swarm_*` | Multi-node Docker Swarm orchestration and service/stack coordination. Cluster *lifecycle* is Stable (above); the higher-level coordination/orchestration surface is still settling. |
| Multi-platform chat | `server/app/services/chat/` (adapters, gateway, router) | Conversation management plus platform adapters (Slack, Discord, WhatsApp, Telegram). The gateway works; individual adapter contracts vary in maturity. |

**Support:** Issues are triaged on a best-effort cadence and fixes are scheduled
rather than immediate. Contracts are mostly stable but may shift between minor
releases; breaking changes are allowed at minor-version boundaries and are called
out in release notes. Contributions here are welcome and reviewed.

---

## Experimental

Early-stage or under active rework. These areas are worth exploring and contributing
to, but make no contract or response-time promises, and we may change them at any
time. **Experimental subsystems explicitly welcome community maintainers** — if you
depend on one of these and want it to harden, the fastest path is to help maintain
it (see [`CONTRIBUTING.md`](../CONTRIBUTING.md); we will grant triage rights and
review your changes promptly).

| Subsystem | Where it lives | Notes |
|-----------|----------------|-------|
| Marketing extension | `extensions/marketing/` | The least mature public extension: public-facing site plus campaign management. Functional but the thinnest in coverage and the most likely to change shape. A good first place to pick up maintainership. |
| Anything under active sweep / refactor | varies | Subsystems being actively re-architected sit here *temporarily* until the rework settles, then graduate to Beta or Stable. As of the date below, recent sweeps include the provider model-sync path; check recent release notes and commit history for the current set. TODO(verify): keep this row current as sweeps open and close. |

**Support:** Triaged when we can, with no response-time expectation. Contracts can
change without notice — including shape and naming — and breaking changes can land
at any time with no deprecation window. This is the tier where outside ownership has
the most leverage.

---

## How a subsystem moves between tiers

Tiers are not permanent. A subsystem graduates **Experimental → Beta → Stable** as
its contract settles, test coverage deepens, and it proves out under real load.
It can also move *down* a tier if it enters a significant rework. Tier changes are
made by maintainers and reflected here; the issue templates and `tier:*` labels are
kept in sync with this document. If a tier label on an issue looks wrong for where
the subsystem actually sits, say so in the issue and we will reconcile.

---

_Last reviewed: 2026-06-12. Maintainer-declared maturity guidance, not a contractual
service-level agreement — it describes where effort is focused and what contracts we
intend to hold, and it changes as the platform does._
