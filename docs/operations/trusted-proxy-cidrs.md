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

**It REPLACES Rails' default list, it does not extend it.** Once set, the
default trusted-proxy list (every loopback/private/link-local range) no
longer applies at all — only the hops you list are trusted. If a reverse
proxy (e.g. Traefik) runs **on the same host** as this app and connects over
loopback or a Docker-bridge private address, that hop's address (or its
containing CIDR) MUST be included explicitly, or its own forwarded-for
header stops being honored and `request.remote_ip` resolves to the proxy
itself instead of the real client.

**A restart is required.** This is read once, in `server/config/application.rb`,
during `Rails::Application` class-body evaluation at boot — changing it in a
running deployment's environment has no effect until the Rails process
(`powernode-*-rails.service`) restarts.

## All-invalid behavior

If every entry fails to parse (e.g. `TRUSTED_PROXY_CIDRS=garbage`), boot does
not crash (see `server/lib/powernode/trusted_proxy_cidrs.rb`), but the result
is the SAME as leaving the variable unset entirely: nothing gets pinned, and
Rails' own default list applies. `Admin::MaintenanceMode.status.bypass_ips_supported`
reports `false` in this state (checked against the PARSED result, not the raw
env var's presence — see `trusted_proxies_configured?`), and any bypass-IP
write is rejected with a 422 explaining why. Boot-time logs (STDERR) name
each invalid entry it skipped.

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
