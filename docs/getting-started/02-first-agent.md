# Ship Your First Agent

> A tutorial that walks you from a fresh Powernode install to a working AI agent.

> Status: stub — expand as the platform matures

This tutorial is reserved as the canonical hands-on demo of Powernode's core proposition: composing, deploying, and supervising AI agents. The platform already exposes the surfaces the tutorial will exercise (providers, agents, teams, skills, MCP tools, intervention policies); the tutorial itself is intentionally short while we settle on the best narrative and screenshot set.

## Table of Contents

- [What you'll learn](#what-youll-learn)
- [Prerequisites](#prerequisites)
- [Concept refresher](#concept-refresher)
- [Step-by-step](#step-by-step)
- [Verification](#verification)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)
- [What's next](#whats-next)

## What you'll learn

By the end of this tutorial you will:

- Pick an AI provider and confirm the platform can reach it.
- Create your first `Ai::Agent` with a system prompt and skill bindings.
- Execute the agent from the chat surface and via the MCP `execute_agent` action.
- Inspect the execution trace, cost record, and audit log the platform produces automatically.

## Prerequisites

- A working Powernode install (see [01-quickstart.md](./01-quickstart.md)).
- One of: an Ollama instance reachable from the backend, an Anthropic API key, an OpenAI API key, or any other supported provider's credentials.
- The seeded admin account (created automatically by `rails db:seed`).

## Concept refresher

Powernode's agent abstraction has four moving parts:

1. **Providers** (`Ai::Provider`) — wrap the API surface for a specific vendor (Anthropic, OpenAI, Ollama, etc.). Health-checked continuously.
2. **Agents** (`Ai::Agent`) — a system prompt + provider + model + a set of bound skills. Has a trust score that decays when idle.
3. **Skills** (`Ai::Skill`) — reusable capabilities the agent can invoke; backed by either MCP tools or executor classes.
4. **Intervention policies** — per-action approval rules. Determine which agent decisions auto-execute and which require a human.

See [concepts/agents-and-autonomy.md](../concepts/agents-and-autonomy.md) for the full model.

## Step-by-step

_Section pending — to be written or commissioned as a focused tutorial._

## Verification

_Section pending — will include exact API/CLI calls that confirm the agent is healthy, executed, and produced an audit record._

## Cleanup

_Section pending — will detail how to leave the platform in a known state after the demo._

## Troubleshooting

Common failure modes the finished tutorial should cover:

- Provider credentials missing or invalid → check `platform.provider_health` and review the seed step in [01-quickstart.md](./01-quickstart.md).
- Agent execution fails with `permission_denied` → confirm the user has the `ai.agents.execute` permission (see [concepts/permissions.md](../concepts/permissions.md)).
- MCP session not established → check `platform.discover_claude_sessions`; restart the backend if no session is visible.

## What's next

- Tour the extension model → [03-extensions.md](./03-extensions.md)
- Learn the architecture → [../concepts/agents-and-autonomy.md](../concepts/agents-and-autonomy.md)
- Understand intervention policies → [../concepts/agents-and-autonomy.md](../concepts/agents-and-autonomy.md)

---

_Last verified: 2026-06-03_
