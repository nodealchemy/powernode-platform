---
name: Deployment / Self-Hosting Help
about: Get help running, deploying, or self-hosting Powernode
title: "[Help] "
labels: help-wanted
---

<!--
Before filing:
- This template is for getting Powernode running, not for reporting a defect. If
  you've found a clear bug with steps to reproduce, use the Bug Report template
  instead.
- Open-ended "how should I..." or "is this the right approach" questions are often
  a better fit for GitHub Discussions:
  https://github.com/nodealchemy/powernode-platform/discussions
- Start from docs/getting-started/01-quickstart.md and the troubleshooting guide
  (docs/getting-started/04-troubleshooting.md) — your answer may already be there.
- For SECURITY issues, do NOT file publicly. Follow SECURITY.md.
-->

## What are you trying to do?

Describe the goal — e.g. "run core mode on a single VM," "bring up the worker
alongside the Rails API," "deploy the system extension for bare-metal provisioning."

## What have you tried?

Steps taken so far, commands run, docs or guides you followed (link them). Tell us
where it broke.

## Environment

- **Powernode version / commit**:
- **Mode**: core mode (no private commercial extension) / extensions present (which?)
- **Deployment target**: bare metal / VM / container / cloud (which provider?) / local dev
- **OS / distro**:
- **Service manager**: systemd / manual / other
- **Ruby version**:
- **Node version**:
- **PostgreSQL version** (with pgvector?):
- **Which services are you running?**: backend (`server/`) / frontend / worker / worker HTTP API

## Relevant Output / Logs

```
Paste the error output, failed command, or service logs here.
Redact any secrets, tokens, hostnames, or personal data before pasting.
```

## Additional Context

Anything else about your setup — reverse proxy, network constraints, air-gapped
environment, custom configuration, etc.
