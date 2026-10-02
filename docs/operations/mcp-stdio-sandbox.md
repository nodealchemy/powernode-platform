# stdio MCP sandbox: behaviour and operator controls

> Status: active

How the worker runs a stdio MCP server's child process, what that changes for a server that worked before the sandbox, and how an operator widens its reach. For command pinning and the native-execution escape hatch see [mcp-stdio-servers.md](mcp-stdio-servers.md).

## Where a server's sandbox settings are set

**AI → MCP → Servers → Security** (`/app/ai/mcp/security`) lists every stdio server with its sandbox settings. Users with `mcp.servers.security_manage` can change them there; everyone else with `mcp.servers.read` sees them read-only. The same operation is available over the API:

```
PATCH /api/v1/mcp_servers/:id/security
{ "security": { "allow_network": true, "allow_extended_commands": false, "egress_allowlist": ["api.example.test"] } }
```

- **Its own permission.** `mcp.servers.security_manage` is **not** part of `mcp.servers.write`: the owner and admin roles carry it, the manager and AI-specialist profiles (who can create and edit servers) do not. It is checked with `has_permission?`, never by role. The endpoint also needs `mcp.servers.read`, since it answers with the server. The permission is new, so a deployed plane needs its role grants reconciled (`rails permissions:reconcile_role_grants`, which `rails-start.sh` runs on every boot; `db:seed` only syncs roles on a first install); until then no role holds it and every request is 403.
- **Only these three settings.** `allow_network`, `allow_extended_commands` and `egress_allowlist`. Any other key is refused with 422, and `strict_environment` stays console-only. Create and update (`mcp.servers.write`) still cannot set them: `capabilities` is not an accepted parameter there.
- **Partial and strict.** Only the keys sent change. The two flags must be JSON `true` or `false`; the allowlist must be an array of strings (`[]` clears it). Stdio servers only: the sandbox does not apply to http or websocket servers.
- **The model refuses, not the endpoint.** The request is merged into the stored capabilities and saved through `McpServer`'s own validations, so the console, this endpoint and the worker's spawn-time gate cannot disagree: `allow_network` and an allowlist cannot both be set; at most 20 allowlist entries; each entry an IP, a CIDR or a hostname; loopback, link-local, the cloud metadata address and full-open ranges refused.
- **Audited.** Every change writes `mcp.servers.security_update` (high severity): who, and the before and after of the three settings and which changed. A request that changes nothing writes no row, and a refused request changes and records nothing.
- **When it takes effect.** The worker reads the capabilities when it spawns a child, so a change applies to the **next spawn**; a child already running keeps the policy it started with.

## The sandbox

Every stdio child runs inside a transient `systemd-run` unit (`DynamicUser=yes`, one uid per account) with, among others, `ProtectSystem=strict`, `ProtectHome=yes`, `PrivateTmp=yes`, `NoNewPrivileges=yes`, `ProtectProc=invisible`, a `RuntimeMaxSec` equal to the call's timeout, and resource limits (`MCP_STDIO_SANDBOX_MEMORY_MAX` default `512M`, `MCP_STDIO_SANDBOX_TASKS_MAX` default `64`, `MCP_STDIO_SANDBOX_CPU_QUOTA` default `200%`). Server-supplied environment variables reach the child through a root-owned, mode-0600 `EnvironmentFile` that is deleted after the spawn, never through the command line.

### What changed for servers that predate it

| Change | Effect | What to do |
|---|---|---|
| The working directory is `/` (the systemd system-unit default: the sandbox sets no `WorkingDirectory=`) | A relative script argument (`node server.js`, `python ./main.py`) no longer resolves | Use absolute paths in `command` and `args` |
| `ProtectHome=yes` | `/home`, `/root` and `/run/user` are inaccessible, so a server installed under any of them cannot start | Install it somewhere readable (for example `/opt/...`) or use a pinned package launcher (`npx`, `uvx`) |
| `HOME` is `/var/cache/<account identity>` | Writable and persistent per account, so `npx` and `uvx` keep their package cache; nothing else is writable | Do not rely on files in the real home directory |
| `ProtectSystem=strict` | The whole filesystem is read-only apart from the account's cache directory and a private `/tmp` | A server must write only to its cache directory or `/tmp` (private to the unit) |

### Root, or a polkit grant

The sandbox needs the system service manager (`DynamicUser=` through `systemd-run` against the system bus), which refuses a non-root caller with "Access denied". `MCP_STDIO_SANDBOX_MODE` decides what happens when it cannot sandbox:

- `required` (the default): refuse to spawn at all. **On a worker not running as root every stdio call fails**, with an error naming the uid and the polkit requirement.
- `available`: sandbox when possible, and run **unsandboxed** with a warning in the worker log when not.
- `off`: never sandbox.

A non-root worker therefore needs either to run as root, or a polkit rule (or equivalent) authorizing it to manage transient systemd units, before `required` can work there. Setting `available` or `off` to get past this removes the containment for every stdio server; prefer fixing the privilege.

## Network access

Three mutually exclusive modes, chosen per server:

1. **Default, no network.** `PrivateNetwork=yes` and `IPAddressDeny=any`. The child cannot reach anything.
2. **`egress_allowlist`.** The child may reach only the resolver and the listed destinations. Hostnames are resolved fresh **at every spawn**, so a hostname that moves is followed, and resolved addresses in forbidden ranges are dropped (DNS rebinding cannot reach loopback or metadata through an allowed name). Everything else is denied.
3. **`allow_network: true`.** Unrestricted outbound network, except that these stay **denied**: loopback (`localhost`), link-local, the cloud metadata address `169.254.169.254`, and every address the host itself holds (a service bound to `0.0.0.0` is otherwise reachable through the host's LAN address). The local resolver stub stays reachable, so DNS works.

`allow_network` and an allowlist cannot be set together: the allowlist would be meaningless. Prefer an allowlist over `allow_network` whenever the destinations are known.

In modes 2 and 3 `RestrictAddressFamilies=AF_INET AF_INET6` is applied, so **`AF_UNIX` sockets are refused**: a child cannot talk to a local daemon through a Unix socket (the Docker socket, a database socket) even though loopback is blocked. Mode 1 applies no address-family restriction: its private network namespace isolates network traffic, and `AF_UNIX` is not what contains it there.

A destination blocked by the sandbox is a silent packet drop. The worker logs the policy it applied at each spawn (`stdio spawn network policy server=... mode=...`), with the resolved allow addresses and never the environment, which is where to look when a server "cannot reach X".

### Forbidden allowlist entries

Refused at save time, and filtered again after resolution at spawn time: `0.0.0.0/8`, `127.0.0.0/8`, `169.254.0.0/16` (including the metadata address), `::`, `::1` and `fe80::/10`, any full-open range (`0.0.0.0/0`, `::/0`), and IPv4-mapped IPv6 spellings of those. Numeric and hex pseudo-IP forms are refused.

## `allow_extended_commands`

By default a stdio server's `command` must be on the worker's allowlist of launchers. `allow_extended_commands: true` widens **only that command whitelist**; the argument checks (inline-code flags such as `node -e`, forbidden environment variables, package pinning) still apply, unchanged. Enabling it is a statement that this server's launcher is trusted: grant it per server, to the smallest set of servers that need it.

## Related

- [mcp-stdio-servers.md](mcp-stdio-servers.md): package pinning and native (unsandboxed) execution.
- `server/app/models/mcp_server.rb`: the validations this surface reuses.
- `worker/app/services/mcp_security_service.rb`: the spawn-time policy.
