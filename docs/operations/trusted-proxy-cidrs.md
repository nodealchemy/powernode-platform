# `TRUSTED_PROXY_CIDRS`

## What it is

An optional environment variable that pins Rails' `ActionDispatch::RemoteIp`
trusted-proxy list to exactly the reverse-proxy hops this deployment actually
has, instead of Rails' own default (`ActionDispatch::RemoteIp::TRUSTED_PROXIES`),
which trusts every loopback, private, and link-local address as a proxy.

Left at that default, `request.remote_ip` cannot be trusted: anything that
reaches the app directly from a private address (another container on the
same host/VPC, bypassing the real reverse proxy) is treated as a trusted hop,
and Rails will honor an arbitrary attacker-supplied `X-Forwarded-For` header
as the caller's IP. Pinning `TRUSTED_PROXY_CIDRS` is what makes
`request.remote_ip` trustworthy at all.

This is the env var that gates `Admin::MaintenanceMode`'s bypass-IP allowlist
(see `server/app/services/admin/maintenance_mode.rb`): while it is unset, the
maintenance-mode gate refuses to configure or match ANY bypass IP/CIDR — public
or private — with a 422 explaining why, because a bypass decision keyed on an
unpinned `remote_ip` cannot be trusted either way.

## Value shape

**Every reverse-proxy hop, comma-separated** — one entry per hop between the
public internet and this app, as an IP or CIDR:

```
TRUSTED_PROXY_CIDRS=203.0.113.10,203.0.113.11/32,198.51.100.0/24
```

Whitespace around entries and blank entries (a trailing or doubled comma) are
ignored. An individual entry that fails to parse as an IP/CIDR is logged and
skipped rather than crashing boot — see `Powernode::TrustedProxyCidrs.parse`
(`server/lib/powernode/trusted_proxy_cidrs.rb`).

## Placeholders only

**Never commit this deployment's real proxy addresses to a tracked file.**
Any example in a tracked doc, `.env.example`, or runbook must use placeholder
addresses (like the `203.0.113.0/24` / `198.51.100.0/24` TEST-NET ranges used
above) — never this deployment's actual reverse-proxy IPs. The real value for
a given deployment is set directly in that deployment's environment/secrets
store, never in git.

## Related

- `server/config/application.rb` — wires this into
  `config.action_dispatch.trusted_proxies`.
- `server/lib/powernode/trusted_proxy_cidrs.rb` — the parser (blank-entry
  filtering, invalid-entry log-and-skip).
- `server/app/services/admin/maintenance_mode.rb` — the maintenance-mode
  bypass-IP gate this env var unlocks.
