---
name: Bug Report
about: Report a problem or unexpected behavior in Powernode
title: "[Bug] "
labels: bug
---

<!--
Before filing:
- Search existing issues to avoid duplicates.
- For SECURITY issues, do NOT file publicly. Follow the process in SECURITY.md
  (open a private GitHub Security Advisory at
  https://github.com/nodealchemy/powernode-platform/security/advisories/new).
  Security reports are handled outside the stability-tier system.
- For "how do I deploy / self-host this" questions, use the deployment-help
  template or GitHub Discussions instead of a bug report.
- See CONTRIBUTING.md for the full contribution guide.
-->

## Description

A clear, concise description of the bug.

## Steps to Reproduce

1. ...
2. ...
3. ...

## Expected Behavior

What you expected to happen.

## Actual Behavior

What actually happened. Include error messages, stack traces, or screenshots.

## Stability Tier

Which tier does the affected subsystem fall under? See
[`docs/STABILITY.md`](../../docs/STABILITY.md) for the per-subsystem tables. This sets
our response expectation — pick your best guess and we will re-label if needed.

- [ ] `tier:stable` — auth/permissions, agents & autonomy, MCP tools & runtime, A2A, DevOps/CI-CD, system extension core paths, cost/FinOps
- [ ] `tier:beta` — knowledge graph & RAG tuning surfaces, Swarm coordination, multi-platform chat
- [ ] `tier:experimental` — marketing extension, or anything under active sweep/refactor
- [ ] Not sure

## Environment

- **Powernode version / commit**:
- **Component**: backend (`server/`) / frontend (`frontend/`) / worker (`worker/`) / extension (`business` / `marketing` / `system` / `supply-chain`)
- **Mode**: core mode (no private commercial extension) / extensions present (which?)
- **OS**:
- **Ruby version** (if backend):
- **Node version** (if frontend):
- **PostgreSQL version**:
- **Browser** (if frontend):

## Logs

```
Paste relevant log output. Redact any secrets, tokens, or personal data before pasting.
```

## Additional Context

Anything else that might help — recent changes, configuration, related issues, workarounds you've tried.
