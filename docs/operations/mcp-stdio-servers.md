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
| `uv run [opts] <script>` | every `-w/--with` value; `<script>` must be a local path (`/…`, `./…`, `../…`), not a bare name `uv` could resolve as a package or tool |
| `pipx run [opts] <pkg> [args]` | `<pkg>`, every `--spec` and `--preinstall` value |
| `deno run/serve ... npm:<pkg> / jsr:@scope/<pkg>` | every `npm:`/`jsr:` specifier, anywhere in argv, including attached flag values (`--allow-import=npm:…`) |

`uv`, `uvx` and `pipx` are also refused when their first argument is an option (`uv --config-file … run`, `pipx --foo run`): a global option before the subcommand can redirect where packages come from, so none is recognized. `deno` pinning is **partial by design**: `deno run https://example.com/mod.ts` (a remote module given as the positional) is still allowed — remote-module policy is a separate concern from registry pinning — but an `=https://…` / `=http://…` value attached to any flag is refused, and a flag value given as a separate token (`--allow-import npm:x`) is not modelled as a value at all (it is scanned as its own token, so a `npm:`/`jsr:` specifier there is still held to the pin rule).

**Pinned means an exact version — no integrity hash is required** (the operator's stated bar; hash/lockfile support would be a separate change).

| Ecosystem | Accepted | Refused |
|---|---|---|
| npm (`npx`, `bun x`, `deno npm:`) | `name@1.2.3`, `@scope/name@1.2.3`, prerelease/build suffixes (`1.2.3-beta.1+build.5`), `npm:name@1.2.3/subpath` | no version, dist-tags (`@latest`, `@next`), ranges (`^1.2.3`, `~1.2`, `>=1`, `1.2.x`, `*`), incomplete (`1.2`), `v`/`=` prefixes, leading zeros, `github:`/`user/repo`/`git+`/URL/tarball/`file:`/path specs, `npm:` aliases, uppercase names |
| PyPI (`uvx`, `uv`, `pipx`) | `name==1.2.3`, `name@1.2.3`, extras (`name[extra]==1.2.3`), PEP 440 epoch/pre/post/dev (`1!2.0rc1.post1.dev2`) | no version, ranges (`>=`, `~=`, `!=`), wildcard (`==1.*`), arbitrary equality (`===`), `pkg @ url`, `git+`/URL/path specs |
| jsr (`deno jsr:`) | `jsr:@scope/name@1.2.3` | anything else |

Options **before** the package are scanned fail-closed: only a small allowlist per launcher is recognized (`-y`, `--quiet`, `--python 3.12`, ...). Anything unlisted — a registry or index override (`--registry`, `--index-url`, `-i`), a requirements file, `--pip-args`, `--path`, `--editable`, `--config-file`, `--project`, `--directory`, `--cache-dir` (each of which can point `uv` at a different configuration or resolution root), a short cluster like `-yp`, a typo — refuses the whole command line, because an unrecognized option could change which package or registry is used. `-p/--python` accepts only a dotted version number (`3`, `3.12`, `3.12.1`); an interpreter path or a name is refused. With `npx -p <pinned>`, the positional that follows is the **bin name** to run and must look like one (`[a-z0-9][a-z0-9._-]*`). Options **after** the package belong to the package and are not scanned.

The environment is held to the same idea: `UV_CONFIG_FILE` and `XDG_CONFIG_HOME` join the forbidden env variables, since either can hand `uv`/`pip` a config file that overrides the index (`HOME` is provided by the sandbox, so a stdio server has no legitimate need to relocate its config directory).

### Package manager entry points (a denylist)

Pinning only helps if the launcher is the launcher. `node /usr/lib/node_modules/npm/bin/npx-cli.js evil` runs npx without ever saying `npx`, so the interpreter paths are also checked: the script an interpreter is given as its program (the first positional of `node`/`bun`/`ruby`/`python`/`deno run`, plus every path-like `-r`/`--require`/`--import` value) is **refused when it is a package manager entry point** — its expanded path contains `/node_modules/{npm,corepack,pnpm,yarn}/`, or its basename is one of `npx-cli.js npm-cli.js npm npx corepack pnpm yarn yarn.js gem bundle bundler pip pip3 pipx uv uvx`. Symlinks are resolved first (`File.realpath`, falling back to the lexical path when the file does not exist on the validating host); when the interpreter's flag scan cannot tell which token is the program, every non-option token is checked.

This is a **denylist**, and that is its limit: it covers the entry points of the mainstream package managers by name and by install location. It does not cover a copied or renamed entry script, a package manager installed under an unusual path, `node -e "require('npm/...')"` (inline code is refused by its own rule anyway), a wrapper script that execs one of these, or package managers not in the list. Treat it as closing the obvious bypass, not as a proof.

The refusal names the launcher, the offending spec, and the shape to write it in, e.g.

```
npx: package "@modelcontextprotocol/server-filesystem" is not pinned to an exact version.
Write it as @modelcontextprotocol/server-filesystem@<major>.<minor>.<patch>
(e.g. @modelcontextprotocol/server-filesystem@1.2.3); dist-tags (latest, next), ranges
(^, ~, >=, *, x), git/URL/tarball/path specs and npm: aliases are refused.
```

### Where it is enforced

- **Save time** — `McpServer` refuses to create a stdio server, or to change an existing one's `command`/`args`/`connection_type`, into an unpinned launcher or a package manager entry point (422 from `POST/PATCH /api/v1/mcp_servers`, error on `command`). The inline-code rule (`node -e …`) is spawn-time only.
- **Spawn time** — `validate_stdio_server!` refuses on every spawn path, server and worker alike. A refusal is written to the audit log as `mcp.servers.spawn_refused`. Its metadata is deliberately token-free: `launcher` (basename of the command), `arg_count`, `arg_index` (position of the offending token in the resolved argv, when the rule knows it), `rule` (a short stable name such as `package_pin`, `launcher_option`, `package_manager_entry`), `error_class` and `stage` (`server_validation` / `worker_validation`) — never the args, the message or env values, any of which may carry a secret. The worker posts its rows through `POST /api/v1/internal/audit_logs` with a 5 s, no-retry timeout; a failed post is logged and does not change the outcome (a refusal still raises, a native spawn still proceeds). Rows the worker reports are stored under the **worker's** account, with the owning account in `metadata.account_id` and the server name in `metadata.mcp_server_name`.

### Rows that already exist

Nothing is migrated or disabled. A pre-existing unpinned server:

- is **refused at its next spawn** (connect, health check, discovery, tool call) with the message above, and the audit log gets `mcp.servers.spawn_refused`. Only the **connection** job writes the message to the row (`status: error` / `last_error`); a refused health check sets `status: error` without a `last_error`, and a refused discovery only logs on the worker — so an existing server can show `status: error` with an old or empty `last_error`;
- **stays saveable** for status/last_error updates (so that report can land) until someone edits its `command`/`args`, at which point the edit must pin the package.

What the operator must do: edit each affected server's command/args to an exact version (`GET /api/v1/mcp_servers` lists them; after a connect attempt `last_error` carries the exact spec to fix), then reconnect. To find them without waiting for a spawn, look for `mcp.servers.spawn_refused` audit rows after deploying, or check each stdio server whose `args` contain a launcher package without `@<version>` / `==<version>`.

The seeded example servers (`db/seeds/mcp_example_servers.rb`, `mcp_servers_seeds.rb`, `ai_skills_seed.rb`) are pinned. Those seeds use `find_or_create_by!` on the name, so an already-seeded row keeps the command line it was created with; it is treated like any other existing row above.

## Native execution (the escape hatch)

Every stdio child normally runs inside the worker's transient `systemd-run` sandbox (`MCP_STDIO_SANDBOX_MODE`, default `required` — refuse rather than run unsandboxed; `available` — sandbox when possible, warn and run unsandboxed otherwise; `off` — never sandbox). Some servers genuinely need the host (device access, a host toolchain, a socket the sandbox hides). For those, and **only in core mode**, an operator can approve a single server to run natively.

- **Core mode only.** The hatch is unavailable whenever the SaaS layer is present (detected through the generic capability seam: `:subscriptions` or `:public_registration` registered by any extension). Approval requests are refused with 403 then, and an approval granted earlier goes dormant — the worker is told nothing — without being erased. Revocation is always allowed.
- **Its own permission and its own endpoint.** `POST /api/v1/mcp_servers/:id/native_execution` approves, `DELETE` revokes. Both require `mcp.servers.native_execution`, which is **not** part of `mcp.servers.write`: owner/admin profiles carry it, the manager and AI-specialist profiles (who can create and edit servers) do not. The permission is new, so **after deploying, run the role sync** (`rails db:seed` or `rails powernode:setup`, both call `Role.sync_from_config!`) — until it runs, no role holds it and every approval request is 403. It is never a create/update attribute: `capabilities` is not an accepted parameter there, and the worker-facing internal update strips it. No MCP tool exposes it to agents.
- **Only a pinned command line can be approved.** Approving a server whose command line fails the pinning rule or the entry-point denylist is refused with 422 (the row itself may predate the rule; the hatch does not grandfather it).
- **Bound to the command line.** Changing the server's `command`, `args` or `connection_type` clears the approval automatically (audited as a revoke with reason `command_changed`); approve again after reviewing the new command line.
- **Bypasses only the sandbox.** Command/argument/environment validation and package pinning still apply, unchanged. Note that `npx -p <pinned> <cmd>` runs `<cmd>` through a shell by npm's design; under the hatch that shell is unsandboxed too.
- **How the worker learns it.** The server computes `native_execution_approved: true` into the capabilities it hands the worker only when the approval is effective (approved, stdio, core mode). The worker reads it from that request body under the worker JWT — the same trust tier as `allow_network` and `allow_extended_commands`: whoever can speak to the worker as the server can already set those.
- **Audited.** `mcp.servers.native_execution_approve` / `_revoke` on the server (who, when; the launcher and argument count, never the arguments), and `mcp.servers.native_execution_spawn` from the worker every time a child actually runs unsandboxed (plus a WARN in the worker log naming the server and the sandbox mode).

The public API shows the state on every server: `native_execution: { available, approved, effective, approved_at, approved_by_id }` — `effective` is what the worker is actually told.

## Related

- `docs/concepts/mcp-and-tools.md` — the platform's own MCP tool registry (a different thing from the stdio servers an account registers).
- `docs/operations/mcp-environment-isolation.md` — isolating MCP connectors between environments.
