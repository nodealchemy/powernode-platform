# stdio MCP servers: package pinning and native execution

How Powernode runs a **stdio** MCP server (one it spawns as a child process), what it refuses, and the one operator-approved exception. Applies to every stdio spawn path: the worker's connection / health-check / tool-discovery / tool-execution jobs and the server's synchronous prompts/resources path, which the worker executes on the server's behalf.

Both apps carry the same rule set (`server/app/services/mcp/security_service.rb` and `worker/app/services/mcp_security_service.rb`); a parity spec fails if they drift.

## Package-launcher pinning (MCP isolation Phase 1 T4)

A **package launcher** resolves its package from a public registry at spawn time. Unless the spec names an exact version, "whatever the registry serves right now" is what runs on your worker. Powernode therefore **refuses an unpinned launcher invocation**, both when the server is saved and again when it is spawned.

Launchers covered:

| Command line | What must be pinned |
|---|---|
| `npx [opts] <pkg> [args]` | `<pkg>`, and every `-p/--package` value |
| `bun x [opts] <pkg> [args]` | `<pkg>` |
| `uvx [opts] <pkg> [args]`, `uv tool run ...` | `<pkg>`, every `--from` and `-w/--with` value |
| `uv run [opts] <script>` | every `-w/--with` value (the script itself is local) |
| `pipx run [opts] <pkg> [args]` | `<pkg>`, every `--spec` and `--preinstall` value |
| `deno run/serve ... npm:<pkg> / jsr:@scope/<pkg>` | every `npm:`/`jsr:` specifier, anywhere in argv |

**Pinned means an exact version — no integrity hash is required** (the operator's stated bar; hash/lockfile support would be a separate change).

| Ecosystem | Accepted | Refused |
|---|---|---|
| npm (`npx`, `bun x`, `deno npm:`) | `name@1.2.3`, `@scope/name@1.2.3`, prerelease/build suffixes (`1.2.3-beta.1+build.5`), `npm:name@1.2.3/subpath` | no version, dist-tags (`@latest`, `@next`), ranges (`^1.2.3`, `~1.2`, `>=1`, `1.2.x`, `*`), incomplete (`1.2`), `v`/`=` prefixes, leading zeros, `github:`/`user/repo`/`git+`/URL/tarball/`file:`/path specs, `npm:` aliases, uppercase names |
| PyPI (`uvx`, `uv`, `pipx`) | `name==1.2.3`, `name@1.2.3`, extras (`name[extra]==1.2.3`), PEP 440 epoch/pre/post/dev (`1!2.0rc1.post1.dev2`) | no version, ranges (`>=`, `~=`, `!=`), wildcard (`==1.*`), arbitrary equality (`===`), `pkg @ url`, `git+`/URL/path specs |
| jsr (`deno jsr:`) | `jsr:@scope/name@1.2.3` | anything else |

Options **before** the package are scanned fail-closed: only a small allowlist per launcher is recognized (`-y`, `--quiet`, `--python 3.12`, ...). Anything unlisted — a registry or index override (`--registry`, `--index-url`, `-i`), a requirements file, `--pip-args`, `--path`, `--editable`, a short cluster like `-yp`, a typo — refuses the whole command line, because an unrecognized option could change which package or registry is used. Options **after** the package belong to the package and are not scanned.

The refusal names the launcher, the offending spec, and the shape to write it in, e.g.

```
npx: package "@modelcontextprotocol/server-filesystem" is not pinned to an exact version.
Write it as @modelcontextprotocol/server-filesystem@<major>.<minor>.<patch>
(e.g. @modelcontextprotocol/server-filesystem@1.2.3); dist-tags (latest, next), ranges
(^, ~, >=, *, x), git/URL/tarball/path specs and npm: aliases are refused.
```

### Where it is enforced

- **Save time** — `McpServer` refuses to create a stdio server, or to change an existing one's `command`/`args`, into an unpinned launcher (422 from `POST/PATCH /api/v1/mcp_servers`, error on `command`).
- **Spawn time** — `validate_stdio_server!` refuses on every spawn path, server and worker alike. A refusal is written to the audit log as `mcp.servers.spawn_refused` (metadata: command, error class, message — never env values).

### Rows that already exist

Nothing is migrated or disabled. A pre-existing unpinned server:

- is **refused at its next spawn** (connect, health check, discovery, tool call) with the message above; the worker records it on the row as `status: error` / `last_error`, and the audit log gets `mcp.servers.spawn_refused`;
- **stays saveable** for status/last_error updates (so that report can land) until someone edits its `command`/`args`, at which point the edit must pin the package.

What the operator must do: edit each affected server's command/args to an exact version (`GET /api/v1/mcp_servers` lists them; `last_error` carries the exact spec to fix), then reconnect. To find them without waiting for a spawn, look for `mcp.servers.spawn_refused` audit rows after deploying, or check each stdio server whose `args` contain a launcher package without `@<version>` / `==<version>`.

## Native execution (the escape hatch)

Every stdio child normally runs inside the worker's transient `systemd-run` sandbox (`MCP_STDIO_SANDBOX_MODE`, default `required` — refuse rather than run unsandboxed; `available` — sandbox when possible, warn and run unsandboxed otherwise; `off` — never sandbox). Some servers genuinely need the host (device access, a host toolchain, a socket the sandbox hides). For those, and **only in core mode**, an operator can approve a single server to run natively.

- **Core mode only.** The hatch is unavailable whenever the business layer is present (detected through the generic capability seam: `:subscriptions` or `:public_registration` registered by any extension). Approval requests are refused with 403 then, and an approval granted earlier goes dormant — the worker is told nothing — without being erased. Revocation is always allowed.
- **Its own permission and its own endpoint.** `POST /api/v1/mcp_servers/:id/native_execution` approves, `DELETE` revokes. Both require `mcp.servers.native_execution`, which is **not** part of `mcp.servers.write`: owner/admin profiles carry it, the manager and AI-specialist profiles (who can create and edit servers) do not. It is never a create/update attribute: `capabilities` is not an accepted parameter there, and the worker-facing internal update strips it. No MCP tool exposes it to agents.
- **Bound to the command line.** Changing the server's `command` or `args` clears the approval automatically (audited as a revoke with reason `command_changed`); approve again after reviewing the new command line.
- **Bypasses only the sandbox.** Command/argument/environment validation and package pinning still apply, unchanged. Note that `npx -p <pinned> <cmd>` runs `<cmd>` through a shell by npm's design; under the hatch that shell is unsandboxed too.
- **Audited.** `mcp.servers.native_execution_approve` / `_revoke` on the server (who, when, which command line), and `mcp.servers.native_execution_spawn` from the worker every time a child actually runs unsandboxed (plus a WARN in the worker log naming the server and the sandbox mode).

The public API shows the state on every server: `native_execution: { available, approved, effective, approved_at, approved_by_id }` — `effective` is what the worker is actually told.

## Related

- `docs/concepts/mcp-and-tools.md` — the platform's own MCP tool registry (a different thing from the stdio servers an account registers).
- `docs/operations/mcp-environment-isolation.md` — isolating MCP connectors between environments.
