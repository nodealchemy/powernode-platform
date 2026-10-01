# frozen_string_literal: true

require 'shellwords'
require 'digest'
require 'ipaddr'
require 'resolv'
require 'socket'

# Service for MCP security hardening in worker
# Provides command whitelist validation and environment sanitization
#
# MIRRORED BY server/app/services/mcp/security_service.rb (Mcp::SecurityService)
# — IMP-176a386fef98 ported this file's rules there (server-side
# Mcp::PromptService/Mcp::ResourceService/Mcp::SyncExecutionService spawn
# stdio MCP servers synchronously in the Rails request cycle and can't use
# this worker file directly — the two apps deploy separately). Kept in sync
# by server/spec/services/mcp/security_service_spec.rb's parity spec, which
# `require`s this file by relative path (spec-only) and asserts identical
# constants/verdicts against a shared adversarial fixture table — a change
# here that isn't ported there will fail that spec, not this file's own.
#
# SCOPE (IMP-97b6b1185748 review item 7): #validate_stdio_server! and its
# argv/env checks stop CASUAL inline-code smuggling through a command/args
# pair that's supposed to be "just run an interpreter against a script
# file" — they are NOT a sandbox on their own. Launchers like `npx -y
# <pkg>`, `uvx <pkg>`, `deno run -A <url>`, `bun x <pkg>`, and
# `pip install`-then-run all execute arbitrary code BY DESIGN — that's the
# entire point of a package launcher, and no argument-shape check can (or
# should try to) distinguish a legitimate package from a malicious one. The
# real security boundary is who is allowed to write server['command'] /
# server['args'] in the first place, plus the child-process isolation
# #spawn_stdio itself now wraps the spawned interpreter in (IMP-a50680fd53d8,
# MCP isolation Phase 1 T2: a transient systemd-run sandbox — DynamicUser,
# ProtectSystem=strict, ProtectHome, network deny-by-default, resource
# limits — see #spawn_stdio's own comment).
# NOTE (IMP-97b6b1185748 item 9): a `validate_stdio_execution!` variant used
# to live here (command:/env:/args: keyword API, returning {command:, env:}).
# `command grep`-ing worker/app turned up no caller besides its own spec —
# every real stdio spawn site goes through #validate_stdio_server!, which
# takes the `server` hash directly and returns the additional resolved
# `argv`. Removed rather than kept as unused dead code.
class McpSecurityService
  class SecurityError < StandardError; end
  class CommandNotAllowedError < SecurityError; end
  class EnvironmentViolationError < SecurityError; end
  # IMP-4689ce5a4acb — raised by #spawn_stdio when a stdio MCP child
  # exceeds its deadline. A StandardError, NOT a SecurityError, subclass:
  # a deadline expiry is not a security violation, and nothing rescues
  # SecurityError generically (confirmed by grep), so there is no
  # behavioral reason to nest it there. Review round 1 correction: the
  # original comment here claimed PromptService/ResourceService "gained
  # an explicit rescue" for this error — false, neither file changed at
  # all. Every one of the 7 stdio call sites (3 server, 4 worker) already
  # has its OWN `rescue StandardError` — either directly around
  # #spawn_stdio, or in the public method that calls it (e.g.
  # PromptService#execute_prompt wraps send_mcp_request →
  # send_stdio_request → spawn_stdio in one outer rescue) — and that
  # PRE-EXISTING catch-all is what maps this into each call site's own
  # error shape, with zero call-site code changes. See each call site's
  # own spec for the proof.
  class StdioTimeoutError < StandardError; end

  # IMP-a50680fd53d8 — raised by #spawn_stdio when MCP_STDIO_SANDBOX_MODE
  # is "required" (the default) and sandboxing cannot actually happen —
  # either this process isn't root (DynamicUser needs the system manager;
  # a non-root caller gets "Access denied" from systemd, see
  # #sandbox_unavailable_message) or systemd-run isn't on PATH. A
  # StandardError, not a SecurityError: refusing to run UNSANDBOXED is a
  # fail-CLOSED availability decision, not evidence the request itself was
  # malicious.
  class SandboxUnavailableError < StandardError; end

  # IMP-bd260c0b4c00 — raised when a sandboxed spawn has no account to key
  # its sandbox identity on (see .sandbox_identity). Refusing is the only
  # safe answer: falling back to a shared identity would let one tenant's
  # child read another's /proc/<pid>/environ and poison its package cache.
  # A SandboxUnavailableError so every existing caller rescue already
  # refuses it the same way.
  class SandboxAccountRequiredError < SandboxUnavailableError; end

  # Allowed commands for stdio MCP servers — bare NAMES only (IMP-b6be9d979e13:
  # this used to also list a partial, inconsistent set of hardcoded absolute
  # paths, e.g. "/usr/bin/node" but not "/usr/bin/npx" or any "/bin/*" path
  # at all — see ALLOWED_ABSOLUTE_COMMAND_DIRS below for how an absolute path
  # is now validated instead: derived from these names, not hand-listed).
  # NOTE: "/usr/bin/env" and bare "env" are deliberately NOT here — see
  # #raise_if_env_wrapper!.
  ALLOWED_COMMANDS = %w[
    npx
    node
    python
    python3
    ruby
    deno
    bun
  ].freeze

  # Extended commands enabled by configuration — bare NAMES only, same as
  # ALLOWED_COMMANDS (IMP-b6be9d979e13).
  EXTENDED_COMMANDS = %w[
    uvx
    uv
    pipx
    docker
    podman
    java
    dotnet
    go
  ].freeze

  # IMP-b6be9d979e13 BLOCKER: #base_command_in_allowed_list? used to accept
  # ANY path whose basename or trailing "/#{name}" matched an allowed name —
  # "/tmp/evil/node" and "./node" both passed as "node". A command is now
  # allowed in exactly two shapes: a bare whitelisted name (no "/" at all —
  # resolved through the WORKER's own PATH at spawn time, which the server
  # can never override, see FORBIDDEN_ENV_VARS/#build_stdio_env), or an
  # EXACT, full match against one of these directories joined with a
  # whitelisted name (e.g. "/usr/bin/node", never "/usr/bin/node2" or
  # "/usr/bin/node/../node"). Every other absolute path, every relative path
  # ("./node", "../x/node", "bin/node"), and any path containing whitespace
  # is refused outright — there is no per-server path configuration.
  ALLOWED_ABSOLUTE_COMMAND_DIRS = %w[/usr/bin /usr/local/bin /bin].freeze

  # Allowed environment variable prefixes
  ALLOWED_ENV_PREFIXES = %w[
    MCP_
    OPENAI_
    ANTHROPIC_
    GOOGLE_
    AZURE_
    AWS_
    GCP_
    HUGGING_FACE_
    COHERE_
    MISTRAL_
    PERPLEXITY_
  ].freeze

  # Explicitly allowed environment variables. NOTE (IMP-e2cba83ee39f):
  # PATH and HOME are deliberately NOT here — see FORBIDDEN_ENV_VARS and
  # #build_stdio_env — nor are PYTHONPATH/PYTHON_PATH/GEM_HOME/GEM_PATH,
  # each of which is a code-injection vector (arbitrary module/gem load
  # path) rather than a harmless locale/runtime setting. Round-3 review:
  # BUNDLE_PATH moved OUT of here and INTO FORBIDDEN_ENV_VARS — it's the
  # same "arbitrary gem load location" class as GEM_HOME/GEM_PATH, not a
  # harmless setting.
  ALLOWED_ENV_VARS = %w[
    USER
    LANG
    LC_ALL
    LC_CTYPE
    TERM
    TZ
    NODE_ENV
    RUBY_VERSION
    XDG_CONFIG_HOME
    XDG_DATA_HOME
    XDG_CACHE_HOME
    TMPDIR
    TEMP
    TMP
  ].freeze

  # Forbidden environment variables (security sensitive) — exact match.
  # See FORBIDDEN_ENV_PREFIXES below for the DYLD_* family. IMP-e2cba83ee39f
  # additions: PATH/HOME (a server-supplied PATH could point a bare
  # command name like "node" at an attacker binary resolved through it;
  # HOME can redirect config/rc-file loading the same way — the worker's
  # own values always win, see #build_stdio_env); the interpreter
  # module/gem search-path vars (NODE_PATH, RUBYLIB, PYTHONPATH,
  # PYTHON_PATH, PYTHONHOME, GEM_HOME, GEM_PATH) — each lets an arbitrary
  # installed (or planted) module/gem get loaded as a side effect of an
  # ordinary require/import; the interpreter auto-load-on-start vars
  # (PYTHONINSPECT, BUN_OPTIONS, PERL5OPT, PERL5LIB, JAVA_TOOL_OPTIONS,
  # _JAVA_OPTIONS, JDK_JAVA_OPTIONS, DOTNET_STARTUP_HOOKS) — each runs
  # attacker-supplied code/flags the moment the interpreter starts, no
  # inline-code flag needed at all. Round-2 review additions: the glibc
  # locale/NSS lookup-path vars (GCONV_PATH, GLIBC_TUNABLES, LOCPATH,
  # NLSPATH) — each can point glibc at an attacker-supplied shared
  # object/conversion module, the same class as LD_PRELOAD; the DNS/host
  # resolution vars (HOSTALIASES, RESOLV_HOST_CONF) — redirect hostname
  # resolution to an attacker-controlled file; uv's package-source vars
  # (UV_INDEX_URL, UV_EXTRA_INDEX_URL, UV_INDEX, UV_DEFAULT_INDEX,
  # UV_FIND_LINKS, UV_PYTHON_INSTALL_MIRROR, UV_PYPY_INSTALL_MIRROR) —
  # named individually rather than banning the whole UV_ prefix, since uv
  # has other, harmless UV_* config vars a real server may legitimately
  # set. Round-3 review additions: PYTHONUSERBASE — PROVEN code execution
  # (redirects Python's per-user site-packages dir, whose
  # usercustomize.py is auto-imported on interpreter startup — the same
  # "runs on start, no flag needed" class as PYTHONSTARTUP, just via a
  # different mechanism); BUNDLE_GEMFILE/RUBYGEMS_GEMDEPS/BUNDLE_PATH —
  # each can point Ruby's gem resolution at an attacker-supplied
  # Gemfile/gemdeps file or gem install location, the same class as
  # GEM_HOME/GEM_PATH (BUNDLE_PATH moved here from ALLOWED_ENV_VARS, not
  # merely removed from it); the extended-launcher vars CLASSPATH (java —
  # arbitrary .class/.jar load path, the JVM's equivalent of
  # LD_LIBRARY_PATH), DOCKER_HOST/DOCKER_CONFIG (docker/podman — redirect
  # the daemon socket or config/credential-helper location an attacker
  # controls), and the Go module-proxy/checksum-verification vars
  # (GOPROXY, GOFLAGS, GONOSUMDB, GONOSUMCHECK, GOSUMDB, GOINSECURE,
  # GOPRIVATE) — each can disable Go's module checksum verification or
  # redirect module fetches through an attacker-controlled proxy, a
  # supply-chain vector. Deliberately NOT added (deferred): the CA-trust
  # vars (NODE_EXTRA_CA_CERTS, DENO_CERT, DENO_TLS_CA_STORE) — some real
  # MCP deployments legitimately need a custom CA bundle for TLS
  # interception (corporate proxies), so this needs its own decision
  # rather than a blanket ban.
  FORBIDDEN_ENV_VARS = %w[
    LD_PRELOAD
    LD_LIBRARY_PATH
    DYLD_INSERT_LIBRARIES
    DYLD_LIBRARY_PATH
    RUBYOPT
    PYTHONSTARTUP
    NODE_OPTIONS
    BASH_ENV
    ENV
    CDPATH
    PATH
    HOME
    NODE_PATH
    RUBYLIB
    PYTHONPATH
    PYTHON_PATH
    PYTHONHOME
    PYTHONINSPECT
    GEM_HOME
    GEM_PATH
    BUN_OPTIONS
    PERL5OPT
    PERL5LIB
    JAVA_TOOL_OPTIONS
    _JAVA_OPTIONS
    JDK_JAVA_OPTIONS
    DOTNET_STARTUP_HOOKS
    GCONV_PATH
    GLIBC_TUNABLES
    LOCPATH
    NLSPATH
    HOSTALIASES
    RESOLV_HOST_CONF
    UV_INDEX_URL
    UV_EXTRA_INDEX_URL
    UV_INDEX
    UV_DEFAULT_INDEX
    UV_FIND_LINKS
    UV_PYTHON_INSTALL_MIRROR
    UV_PYPY_INSTALL_MIRROR
    PYTHONUSERBASE
    BUNDLE_GEMFILE
    RUBYGEMS_GEMDEPS
    BUNDLE_PATH
    CLASSPATH
    DOCKER_HOST
    DOCKER_CONFIG
    GOPROXY
    GOFLAGS
    GONOSUMDB
    GONOSUMCHECK
    GOSUMDB
    GOINSECURE
    GOPRIVATE
  ].freeze

  # Forbidden environment variable PREFIXES. DYLD_* (IMP-e2cba83ee39f round
  # 1) covers the whole macOS dynamic-linker family (DYLD_INSERT_LIBRARIES/
  # DYLD_LIBRARY_PATH are also listed explicitly above for clarity, but
  # this catches every other DYLD_* variable too, e.g. DYLD_FRAMEWORK_PATH).
  # LD_ (round 2 BLOCKER — review found LD_AUDIT/LD_PROFILE were still
  # ALLOWED in non-strict mode despite being the exact same "load an
  # arbitrary shared object into the process" class as LD_PRELOAD, which is
  # already named above) covers the whole glibc dynamic-linker family the
  # same way (LD_AUDIT, LD_PROFILE, LD_BIND_NOW, LD_ORIGIN_PATH, ...).
  # NPM_CONFIG_/PIP_/BUN_CONFIG_ (round 2) each redirect a package
  # manager's package/registry SOURCE (npm_config_registry, PIP_INDEX_URL,
  # a malicious bun registry, ...) — letting a server override where its
  # own dependencies are fetched from is a supply-chain vector, not a
  # harmless runtime setting. uv is deliberately NOT covered by a whole-
  # prefix ban here — see the named UV_* entries in FORBIDDEN_ENV_VARS
  # below instead.
  FORBIDDEN_ENV_PREFIXES = %w[DYLD_ LD_ NPM_CONFIG_ PIP_ BUN_CONFIG_].freeze

  # IMP-e2cba83ee39f: the ONLY variables passed through from the WORKER's
  # own process environment into a spawned stdio MCP server — everything
  # else (DATABASE_URL, REDIS_URL, WORKER_ID, JWT_SECRET_KEY, ...) must
  # NEVER reach the child. See #build_stdio_env and #spawn_stdio. TMPDIR is
  # deliberately server-overridable (unlike PATH/HOME) — a server pointing
  # its own child-scoped scratch dir elsewhere is accepted, not a security
  # boundary the way a binary-resolution or config-file path is.
  STDIO_ENV_PASSTHROUGH_KEYS = %w[PATH HOME LANG LC_ALL TZ TMPDIR].freeze

  # IMP-a50680fd53d8 review blocker 2 — a systemd EnvironmentFile is a tiny
  # KEY=VALUE parser, not shell/JSON: a key containing anything other than
  # this pattern (e.g. embedded whitespace or an '=') is ambiguous to it,
  # and a raw newline inside a VALUE injects an entire extra "line" the
  # parser reads as its own KEY=VALUE pair (e.g. smuggling in a bogus
  # LD_PRELOAD=... entry despite that name never appearing in the actual
  # key this env var was written under) — a validated env HASH KEY never
  # protects against a value that itself contains a newline. See
  # #write_sandbox_env_file / #format_sandbox_env_file_line.
  SANDBOX_ENV_FILE_KEY_PATTERN = /\A[A-Za-z_][A-Za-z0-9_]*\z/

  # IMP-bf72723ef161 — ranges an egress_allowlist entry, or a hostname
  # entry's RESOLVED IP, must never be allowed to name. Same list as
  # McpServer::FORBIDDEN_EGRESS_RANGES (server/app/models/mcp_server.rb) —
  # duplicated deliberately (defense in depth, not a shared gem): the
  # SERVER validates literal entries at save time, but a hostname's
  # resolved IP can only be checked HERE, at spawn time, because DNS
  # rebinding means a hostname validated safe when it was saved can
  # resolve to something forbidden by the time it's actually used. Both
  # literal entries AND resolved hostname IPs are re-checked here
  # uniformly — never trust the server-side check alone for something
  # this security-relevant (see #resolve_egress_allowlist).
  EGRESS_FORBIDDEN_RANGES = %w[
    0.0.0.0/8
    127.0.0.0/8
    169.254.0.0/16
    169.254.169.254/32
    ::/128
    ::1/128
    fe80::/10
  ].freeze

  # IMP-bf72723ef161 review amendment 3 — the well-known cloud-metadata
  # SSRF target (AWS/GCP/Azure instance metadata service), explicitly
  # denied on the allow_network=true path even though it's already
  # covered by the broader 169.254.0.0/16 EGRESS_FORBIDDEN_RANGES entry —
  # named separately here because #network_policy_argv's allow_network=true
  # branch builds its IPAddressDeny list from systemd's own "link-local"
  # TOKEN (verified empirically to expand to 169.254.0.0/16 + fe80::/64,
  # NOT the full fe80::/10), not from EGRESS_FORBIDDEN_RANGES, so this
  # address needs its own explicit deny entry in that specific path.
  EGRESS_METADATA_ADDRESS = '169.254.169.254'

  # IMP-bf72723ef161 review round 2 fix 3 — matches numeric/octal/hex
  # "pseudo-IP" forms IPAddr itself refuses to parse strictly (e.g.
  # "2130706433", "127.1", "0177.0.0.1", "0x7f.0.0.1", "0x7f000001"), but
  # that a vulnerable getaddrinfo/URL-parsing implementation downstream
  # may still accept and resolve as a real IP — a well-known SSRF bypass
  # for evading a naive string-based IP check. Same list/logic as
  # McpServer::EGRESS_NUMERIC_PSEUDO_IP_FORMAT (server/app/models/mcp_server.rb)
  # — duplicated deliberately, same reasoning as EGRESS_FORBIDDEN_RANGES.
  EGRESS_NUMERIC_PSEUDO_IP_FORMAT = /\A(0x[0-9a-fA-F]+|[0-9]+)(\.(0x[0-9a-fA-F]+|[0-9]+)){0,3}\z/

  # IMP-97b6b1185748: validate_command! only ever checked the *command*
  # string. server['args'] reached Open3.capture3 completely unchecked, so
  # a whitelisted command like "node" plus args ["-e", "<code>"] ran
  # arbitrary code. This maps each ALLOWED_COMMANDS interpreter (npx
  # included — see -c/--call below) to the short/long flags that run
  # inline code or otherwise need refusing.
  #
  # Shape per interpreter:
  #   blocked_short / blocked_long — always refused outright.
  #   blocked_long_prefixes — refused if the long flag's name is exactly
  #     this prefix, or starts with "<prefix>-" (e.g. "inspect" also
  #     catches "inspect-brk"/"inspect-wait", but not "inspector").
  #   path_exempt_short / path_exempt_long — refused UNLESS the flag's
  #     value looks like a real file path (#stdio_arg_looks_like_path?):
  #     `node -r ./preload.js` preloads a local script; `node -r some-pkg`
  #     runs arbitrary code from an arbitrary installed package purely as
  #     a require side effect. A stdin device path (/dev/stdin, ...) is
  #     never path-like here even though it starts with "/".
  #   mcp_module_short — like path_exempt, but for python's -m: consumes a
  #     value and is refused UNLESS that value looks like an MCP server
  #     module (#stdio_arg_looks_like_mcp_module?) — `-m mcp_server_git` is
  #     the ordinary way an MCP server is launched via `python -m`;
  #     `-m code`/`-m pdb`/`-m pip` are not.
  #   value_only_short — NOT blocked, but DOES consume a value that, when
  #     not attached to the same token, is a SEPARATE next-arg (python's
  #     -W/-X/-Q, node/bun's -C — round-6 CONFIRMED BY EXECUTION on this
  #     host: `python3 -X -c ...` / `node -C -e ...` really do swallow the
  #     next arg). Cluster scanning stops there either way, so e.g. the
  #     "c" in python's "-Wc" isn't misread as also carrying -c.
  #   optional_value_short — NOT blocked, MAY carry a value, but that
  #     value — if present at all — MUST be attached to the same token —
  #     a bare occurrence is already a COMPLETE flag and never reaches
  #     for a separate next arg. Currently unused (ruby's -W/-K moved OFF
  #     this shape in round 7 — see ruby_warning_short/ruby_encoding_short
  #     below — because round-5's real-spawn proof this is a DISTINCT
  #     shape from value_only_short (`ruby -W -e 'puts 1'` /
  #     `ruby -K -e 'puts 1'` both RAN the code under value_only_short's
  #     "no attached value → assume a separate one" logic) turned out to
  #     be necessary-but-not-sufficient: round-7's real-spawn proof found
  #     the ATTACHED-cluster form leaks too (`ruby -We`/`-W2e`/`-Kae`/
  #     `-Kue` all ran code) — "always exactly 1 token" was right, but
  #     "the token's tail is inert" was not; see below for what actually
  #     happens inside that tail). Kept defined for any future flag that
  #     really does have the simpler "attached value, if any, is inert"
  #     shape.
  #   ruby_warning_short (round 7, ruby's -W ONLY — CONFIRMED BY EXECUTION
  #     that node's -C and python's -W/-X do NOT do this) — within the
  #     SAME token: a following ":" makes the rest of the token an inert
  #     category value (stop scanning, like optional_value_short); a
  #     following digit 0/1/2 is consumed as the warning LEVEL and
  #     scanning RESUMES right after it (so "-W2e" reaches "e" and
  #     correctly raises); anything else, or nothing, means -W took
  #     nothing and scanning resumes from that same next character. Never
  #     a separate next-arg in any case. See #ruby_warning_flag_next_index.
  #   ruby_encoding_short (round 7, ruby's -K ONLY) — within the SAME
  #     token, ALWAYS consumes exactly the one character immediately
  #     after K (whatever it is) as its encoding value, then scanning
  #     RESUMES right after that character (so "-Kae"/"-Kue" reach "e"
  #     and correctly raise, while "-Ka"/"-Ke" with nothing further are
  #     fully consumed and safe). Never a separate next-arg.
  #   boolean_long — a long flag with NO attached "=" that is known to
  #     take no value at all, e.g. a hypothetical "--enable-source-maps"
  #     entry (currently empty everywhere — see #raise_on_long_flag!'s
  #     ambiguity rule below for why this MUST stay small and explicit).
  #
  # Deliberately NOT covered — no config surface to widen this, it's a
  # fixed audit of the whitelist, not a per-server allowlist:
  #   * EXTENDED_COMMANDS (uvx, uv, pipx, docker, podman, java, dotnet, go)
  #     — none has a widely-used inline-code flag matching this shape, and
  #     docker/podman's `-e` sets an ENVIRONMENT VARIABLE
  #     (`docker run -e KEY=value`), not code — blocking it here would
  #     break ordinary container invocations. allow_extended_commands only
  #     widens the COMMAND whitelist; it never relaxes this argument check.
  INLINE_CODE_RULES_BY_INTERPRETER = {
    'node' => {
      blocked_short: %w[e p i],
      path_exempt_short: %w[r],
      value_only_short: %w[C],
      optional_value_short: [],
      blocked_long: %w[eval print interactive loader experimental-loader env-file env-file-if-exists run],
      blocked_long_prefixes: %w[inspect],
      path_exempt_long: %w[require import],
      boolean_long: []
    },
    'bun' => {
      blocked_short: %w[e p i],
      path_exempt_short: %w[r],
      value_only_short: %w[C],
      optional_value_short: [],
      blocked_long: %w[eval print interactive loader experimental-loader env-file env-file-if-exists],
      blocked_long_prefixes: %w[inspect],
      path_exempt_long: %w[require import],
      boolean_long: []
    },
    # Letters per `ruby --help`, VERIFIED BY EXECUTION on this host
    # (IMP-97b6b1185748 round 6 sweep — `ruby -<X> -e 'puts :probe'` for
    # each; a real spawn either prints "probe" (X took no separate value,
    # -e was recognized as ruby's own flag) or errors trying to treat "-e"
    # itself as X's value):
    #   -e (inline code) — always blocked, not part of this sweep.
    #   -I: CONFIRMED takes a MANDATORY SEPARATE value (chdir/LoadError on
    #     "puts :probe" proved "-e" got swallowed as -I's load-path arg).
    #   -C: CONFIRMED takes a MANDATORY SEPARATE value ("Can't chdir to
    #     -e" proved the same swallow).
    #   -x: confirmed NO separate value is taken (printed "probe" — -x's
    #     directory argument, if any, must be attached, e.g. "-x/dir").
    #   -E: CONFIRMED takes a MANDATORY SEPARATE value ("unknown encoding
    #     name - -e" proved the swallow).
    #   -F, -l, -0, -T, -S: confirmed NO separate value is taken (each
    #     printed "probe", or in -T's case ruby itself refuses the bare
    #     flag before ever reaching further args).
    # All nine stay in blocked_short regardless of the above — an
    # unconditionally-raised flag's true value-consumption shape can't
    # cause a bypass (the raise happens before any value is examined) —
    # widening any of them into an allowed-with-conditions category isn't
    # what this sweep is for; it exists to CONFIRM none of them hide the
    # same mistake -W/-K did.
    #
    # -r stays the sole path-exempt flag (CONFIRMED mandatory separate
    # value — "No such file or directory -- puts :probe" is the same
    # swallow pattern as -I/-C/-E), same rule as node/bun.
    #
    # -W (warning level) and -K (legacy source encoding) were WRONGLY
    # modeled as value_only_short (assumed a mandatory value, separate if
    # not attached) — round-5 real-spawn proof: `ruby -W -e 'puts 1'` and
    # `ruby -K -e 'puts 1'` both RAN THE CODE. Real ruby's -W/-K take an
    # OPTIONAL value that, if present, must be ATTACHED to the same token
    # (-W2, -W:no-deprecated, -Ke) — a bare -W/-K is already a COMPLETE
    # flag and never reaches for a separate next arg. See
    # optional_value_short below (IMP-97b6b1185748 round 6).
    'ruby' => {
      blocked_short: %w[e I C x E F l 0 T S],
      path_exempt_short: %w[r],
      value_only_short: [],
      optional_value_short: [],
      ruby_warning_short: %w[W],
      ruby_encoding_short: %w[K],
      blocked_long: [],
      blocked_long_prefixes: [],
      path_exempt_long: [],
      boolean_long: []
    },
    # -c (inline code) always blocks regardless of value. -i is the
    # interactive REPL. -m is handled separately via mcp_module_short: an
    # MCP server launched with `python -m <package>` is the ordinary
    # pattern, but `-m code`/`-m pdb`/`-m pip`/`-m http.server` are not.
    # -W/-X/-Q take a value but aren't code execution themselves —
    # cluster scanning must stop there so e.g. "-Wc" (a -W value of "c")
    # isn't misread as also carrying -c.
    'python' => {
      blocked_short: %w[c i],
      path_exempt_short: [],
      mcp_module_short: %w[m],
      value_only_short: %w[W X Q],
      optional_value_short: [],
      blocked_long: [],
      blocked_long_prefixes: [],
      path_exempt_long: [],
      boolean_long: []
    },
    'python3' => {
      blocked_short: %w[c i],
      path_exempt_short: [],
      mcp_module_short: %w[m],
      # No -Q here (unlike 'python'): CONFIRMED BY EXECUTION on this host
      # that python3 rejects it outright ("Unknown option: -Q") — Python
      # 2's old-style-division flag, removed in Python 3 (IMP-97b6b1185748
      # round 7 tidy-up). 'python' keeps -Q since a real python2 install
      # would still accept it and this repo has no python2 to verify
      # against either way.
      value_only_short: %w[W X],
      optional_value_short: [],
      blocked_long: [],
      blocked_long_prefixes: [],
      path_exempt_long: [],
      boolean_long: []
    },
    # npx's -c/--call runs an arbitrary shell command directly — distinct
    # from (and more dangerous than) `npx -y <pkg>`, which is the ordinary
    # launcher pattern this service deliberately leaves alone (see the
    # class-level SCOPE note).
    'npx' => {
      blocked_short: %w[c],
      path_exempt_short: [],
      value_only_short: [],
      blocked_long: %w[call],
      blocked_long_prefixes: [],
      path_exempt_long: []
    }
  }.freeze

  # A dotted Python identifier (module/package path), e.g. "mcp_server_git"
  # or "awslabs.foo_mcp_server". Doesn't accept a leading dot, spaces, or
  # shell metacharacters — those are already caught earlier, but this
  # keeps the match intentionally narrow.
  MCP_MODULE_NAME_PATTERN = /\A[A-Za-z_]\w*(\.[A-Za-z_]\w*)*\z/.freeze

  # Deno's inline-code / interactive-REPL entry points, and most of its
  # other subcommands (task, install, compile, ...), are NOT the ordinary
  # "launch an MCP server" pattern (`deno run <script>` / `deno serve
  # <script>`) — see #raise_on_deno_subcommand!.
  DENO_ALLOWED_SUBCOMMANDS = %w[run serve].freeze

  # IMP-97b6b1185748 round 8: the ONLY global flags #deno_subcommand! may
  # skip before the subcommand — a small, explicit allowlist, fail-closed
  # by construction (see #deno_subcommand!'s comment for why this doesn't
  # fall back to "scan everything" the way node/bun/ruby/python do).
  DENO_BOOLEAN_GLOBAL_FLAGS = %w[-q --quiet].freeze
  DENO_VALUE_GLOBAL_FLAGS = %w[-L --log-level].freeze
  DENO_UNSTABLE_PREFIX = '--unstable'

  # A bare "-" argument tells these interpreters to read their PROGRAM from
  # stdin — but stdin is where this worker writes the MCP JSON-RPC request,
  # so "the program" would be whatever bytes land there. The various
  # /dev and /proc stdin device paths are the same trick spelled as a
  # "file". Refused outright regardless of position (ruby/node/python/
  # python3 as a top-level arg, deno/bun after their `run` subcommand) —
  # IMP-97b6b1185748 item 8.
  STDIN_DASH_INTERPRETERS = %w[node bun ruby python python3 deno].freeze

  # IMP-97b6b1185748 item 3 (round 4): matched against File.expand_path(value)
  # — NOT File.realpath, which would touch the filesystem and follow
  # symlinks. expand_path only resolves "." / ".." segments and internal
  # "//" lexically, so "/dev/./stdin", "/proc/self/fd//0" and
  # "/dev/fd/../fd/0" all normalize down to a form this pattern catches,
  # without ever stat-ing anything. The "/+" (not "/") at the front is
  # deliberate: expand_path does NOT collapse a repeated LEADING slash
  # (POSIX gives "//foo" implementation-defined meaning), so "//dev/stdin"
  # stays two slashes wide after normalization and still needs to match.
  STDIN_DEVICE_PATH_PATTERN = %r{\A/+(dev/(stdin|fd/0)|proc/(self|thread-self|\d+)/fd/0)\z}.freeze

  SHELL_METACHARACTER_PATTERN = /[;&|`$<>\r\n]/.freeze

  # IMP-97b6b1185748 item 1 (round 4): everything after the interpreter's
  # own script/module positional belongs to the TARGET PROGRAM, not the
  # interpreter — `node dist/index.js -p 3000` must not have "-p" read as
  # a node flag. npx is deliberately excluded: its whole argv (after -y
  # etc.) is package-selection plus package args in a shape this service
  # doesn't model, so it stays fully, conservatively scanned as before.
  STOP_AT_FIRST_POSITIONAL_INTERPRETERS = %w[node bun ruby python python3].freeze

  # IMP-2c760325c102 (MCP isolation Phase 1 T4) — PACKAGE-LAUNCHER PINNING.
  # A launcher (npx, `bun x`, uvx / `uv tool run`, `uv run --with`,
  # `pipx run`, deno's npm:/jsr: specifiers) resolves its package from a
  # public registry AT SPAWN TIME, so "whatever the registry serves right
  # now" is what runs — unless the spec names an EXACT version. Every
  # launcher invocation must therefore be pinned, and the operator's bar is
  # an exact version (not an integrity hash — see the docs page). Enforced
  # at spawn time (#validate_stdio_server!, via #raise_on_unpinned_package!)
  # AND at save time (the server's McpServer model calls the public
  # #package_pin_violation), independently of the native-execution hatch,
  # which bypasses only the sandbox.
  #
  # The option scan BEFORE the package positional is fail-closed by
  # construction, the same way DENO_BOOLEAN_GLOBAL_FLAGS is: only the
  # listed boolean / value / package / selector options are recognized,
  # and anything else (a registry or index override, a requirements file,
  # `--pip-args`, a short cluster like `-yp`, a typo) refuses the whole
  # command line rather than guessing whether it consumed the next token.
  # Options AFTER the positional belong to the package and are not scanned
  # (every launcher here stops option parsing at its first positional).
  PACKAGE_LAUNCHER_COMMANDS = %w[npx bun uvx uv pipx deno].freeze

  # An exact semver (npm/jsr): MAJOR.MINOR.PATCH, no leading zeros, optional
  # prerelease/build metadata. No "v" prefix, no "=" prefix, never a range
  # or dist-tag.
  EXACT_SEMVER_PATTERN = /(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?/.freeze

  # npm package spec: an optionally-scoped LOWERCASE name, "@", an exact
  # semver. Scoped names keep their leading "@" (the version separator is
  # the LAST "@"); a second "@" after the version, an uppercase name, an
  # npm: alias, a github:/git+/URL/tarball/file:/path spec all fail here.
  NPM_PINNED_PACKAGE_PATTERN = /\A(?:@[a-z0-9][a-z0-9._~-]*\/)?[a-z0-9][a-z0-9._~-]*@#{EXACT_SEMVER_PATTERN.source}\z/.freeze

  # jsr always requires a scope.
  JSR_PINNED_PACKAGE_PATTERN = /\A@[a-z0-9][a-z0-9-]*\/[a-z0-9][a-z0-9-]*@#{EXACT_SEMVER_PATTERN.source}\z/.freeze

  # deno's `npm:`/`jsr:` specifiers, with an optional entry subpath AFTER
  # the version (`npm:pkg@1.2.3/cli.js`).
  DENO_NPM_PINNED_SPECIFIER_PATTERN = /\Anpm:(?:@[a-z0-9][a-z0-9._~-]*\/)?[a-z0-9][a-z0-9._~-]*@#{EXACT_SEMVER_PATTERN.source}(?:\/[A-Za-z0-9._\/-]+)?\z/.freeze
  DENO_JSR_PINNED_SPECIFIER_PATTERN = /\Ajsr:@[a-z0-9][a-z0-9-]*\/[a-z0-9][a-z0-9-]*@#{EXACT_SEMVER_PATTERN.source}(?:\/[A-Za-z0-9._\/-]+)?\z/.freeze

  # An exact PEP 440 version: optional epoch, release segments, optional
  # pre (a/b/rc), post and dev segments. No wildcard (`1.*`), no local
  # version label.
  EXACT_PEP440_PATTERN = /(?:\d+!)?\d+(?:\.\d+)*(?:(?:a|b|rc)\d+)?(?:\.post\d+)?(?:\.dev\d+)?/.freeze

  # PyPI package spec: a PEP 503 name, optional extras, then "==<exact>"
  # (PEP 508) or "@<exact>" (uv's shorthand). Ranges (>=, ~=, !=), the
  # wildcard, arbitrary equality (===), a direct reference (`pkg @ url`),
  # git+/URL/path specs all fail here.
  PYPI_PINNED_PACKAGE_PATTERN = /\A[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?(?:\[[A-Za-z0-9._,-]+\])?(?:==|@)#{EXACT_PEP440_PATTERN.source}\z/.freeze

  # Options shared by `uvx` / `uv tool run` and `uv run`. Index/registry
  # steering (-i/--index/--index-url/--extra-index-url/--default-index/
  # --find-links), requirements/constraints files, --with-editable and
  # --allow-insecure-host are deliberately ABSENT: absent means refused.
  UV_COMMON_BOOLEAN_FLAGS = %w[
    -q --quiet -v --verbose -n --no-cache --offline --no-progress --no-config --no-index --refresh --reinstall
    --isolated --managed-python --no-managed-python --native-tls --no-native-tls --no-env-file
    --no-python-downloads --compile-bytecode --no-compile-bytecode --no-build --no-binary --no-sources
  ].freeze
  UV_COMMON_VALUE_FLAGS = %w[
    -p --python --python-preference --cache-dir --color --project --directory --config-file --link-mode
    --resolution --exclude-newer --prerelease --index-strategy --keyring-provider --python-platform
    --no-build-package --no-binary-package --reinstall-package --refresh-package -P --upgrade-package
    --fork-strategy
  ].freeze

  # Per-launcher option grammar for #package_launcher_pin_violation:
  #   boolean_flags  — take no value.
  #   value_flags    — take one value (attached with "=" on a long flag, or
  #                    the next token); the value is not a package.
  #   package_flags  — ADD a package (uvx/uv `--with`, pipx `--preinstall`);
  #                    each value (comma-separated for uv) must be pinned,
  #                    and the positional is still the package to pin.
  #   selector_flags — SELECT the package (npx `-p/--package`, uvx `--from`,
  #                    pipx `--spec`); must be pinned, and the positional is
  #                    then a bin/command NAME inside that package, not a
  #                    package spec.
  #   pinned         — :npm or :pypi, which pattern a spec is held to.
  #   positional     — :package (must be pinned unless a selector was given,
  #                    and must be present) or :script (`uv run`: a local
  #                    script/command, not pinned; only its --with is).
  PACKAGE_LAUNCHER_RULES = {
    'npx' => {
      boolean_flags: %w[-y --yes --no -q --quiet --no-install --prefer-online --prefer-offline --ignore-existing].freeze,
      value_flags: [].freeze,
      package_flags: [].freeze,
      selector_flags: %w[-p --package].freeze,
      pinned: :npm,
      positional: :package
    }.freeze,
    'bun x' => {
      boolean_flags: %w[-b --bun].freeze,
      value_flags: [].freeze,
      package_flags: [].freeze,
      selector_flags: [].freeze,
      pinned: :npm,
      positional: :package
    }.freeze,
    'uvx' => {
      boolean_flags: UV_COMMON_BOOLEAN_FLAGS,
      value_flags: UV_COMMON_VALUE_FLAGS,
      package_flags: %w[-w --with].freeze,
      selector_flags: %w[--from].freeze,
      pinned: :pypi,
      positional: :package
    }.freeze,
    'uv run' => {
      boolean_flags: (UV_COMMON_BOOLEAN_FLAGS + %w[
        --no-project --no-sync --locked --frozen --active --no-active --exact --all-extras --no-all-extras
        --all-groups --no-dev --dev --only-dev --no-default-groups --all-packages --no-editable --script --gui-script
      ]).freeze,
      value_flags: (UV_COMMON_VALUE_FLAGS + %w[--extra --group --only-group --no-group --package --env-file -m --module]).freeze,
      package_flags: %w[-w --with].freeze,
      selector_flags: [].freeze,
      pinned: :pypi,
      positional: :script
    }.freeze,
    'pipx run' => {
      boolean_flags: %w[-v --verbose -q --quiet --no-cache --system-site-packages --fetch-missing-python].freeze,
      value_flags: %w[--python].freeze,
      package_flags: %w[--preinstall].freeze,
      selector_flags: %w[--spec].freeze,
      pinned: :pypi,
      positional: :package
    }.freeze
  }.freeze

  # IMP-4689ce5a4acb — deadline for a stdio MCP child's full round trip
  # (write stdin, read stdout+stderr to EOF, exit). Mcp::McpTransportClient
  # and every worker job here spawn through #spawn_stdio synchronously
  # (job thread) — without a deadline, a hung MCP child pins that thread
  # forever. IMP-f010c9fc7051: this is the default for every caller that
  # does not pass `timeout:` (the async jobs). The synchronous
  # /api/v1/mcp/execute_stdio path receives the server's configured
  # deadline per request instead (JobsController, bounded by
  # MAX_STDIO_TIMEOUT_SECONDS below).
  DEFAULT_STDIO_TIMEOUT_SECONDS = 30

  # IMP-f010c9fc7051 — the largest per-request deadline
  # /api/v1/mcp/execute_stdio accepts; JobsController refuses anything
  # above it (422), so a request body can never hold a worker thread
  # longer than this. Parity-spec-verified identical to the server's
  # copy, which clamps its configured deadline to it.
  MAX_STDIO_TIMEOUT_SECONDS = 60

  # Grace period between SIGTERM and SIGKILL when a deadline expires —
  # gives a well-behaved child a chance to exit cleanly before the harder
  # signal.
  STDIO_TERM_GRACE_SECONDS = 2

  # Upper bound on a single IO.select call inside #spawn_stdio's read/
  # write loop, so the loop re-checks the overall deadline (and re-scans
  # which fds still need attention) at least this often rather than
  # blocking for the full remaining timeout in one select() call.
  STDIO_SELECT_SLICE_SECONDS = 0.2

  # IMP-a50680fd53d8 (MCP isolation Phase 1 T2) — every stdio MCP child
  # runs inside a transient `systemd-run` sandbox by default. Empirically
  # verified on a noble/systemd 255 host before this was written (real
  # systemd-run invocations, not documentation alone) — see the task's
  # probe notes for the exact commands.
  #
  # required: refuse to spawn UNSANDBOXED at all — fail closed
  #   (#SandboxUnavailableError) if sandboxing can't actually happen. This
  #   is the default: a silently-unsandboxed spawn is a worse outcome than
  #   a loud refusal.
  # available: sandbox when possible; if not (non-root, or systemd-run
  #   missing), fall back to an UNSANDBOXED spawn — but only after a WARN
  #   log naming exactly why, never silently.
  # off: never sandbox. This app's own specs run with this (set once by
  #   the spec helper, never by changing this constant) so the existing
  #   IMP-4689ce5a4acb real-spawn specs (deadline, pgroup, large stdin)
  #   keep working unprivileged/non-root, unchanged.
  SANDBOX_MODES = %w[required available off].freeze
  DEFAULT_SANDBOX_MODE = 'required'

  # DynamicUser requires the SYSTEM manager — confirmed empirically
  # (systemd-run against the system bus as a plain non-root user returns
  # "Access denied"; `--user` mode has no bus at all in a container
  # without a lingering session, and DynamicUser is documented as a
  # system-service-only feature regardless). There is no non-root default
  # path today; see #sandbox_unavailable_message and IMP-94977647c24c (hub
  # root drop), which must land a polkit grant (or equivalent) authorizing
  # this worker to manage transient systemd units BEFORE it can run
  # non-root under MCP_STDIO_SANDBOX_MODE=required.
  SANDBOX_REQUIRES_ROOT = true

  # IMP-bd260c0b4c00 — each ACCOUNT gets its own systemd "dynamic user"
  # NAME (not a real Unix account — NSS-only, exists only while at least
  # one unit using it is active), used for BOTH `User=` and
  # `CacheDirectory=` (created as /var/cache/<name>, owned by that user,
  # isolated from the real /var/cache via a private bind mount, and what
  # makes ProtectHome's otherwise-removed $HOME survive for npx/uvx's own
  # package cache; #spawn_stdio points `HOME` at it).
  #
  # Why not ONE shared name (this constant's previous shape): verified by
  # execution on systemd 255 that with one shared User=, concurrent
  # children of DIFFERENT tenants ran as the same uid — so one tenant's
  # MCP server read another's concurrent /proc/<pid>/environ (API tokens)
  # and wrote into the shared npx/uvx cache the other's `npx -y` executes.
  #
  # Why a pinned NAME per account rather than a bare per-unit DynamicUser:
  # two CONCURRENT units each given a plain `DynamicUser=yes` (no `User=`)
  # get two DIFFERENT dynamically-allocated UIDs, and the second one to
  # touch a shared CacheDirectory fails with "Permission denied". Pinning
  # `User=` makes every unit of ONE account share one uid (and so its
  # cache, which is what keeps npx caching working), while units of
  # DIFFERENT accounts get different uids (verified: distinct uids, and
  # the other account's cache directory is not even present in the
  # unit's mount namespace). ProtectProc=invisible + ProcSubset=pid then
  # hide other uids' processes entirely (verified: another account's pid
  # does not exist in /proc), so the environ leak is closed by two
  # independent layers.
  #
  # The name is a truncated SHA-256 of the account id: systemd user names
  # are limited to 31 characters, so `mcp-stdio-` + 21 hex characters
  # (84 bits) is the longest that fits. Hashing (rather than truncating
  # the UUID) matters because a UUIDv7's leading characters are its
  # timestamp — accounts created together would share a prefix and
  # collide. 84 bits makes a collision between two accounts negligible
  # (birthday bound ~2^42 accounts); there is no per-host registry to
  # detect one because none is needed at that size.
  #
  # Cache directories are per account and are NOT garbage-collected here:
  # each holds only that account's npx/uvx package cache, bounded by what
  # its own MCP servers install, and is recreated on demand. Reclaiming a
  # deleted account's directory is an operator action (`rm -rf
  # /var/cache/private/mcp-stdio-<hash>` on the worker host).
  SANDBOX_IDENTITY_PREFIX = 'mcp-stdio-'
  SANDBOX_IDENTITY_HEX_LENGTH = 21

  # Resource limits applied to every sandboxed stdio MCP child — ENV-
  # overridable, each with a documented default (see worker/.env.example),
  # evaluated fresh (not memoized) like .sandbox_mode, so a config change
  # takes effect without a restart.
  DEFAULT_SANDBOX_MEMORY_MAX = '512M'
  DEFAULT_SANDBOX_TASKS_MAX = '64'
  DEFAULT_SANDBOX_CPU_QUOTA = '200%'

  # Default for .sandbox_env_file_dir below — root-owned, mode-0700,
  # holding the per-spawn EnvironmentFile (see #write_sandbox_env_file).
  # Deliberately under /run (tmpfs-backed on every target host): a
  # secret's on-disk lifetime should be bounded by the boot, never by a
  # forgotten cleanup surviving a crash into persistent storage.
  DEFAULT_SANDBOX_ENV_FILE_DIR = '/run/powernode/mcp-stdio-env'

  class << self
    # Validate a command against the whitelist. `command` may be a single
    # token ("node") or a full command line ("node server.js") — only the
    # first word is checked against the whitelist.
    def validate_command!(command, allow_extended: false)
      return if command.blank?

      base_command = extract_base_command(command)
      validate_exact_base_command!(base_command, allow_extended: allow_extended)
      validate_command_arguments!(command)
    end

    # Check if a command is allowed (without raising)
    def command_allowed?(command, allow_extended: false)
      base_command = extract_base_command(command)
      return false if env_wrapper?(base_command)

      base_command_in_allowed_list?(base_command, allowed_commands(allow_extended))
    end

    # Sanitize environment variables
    def sanitize_environment(env, strict: false)
      return {} if env.blank?

      env.transform_keys(&:to_s).select do |key, _value|
        env_allowed?(key, strict: strict)
      end
    end

    # Check if an environment variable is allowed
    def env_allowed?(key, strict: false)
      key = key.to_s.upcase

      return false if env_forbidden?(key)
      return true if ALLOWED_ENV_PREFIXES.any? { |prefix| key.start_with?(prefix) }
      return true if ALLOWED_ENV_VARS.include?(key)

      !strict
    end

    def env_forbidden?(key)
      key = key.to_s.upcase

      FORBIDDEN_ENV_VARS.include?(key) || FORBIDDEN_ENV_PREFIXES.any? { |prefix| key.start_with?(prefix) }
    end

    # Validate environment and raise if forbidden vars present
    def validate_environment!(env)
      return if env.blank?

      forbidden = env.keys.map(&:to_s).map(&:upcase).select { |key| env_forbidden?(key) }

      return unless forbidden.any?

      raise EnvironmentViolationError,
            "Forbidden environment variables detected: #{forbidden.join(', ')}. " \
            'These variables could be used for code injection.'
    end

    # Validate the effective argv (command-string tokens after the first,
    # plus server['args']) for `command` — an ALREADY-RESOLVED single
    # token (e.g. "node", "/usr/bin/env"), never a raw multi-word command
    # line. allow_extended is deliberately NOT accepted here: it only ever
    # widens the COMMAND whitelist (validate_command!), never these
    # argument rules — there would be nothing for it to widen anyway,
    # since EXTENDED_COMMANDS carry no entry in INLINE_CODE_RULES_BY_INTERPRETER.
    def validate_stdio_args!(command, args)
      interpreter = interpreter_key_for(command)
      args = Array(args).map(&:to_s)

      # Metacharacter/NUL and stdin-device checks apply to EVERY arg,
      # including ones that belong to the target program rather than the
      # interpreter (see #scan_interpreter_flags!) — those are just as
      # capable of smuggling a shell metacharacter or a stdin device path.
      raise_on_shell_metacharacters!(args)
      raise_on_stdin_source_arg!(interpreter, args)

      return unless interpreter

      if interpreter == 'deno'
        raise_on_deno_subcommand!(args)
        return
      end

      rules = INLINE_CODE_RULES_BY_INTERPRETER[interpreter]
      return unless rules

      positional_index, ambiguous = scan_interpreter_flags!(args, rules, interpreter)
      raise_on_bun_shell_script!(args, positional_index, ambiguous) if interpreter == 'bun'
    end

    # IMP-2c760325c102 — the SAVE-time face of package-launcher pinning
    # (the server's McpServer model calls this from a validation): the
    # refusal message for `command` + `args`, or nil when every launcher
    # package in the command line is pinned (or the command is not a
    # launcher at all). Tokenizes the command string exactly as
    # #validate_stdio_server! does, so a launcher hidden in the command
    # string ("npx -y pkg") is held to the same rule as one in args. Never
    # raises: an unparseable command string is itself reported as the
    # violation, so a validation built on this can only ever add an error.
    def package_pin_violation(command, args)
      tokens = tokenize_command(command)
      return nil if tokens.empty?

      package_pin_violation_for_argv(tokens.first, tokens.drop(1) + Array(args).map(&:to_s))
    rescue CommandNotAllowedError => e
      e.message
    end


    # Shared validated-spawn entry point for every stdio MCP call site
    # (McpServerHealthCheckJob#ping_stdio_server, McpToolDiscoveryJob
    # #discover_stdio_tools, McpServerConnectionJob#establish_stdio_connection,
    # Mcp::McpTransportClient#execute_stdio_tool). Takes the `server` hash
    # (string-keyed, or indifferent-access) directly.
    #
    # `server['command']` is Shellwords-tokenized EXACTLY ONCE here, and
    # ONLY its first token is ever treated as the executable — every other
    # token, plus server['args'], becomes the returned `argv`. That single
    # resolved token is then validated as an EXACT command (no further
    # re-tokenizing downstream — IMP-97b6b1185748 item 7: re-splitting an
    # already-resolved token on whitespace let an escaped-space command
    # string like "node\\ -e x" tokenize once into a single token
    # "node -e" that then re-split, on a SECOND pass, back into "node" +
    # "-e" — passing the whitelist under a name that was never actually
    # checked against the argument rules). Callers MUST spawn with this
    # argv via the two-element `[cmd, cmd]` array form for the command
    # (`Open3.capture3(env, [command, command], *argv, ...)`), NEVER a
    # single command string — Ruby's Process.spawn/Open3 silently runs a
    # lone string command through `/bin/sh -c` when no additional args are
    # given, which would let a command string like "ruby -e p:ok" (with
    # args: []) execute arbitrary code even though every check in this
    # class passed (IMP-97b6b1185748 item 1).
    #
    # Always returns a STRING-keyed env — Open3.capture3 raises TypeError
    # if handed a symbol-keyed env Hash, so never deep_symbolize this.
    # Raises McpSecurityService::CommandNotAllowedError /
    # ::EnvironmentViolationError on a blocked command/env/args; callers
    # decide how to log/report that per their own return shape.
    #
    # @return [Array(String, Hash, Array<String>)] [command, string-keyed sanitized env, argv]
    def validate_stdio_server!(server)
      env = server['env'] || {}
      allow_extended = server.dig('capabilities', 'allow_extended_commands') == true
      strict_env = server.dig('capabilities', 'strict_environment') == true

      command_tokens = tokenize_command(server['command'])
      raise CommandNotAllowedError, 'No command specified for stdio MCP server' if command_tokens.empty?

      base_command = command_tokens.first
      combined_args = command_tokens.drop(1) + Array(server['args'] || [])

      validate_exact_base_command!(base_command, allow_extended: allow_extended)
      validate_environment!(env) if env.present?
      validate_stdio_args!(base_command, combined_args)
      raise_on_unpinned_package!(base_command, combined_args)

      final_env = build_stdio_env(env, strict_env: strict_env)

      [base_command, final_env, combined_args]
    rescue SecurityError => e
      record_spawn_refusal_audit(server, e)
      raise
    end

    # IMP-e2cba83ee39f: the shared spawn point for every stdio MCP call
    # site (McpServerHealthCheckJob#ping_stdio_server, McpToolDiscoveryJob
    # #discover_stdio_tools, McpServerConnectionJob#establish_stdio_connection,
    # Mcp::McpTransportClient#execute_stdio_tool) — the ONLY place
    # Open3 is invoked for a stdio MCP server, so `unsetenv_others: true`
    # can never be forgotten at a call site. Without it, Process.spawn/
    # Open3 MERGE the given `env` Hash ON TOP of the worker's own FULL
    # process environment rather than replacing it — every worker secret
    # (DATABASE_URL, REDIS_URL, WORKER_ID, JWT_SECRET_KEY, ...) would
    # otherwise leak into the spawned server's environment even though
    # `env` here is deliberately built to contain only the small
    # passthrough plus the validated server env (see #build_stdio_env).
    # `command`/`env`/`args` are exactly the 3-tuple `validate_stdio_server!`
    # returns; callers must not construct these themselves.
    #
    # IMP-4689ce5a4acb — Open3.capture3 had no deadline: a hung/misbehaving
    # MCP child pinned whatever thread called this forever (the worker's
    # job thread here; the server's Puma REQUEST thread for
    # PromptService/ResourceService, before IMP-abda86fb39be moved
    # execution here entirely). Ported to Open3.popen3 with pgroup: true
    # (the spawned process becomes its own process group leader) plus a
    # manual read/write loop against a monotonic deadline, so:
    #   - stdin is written and stdout/stderr are read in the SAME
    #     IO.select loop, never sequentially — writing all of stdin first
    #     would deadlock if the child produces enough stdout to fill ITS
    #     pipe buffer before draining stdin (the exact "large stdin +
    #     large stdout" case the specs cover).
    #   - stdin is closed the moment it's fully written (or immediately,
    #     if empty), so the child sees EOF on its own stdin.
    #   - on deadline expiry, or if the reap itself would block past the
    #     deadline, #terminate_process_group! signals the WHOLE process
    #     group (TERM, grace, then KILL) — reaping any grandchild the
    #     child forked too, not just the direct child — and this raises
    #     StdioTimeoutError rather than returning.
    # No Timeout.timeout: it runs the block on a SEPARATE thread and
    # raises into it asynchronously, which is unsafe for code doing raw
    # fd I/O (a raise mid-syscall can leave the child process/pipes in an
    # unknown state) — irrelevant here anyway, since the whole point is to
    # interrupt I/O we're doing ourselves, synchronously, via IO.select's
    # own bounded wait.
    #
    # IMP-a50680fd53d8 (MCP isolation Phase 1 T2) — SANDBOXING. Unless
    # MCP_STDIO_SANDBOX_MODE is "off", `command`/`args` are no longer
    # spawned directly: they're wrapped as the trailing argv of a
    # `systemd-run --pipe --wait --collect --unit=mcp-stdio-<uuid> -p ...`
    # invocation, and OPEN3 SPAWNS THAT WRAPPER instead — the read/write/
    # deadline loop above is unchanged, since it only ever cared about
    # pipes and a pid, not what's on the other end of them.
    #   - DynamicUser=yes + ProtectSystem=strict + ProtectHome=yes +
    #     PrivateTmp=yes + NoNewPrivileges=yes + ProtectProc=invisible +
    #     ProcSubset=pid, with User= pinned to the ACCOUNT's own identity
    #     (.sandbox_identity, IMP-bd260c0b4c00): every child of one
    #     account shares one uid (and so one cache), children of
    #     different accounts never do, and cannot see each other's
    #     processes. `account_id:` is REQUIRED when sandboxing — a nil or
    #     blank one raises SandboxAccountRequiredError, never a shared
    #     fallback. See SANDBOX_IDENTITY_PREFIX for why a pinned name,
    #     not a bare per-unit DynamicUser.
    #   - IPAddressDeny=any by DEFAULT — omitted entirely when the
    #     server's capabilities['allow_network'] (`allow_network:` below)
    #     is true, an admin-gated opt-in at the SAME trust tier as
    #     allow_extended_commands (IMP-427e98cae0be's serialization
    #     allowlist carries it to this process). NOT a per-host/CIDR
    #     allowlist: verified empirically that IPAddressAllow accepts a
    #     hostname, but systemd resolves it ONCE at unit start (a
    #     snapshot), which would silently go stale against a CDN-backed
    #     target — deliberately not built.
    #   - CacheDirectory=<the account's identity> + Environment=HOME=
    #     pointed at it, since ProtectHome removes $HOME entirely
    #     (verified: `/home` and `/root` become mode 0700, unreadable, and
    #     the root filesystem itself goes read-only under
    #     ProtectSystem=strict) — npx/uvx need a writable HOME for their
    #     own package cache.
    #   - RuntimeMaxSec=<timeout> as a systemd-ENFORCED backstop to the
    #     same deadline this method already tracks in Ruby, independent
    #     of whether our own kill path ever runs.
    #   - MemoryMax/TasksMax/CPUQuota resource limits (ENV-overridable,
    #     see the DEFAULT_SANDBOX_* constants).
    #   - EnvironmentFile=<0600 root-owned file, deleted in this method's
    #     `ensure`> for EVERY server-supplied env var, never `--setenv`/
    #     `Environment=` — verified empirically that `--setenv` value IS
    #     readable by ANY local user via a plain `systemctl show -p
    #     Environment`, even though the unit itself was started by root;
    #     an EnvironmentFile's path shows there but its CONTENT never
    #     does, and the child still receives it correctly. Only this
    #     process's OWN passthrough keys (STDIO_ENV_PASSTHROUGH_KEYS —
    #     PATH/HOME/LANG/etc., never server-supplied secrets, and HOME
    #     always overridden to the CacheDirectory above) go via
    #     `--setenv`, since those were never secret. Classifying which
    #     server-supplied vars "look" secret was rejected as fragile —
    #     ALL of them go through the file, uniformly.
    #   - #terminate_process_group! additionally runs `systemctl stop
    #     <unit>` — verified empirically that killing the systemd-run
    #     CLIENT process (even its whole local process group) does NOT
    #     stop the actual sandboxed unit, which keeps running as an orphan
    #     under systemd's own cgroup, entirely decoupled from the
    #     client's process group. Only `systemctl stop <the same
    #     generated --unit= name>` reaches it.
    #
    # required (default) vs available vs off: see SANDBOX_MODES above.
    # `allow_network:`, `timeout:` and `account_id:` are the only sandbox-
    # relevant arguments a caller passes in — the unit name, resource
    # limits and env-file path are generated fresh, internally, every call.
    # `account_id:` (the owning account of the MCP server, already on the
    # caller's payload) selects the sandbox identity; it is ignored when
    # sandboxing is off.
    #
    # @return [Array(String, String, Process::Status)] [stdout, stderr, status]
    # @raise [StdioTimeoutError] if the child doesn't finish within `timeout`
    # @raise [SandboxUnavailableError] if mode is "required" and sandboxing isn't possible
    # @raise [SandboxAccountRequiredError] if sandboxed and account_id is nil/blank
    def spawn_stdio(command, env, args, stdin_data:, timeout: DEFAULT_STDIO_TIMEOUT_SECONDS, allow_network: false,
                     egress_allowlist: [], mcp_server_id: nil, account_id: nil)
      require 'open3'

      sandboxed = sandbox_for_this_call?
      # Checked BEFORE the env file is written: a missing account must
      # refuse without leaving a secret on /run or spawning anything.
      sandbox_identity(account_id) if sandboxed
      unit_name = sandboxed ? "mcp-stdio-#{SecureRandom.uuid}" : nil
      # Only the SERVER-supplied portion goes in the file — this
      # process's own passthrough keys (PATH/HOME/LANG/...) go via
      # --setenv inside #sandboxed_spawn_argv instead. This split isn't
      # just "where secrets are safer" — it's REQUIRED for HOME's own
      # override to take effect at all: systemd applies EnvironmentFile=
      # AFTER Environment=/--setenv=, so if this file's own HOME entry
      # (the worker's real $HOME, part of the passthrough) survived here
      # too, it would silently win over the CacheDirectory HOME
      # #sandboxed_spawn_argv sets — verified empirically (a real
      # sandboxed child saw the worker's own $HOME, not the sandbox's,
      # until this exclusion was added).
      env_file_path = sandboxed ? write_sandbox_env_file(env.except(*STDIO_ENV_PASSTHROUGH_KEYS)) : nil

      # IMP-a50680fd53d8 review blocker 3 — this outer begin/ensure wraps
      # BOTH #sandboxed_spawn_argv (formats/validates the env file's own
      # content — see #format_sandbox_env_file_line — and can raise) AND
      # the Open3.popen3 call itself (can raise Errno::ENOENT if `command`
      # doesn't exist, or Errno::EMFILE under fd exhaustion). The PREVIOUS
      # inner begin/ensure (still below, for the read/select loop) only
      # started AFTER popen3 returned successfully, so a popen3 failure
      # skipped its cleanup entirely and left the 0600 env file on /run
      # forever — a real leak, not a hypothetical one. `cleanup_sandbox_env_file`
      # now lives in THIS ensure so every raise path from here on is covered.
      begin
        spawn_env, spawn_command, spawn_args =
          if sandboxed
            sandboxed_spawn_argv(command, args, env: env, account_id: account_id, unit_name: unit_name,
                                                env_file_path: env_file_path, timeout: timeout, allow_network: allow_network,
                                                egress_allowlist: egress_allowlist, mcp_server_id: mcp_server_id)
          else
            [ env, command, Array(args) ]
          end

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        stdin_io, stdout_io, stderr_io, wait_thr = Open3.popen3(
          spawn_env, [ spawn_command, spawn_command ], *spawn_args, unsetenv_others: true, pgroup: true
        )
        pid = wait_thr.pid
        pending_stdin = stdin_data.to_s
        stdout_buf = +''
        stderr_buf = +''
        stdin_io.close if pending_stdin.empty?

        begin
          loop do
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            raise_stdio_timeout!(pid, wait_thr, command, timeout, unit_name: unit_name) if remaining <= 0

            read_fds = [ stdout_io, stderr_io ].reject(&:closed?)
            write_fds = stdin_io.closed? ? [] : [ stdin_io ]
            break if read_fds.empty? && write_fds.empty?

            ready = IO.select(read_fds, write_fds, nil, [ remaining, STDIO_SELECT_SLICE_SECONDS ].min)
            next unless ready

            readable, writable, = ready

            writable&.each do
              begin
                written = stdin_io.write_nonblock(pending_stdin, exception: false)
                pending_stdin = pending_stdin.byteslice(written..) if written.is_a?(Integer)
              rescue Errno::EPIPE
                # Child closed its stdin (or already exited) before we
                # finished writing — not our error to raise; stop trying.
                pending_stdin = ''
              end
              stdin_io.close if pending_stdin.empty?
            end

            readable&.each do |io|
              chunk = io.read_nonblock(65_536, exception: false)
              case chunk
              when String
                (io.equal?(stdout_io) ? stdout_buf : stderr_buf) << chunk
              when nil
                io.close
              end
              # :wait_readable → spurious wakeup, nothing to append yet.
            end
          end

          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          unless remaining.positive? && wait_thr.join(remaining)
            raise_stdio_timeout!(pid, wait_thr, command, timeout, unit_name: unit_name)
          end

          [ stdout_buf, stderr_buf, wait_thr.value ]
        rescue StdioTimeoutError
          # raise_stdio_timeout! already ran #terminate_process_group! before
          # raising this — re-raise as-is rather than killing the (already
          # dead) group a second time via the broader rescue below.
          raise
        rescue Exception => e # rubocop:disable Lint/RescueException
          # IMP-4689ce5a4acb review round 1 — an Interrupt, a Thread#raise
          # injected from elsewhere, or an unexpected IOError inside the
          # select loop used to just unwind through the `ensure` below,
          # which only closes OUR pipe fds — the CHILD (and anything in its
          # process group) kept running with no deadline left to catch it,
          # since the deadline check only fires from inside the loop's own
          # normal iteration. Kill it here too, on ANY exception, before
          # propagating.
          terminate_process_group!(pid, wait_thr, unit_name: unit_name)
          raise e
        ensure
          stdin_io.close unless stdin_io.closed?
          stdout_io.close unless stdout_io.closed?
          stderr_io.close unless stderr_io.closed?
        end
      ensure
        # IMP-a50680fd53d8 review blocker 3 — this OUTER ensure (see the
        # matching comment above the outer `begin`) covers a crash in
        # #sandboxed_spawn_argv or Open3.popen3 itself, not just the
        # read/select loop above it; a 0600 root-owned secret must not
        # survive ANY exit path from here on (success, StdioTimeoutError,
        # any other exception, or a popen3-level Errno::ENOENT/EMFILE).
        cleanup_sandbox_env_file(env_file_path) if env_file_path
      end
    end

    # IMP-bd260c0b4c00 — the per-account sandbox identity (see
    # SANDBOX_IDENTITY_PREFIX above): the `User=`/`CacheDirectory=` name
    # for every sandboxed child of this account. Deterministic, so an
    # account's concurrent and successive children share one uid and one
    # cache; case/whitespace-normalized so one account never gets two.
    # A nil or blank account_id raises — there is deliberately no shared
    # fallback identity.
    #
    # @param account_id [String, nil]
    # @return [String] e.g. "mcp-stdio-3f9a1c0b7d2e4a5b6c8d1"
    # @raise [SandboxAccountRequiredError] if account_id is nil or blank
    def sandbox_identity(account_id)
      normalized = account_id.to_s.strip.downcase
      if normalized.empty?
        raise SandboxAccountRequiredError,
              'a sandboxed stdio MCP spawn requires an account_id to key its sandbox identity ' \
              '(refusing to fall back to a shared identity)'
      end

      "#{SANDBOX_IDENTITY_PREFIX}#{Digest::SHA256.hexdigest(normalized)[0, SANDBOX_IDENTITY_HEX_LENGTH]}"
    end

    # IMP-f010c9fc7051 — true only for a deadline JobsController may hand
    # to #spawn_stdio from a request body: an Integer (not a numeric
    # string, a Float or a boolean) in 1..MAX_STDIO_TIMEOUT_SECONDS.
    def acceptable_stdio_timeout?(value)
      value.is_a?(Integer) && value.between?(1, MAX_STDIO_TIMEOUT_SECONDS)
    end

    # Resolves MCP_STDIO_SANDBOX_MODE — "required" (default), "available"
    # or "off" (see SANDBOX_MODES above). Evaluated fresh on every call,
    # never memoized, so a config change takes effect without a restart. An unknown
    # value (typo, unset-but-non-blank) falls back to DEFAULT_SANDBOX_MODE
    # rather than silently matching neither branch below — this is a
    # fail-closed setting, so an unrecognized value must not be treated as
    # "off".
    def sandbox_mode
      value = ENV['MCP_STDIO_SANDBOX_MODE'].to_s.strip.downcase
      SANDBOX_MODES.include?(value) ? value : DEFAULT_SANDBOX_MODE
    end

    # IMP-2c760325c102 — where spawn-time security events go: an object
    # responding to #spawn_refused(server, error) and
    # #native_execution_spawn(mcp_server_id:, account_id:, sandbox_mode:)
    # (Mcp::SpawnAuditReporter, wired by the worker at boot — see
    # config/boot.rb). nil means no reporting (the spec suite's default, so
    # no spec ever makes a real audit HTTP call by accident). Injected
    # rather than hardcoded because this class is plain Ruby with no
    # knowledge of the backend API client, and because a reporter that
    # fails must never change a spawn verdict — see
    # #record_spawn_refusal_audit / #record_native_execution_bypass.
    attr_accessor :audit_reporter

    private

    # Per-side hook called by the shared #validate_stdio_server! on EVERY
    # refusal (the server's Mcp::SecurityService has its own, writing the
    # AuditLog row directly). Never raises: the refusal itself is what
    # matters, and it is re-raised by the caller regardless.
    def record_spawn_refusal_audit(server, error)
      audit_reporter&.spawn_refused(server, error)
    rescue StandardError => e
      logger.error("[McpSecurityService] failed to report a stdio spawn refusal to the audit log: #{e.class}: #{e.message}")
    end

    # The native escape hatch was exercised for this spawn (see
    # #spawn_stdio's `native_execution:`): say so loudly, and durably.
    def record_native_execution_bypass(mcp_server_id:, account_id:)
      mode = sandbox_mode
      logger.warn(
        "[McpSecurityService] native execution is approved for MCP server #{mcp_server_id} — running this stdio " \
        "MCP child UNSANDBOXED (MCP_STDIO_SANDBOX_MODE=#{mode})."
      )
      audit_reporter&.native_execution_spawn(mcp_server_id: mcp_server_id, account_id: account_id, sandbox_mode: mode)
    rescue StandardError => e
      logger.error("[McpSecurityService] failed to report a native stdio spawn to the audit log: #{e.class}: #{e.message}")
    end

    # Decides, for THIS #spawn_stdio call, whether to actually wrap the
    # spawn in a sandbox — the single place #spawn_stdio's mode dispatch
    # lives, so its own body only ever asks "sandboxed or not", never
    # "which mode". Raises SandboxUnavailableError for "required" when
    # unavailable (fail closed); logs a WARN and returns false for
    # "available" (never a silent unsandboxed fallback).
    def sandbox_for_this_call?
      mode = sandbox_mode
      return false if mode == 'off'
      return true if sandbox_available?

      raise SandboxUnavailableError, sandbox_unavailable_message if mode == 'required'

      logger.warn(
        "[McpSecurityService] MCP_STDIO_SANDBOX_MODE=available but sandboxing is unavailable " \
        "(#{sandbox_unavailable_message}) — running this stdio MCP child UNSANDBOXED."
      )
      false
    end

    # Mirrors Mcp::McpTransportClient#logger: uses the worker's own
    # application logger when available (this is a plain Ruby class, not
    # a Rails app — `Rails.logger` doesn't exist here), falling back to
    # STDOUT so this never raises in a context (e.g. a bare script) where
    # PowernodeWorker isn't loaded.
    def logger
      @logger ||= if defined?(PowernodeWorker) && PowernodeWorker.application.respond_to?(:logger)
                    PowernodeWorker.application.logger
                  else
                    require 'logger'
                    Logger.new($stdout)
                  end
    end

    # DynamicUser needs the SYSTEM manager (empirically confirmed: a
    # non-root `systemd-run` against the system bus returns "Access
    # denied"; `--user` mode has no bus in a container without a
    # lingering session, and is documented as unsupported for
    # DynamicUser regardless of that). There is no non-root path today —
    # see SANDBOX_REQUIRES_ROOT's own comment and IMP-94977647c24c.
    def sandbox_available?
      (!SANDBOX_REQUIRES_ROOT || Process.uid.zero?) && !systemd_run_path.nil?
    end

    # Resolves systemd-run via THIS process's own PATH (never a
    # hardcoded, distro-specific absolute path) — reused both to decide
    # #sandbox_available? and, when sandboxing, as the actual argv[0] so
    # the exec form is unambiguous.
    def systemd_run_path
      ENV['PATH'].to_s.split(File::PATH_SEPARATOR).map { |dir| File.join(dir, 'systemd-run') }
                 .find { |path| File.executable?(path) }
    end

    def sandbox_unavailable_message
      return 'systemd-run was not found on PATH' if systemd_run_path.nil?

      "this worker is not running as root (uid=#{Process.uid}) — DynamicUser requires the system " \
        'manager, which refuses a non-root caller with "Access denied"; a non-root worker needs a ' \
        'polkit grant (or equivalent) authorizing it to manage transient systemd units before ' \
        'MCP_STDIO_SANDBOX_MODE=required can work here (see IMP-94977647c24c)'
    end

    # Builds the systemd-run-wrapped [env, command, args] #spawn_stdio
    # actually spawns via Open3.popen3, once sandboxing is confirmed
    # active for this call. `env` here is the FULL resolved env
    # #validate_stdio_server! produced (this process's own passthrough
    # keys merged with the sanitized server env, per #build_stdio_env) —
    # split back apart here into "ours" (STDIO_ENV_PASSTHROUGH_KEYS, sent
    # via --setenv, never secret) and "the server's" (everything else,
    # sent via the EnvironmentFile at env_file_path, written by the
    # caller) because ONLY the split matters for where each half is
    # allowed to go — see #spawn_stdio's own comment for why.
    def sandboxed_spawn_argv(command, args, env:, account_id:, unit_name:, env_file_path:, timeout:, allow_network:,
                              egress_allowlist: [], mcp_server_id: nil)
      identity = sandbox_identity(account_id)
      passthrough = env.slice(*STDIO_ENV_PASSTHROUGH_KEYS).except('HOME')

      argv = [
        systemd_run_path,
        '--pipe', '--wait', '--collect', '--quiet',
        "--unit=#{unit_name}",
        '-p', 'DynamicUser=yes',
        '-p', "User=#{identity}",
        '-p', 'ProtectSystem=strict',
        '-p', 'ProtectHome=yes',
        # IMP-bd260c0b4c00 — other uids' processes do not exist in this
        # unit's /proc at all, so another account's /proc/<pid>/environ
        # cannot even be opened. Defense in depth behind the per-account
        # User=.
        '-p', 'ProtectProc=invisible',
        '-p', 'ProcSubset=pid',
        '-p', 'PrivateTmp=yes',
        '-p', 'NoNewPrivileges=yes',
        '-p', "RuntimeMaxSec=#{timeout}",
        # IMP-a50680fd53d8 review blocker 4 — bounds systemd's OWN stop job
        # (triggered by our `systemctl stop <unit>` in
        # #terminate_process_group!, or by RuntimeMaxSec above) to the same
        # grace period the local TERM/KILL sequence already uses, so the
        # unit's processes are force-killed on that bound even if nothing
        # local is left around to observe it (see #stop_sandboxed_unit!).
        '-p', "TimeoutStopSec=#{STDIO_TERM_GRACE_SECONDS}",
        '-p', "MemoryMax=#{sandbox_memory_max}",
        '-p', "TasksMax=#{sandbox_tasks_max}",
        '-p', "CPUQuota=#{sandbox_cpu_quota}",
        '-p', "CacheDirectory=#{identity}",
        '-p', "EnvironmentFile=#{env_file_path}"
      ]
      argv += network_policy_argv(allow_network: allow_network, egress_allowlist: egress_allowlist,
                                   mcp_server_id: mcp_server_id)
      passthrough.each { |key, value| argv += [ "--setenv=#{key}=#{value}" ] }
      argv += [ "--setenv=HOME=/var/cache/#{identity}" ]
      argv += [ '--', command, *Array(args) ]

      # The systemd-run CLIENT's OWN environment is deliberately NOT the
      # sandboxed child's env (`env` above) — that would put every
      # server-supplied var, secrets included, into the CLIENT process's
      # own environment too (readable via /proc/<client-pid>/environ by
      # root), for no benefit: the client only needs enough PATH to
      # exist; systemd-run's argv0 here is already an absolute path.
      [ { 'PATH' => ENV['PATH'].to_s }, argv.first, argv.drop(1) ]
    end

    # IMP-bf72723ef161 — the property set that governs a sandboxed spawn's
    # network reach. THREE mutually exclusive modes (allow_network=true +
    # a non-empty egress_allowlist together is refused server-side at save
    # time — see McpServer's own validation — so if both somehow reached
    # here anyway, the narrower allowlist branch wins, since it's checked
    # first):
    #
    # 1. egress_allowlist present: PrivateNetwork is NEVER set for this
    #    mode — confirmed empirically that it isolates the unit into its
    #    OWN network namespace with only a disconnected loopback, no route
    #    to the host's DNS resolver at all (a real `getent hosts` inside
    #    it failed outright). RestrictAddressFamilies=AF_INET AF_INET6
    #    closes the AF_UNIX gap that leaves open (confirmed: without it, a
    #    plain AF_UNIX socket() call succeeds; with it, EAFNOSUPPORT).
    #    IPAddressAllow = the resolver stub address(es) (see
    #    #resolver_stub_addresses — NOT all of "localhost": that would
    #    expose every OTHER loopback service on the host) plus every
    #    resolved, non-forbidden IP from the allowlist itself (see
    #    #resolve_egress_allowlist). IPAddressDeny=any last.
    #
    # 2. allow_network true (IMP-bf72723ef161 review — closes a gap in the
    #    ORIGINAL IMP-a50680fd53d8 allow_network=true path, which omitted
    #    ALL IP filtering: the child could reach every loopback service on
    #    the host and the cloud metadata IP). Confirmed empirically:
    #    IPAddressDeny=localhost + link-local + the metadata /32, PLUS
    #    IPAddressAllow=<resolver stub>, lets DNS through (systemd's
    #    ALLOW-WINS-OVER-DENY precedence) while a DIFFERENT loopback
    #    listener stays blocked, the metadata address stays blocked, and a
    #    non-loopback, non-link-local address (standing in for "the rest
    #    of the internet" — this dev cell has no real egress to test
    #    against) stays reachable. `link-local` is systemd's own TOKEN
    #    (confirmed to expand to 169.254.0.0/16 + fe80::/64) — narrower
    #    than EGRESS_FORBIDDEN_RANGES' fe80::/10, which is why
    #    EGRESS_METADATA_ADDRESS is still named explicitly here rather
    #    than assumed covered. Review round 2 fix 4 additionally denies
    #    every address THIS HOST ITSELF has (#host_own_addresses) — a
    #    service bound to 0.0.0.0 (worker-web/Puma, a local Ollama or
    #    Postgres, ...) is reachable via the host's own LAN IP
    #    specifically, which none of the generic ranges above name.
    #
    # 3. Neither: unchanged full deny (PrivateNetwork=yes + IPAddressDeny=any).
    #
    # SYSTEMD ARGV QUIRK, verified empirically and load-bearing for the
    # shape below: a systemd-run transient property SPECIAL TOKEN
    # (localhost/link-local/any/multicast) fails to parse ("Failed to
    # parse IP address prefix: localhost") the moment it shares a single
    # space-separated `-p Prop=...` VALUE with anything else — even a
    # SECOND special token. Plain literal IPs/CIDRs CAN be space-joined in
    # one value, but to sidestep this bug uniformly (rather than special-
    # casing tokens vs literals), every entry below — token or literal —
    # gets its OWN `-p` flag; repeated `-p IPAddressAllow=`/`IPAddressDeny=`
    # flags ACCUMULATE (confirmed via `systemctl show`), they don't
    # overwrite each other.
    def network_policy_argv(allow_network:, egress_allowlist:, mcp_server_id:)
      if egress_allowlist.present?
        effective_ips = (resolver_stub_addresses + resolve_egress_allowlist(egress_allowlist)).uniq
        log_egress_network_policy(mcp_server_id, 'deny_except_allowlist', effective_ips)

        [
          '-p', 'RestrictAddressFamilies=AF_INET AF_INET6',
          *effective_ips.flat_map { |ip| [ '-p', "IPAddressAllow=#{ip}" ] },
          '-p', 'IPAddressDeny=any'
        ]
      elsif allow_network
        effective_ips = resolver_stub_addresses
        # IMP-bf72723ef161 review round 2 fix 4 — the generic
        # localhost/link-local/metadata deny above does NOT cover a
        # service bound to 0.0.0.0 (worker-web, Puma, a local Ollama or
        # Postgres, ...): those are ALSO reachable via THIS HOST'S OWN
        # LAN/other interface addresses specifically, which no generic
        # range names. Every address this host actually has
        # (Socket.ip_address_list, every family, nothing excluded — a
        # loopback/link-local entry here is a harmless duplicate of the
        # tokens above) is denied too. #host_own_addresses strips any
        # %zone suffix the same way #resolver_stub_addresses does (same
        # parse-failure risk — see that method's own comment).
        host_addresses = host_own_addresses
        log_egress_network_policy(mcp_server_id, 'allow_network_with_loopback_deny', effective_ips)

        [
          '-p', 'RestrictAddressFamilies=AF_INET AF_INET6',
          '-p', 'IPAddressDeny=localhost',
          '-p', 'IPAddressDeny=link-local',
          '-p', "IPAddressDeny=#{EGRESS_METADATA_ADDRESS}/32",
          *host_addresses.flat_map { |ip| [ '-p', "IPAddressDeny=#{ip}" ] },
          *effective_ips.flat_map { |ip| [ '-p', "IPAddressAllow=#{ip}" ] }
        ]
      else
        log_egress_network_policy(mcp_server_id, 'full_deny', [])

        [ '-p', 'IPAddressDeny=any', '-p', 'PrivateNetwork=yes' ]
      end
    end

    # IMP-bf72723ef161 review — logged at spawn time so an operator can
    # diagnose "this server can't reach X" without systemd itself being
    # able to say WHICH destination was blocked (IPAddressDeny/Allow are
    # unlogged eBPF packet drops by design — confirmed empirically that
    # not even IPAccounting=yes reliably surfaces per-unit traffic counts
    # for a short-lived transient unit, and even a working counter
    # wouldn't be per-destination). Server id and the resolved IPs only —
    # never the env (which may carry secrets).
    def log_egress_network_policy(mcp_server_id, mode, effective_ips)
      logger.info(
        "[McpSecurityService] stdio spawn network policy server=#{mcp_server_id.inspect} " \
        "mode=#{mode} effective_allow_ips=#{effective_ips.inspect}"
      )
    end

    # IMP-bf72723ef161 amendment 1 — deliberately NOT "localhost"
    # (127.0.0.0/8): that would expose every OTHER loopback service on
    # this host (Redis, Postgres, worker-web, Rails, the local MCP proxy)
    # to a sandboxed child whose only legitimate need is to reach the DNS
    # resolver. Read fresh from /etc/resolv.conf at spawn time (never
    # cached) — confirmed empirically that only the STUB hop
    # (127.0.0.53 on this host) needs to cross the sandbox boundary at
    # all: the stub resolver does the real upstream query itself as an
    # unsandboxed HOST process, so a real hostname resolved fine inside a
    # sandbox that allowed ONLY the stub IP, with no upstream nameserver
    # IP in the allow set at all. If resolv.conf ever points at a
    # non-loopback upstream directly, this allows THAT address instead —
    # nothing here is loopback-specific, only "whatever this host's
    # resolver actually is".
    #
    # IMP-bf72723ef161 review round 2 fix 1 — a nameserver line CAN carry
    # a link-local address with a zone suffix (e.g. "fe80::1%eth0"); a
    # bare zone strip alone isn't enough, so each candidate is also
    # re-parsed with IPAddr and dropped (with a WARN) if it doesn't parse
    # at all — a malformed resolv.conf line must never propagate into a
    # `-p IPAddressAllow=` value (see #parse_ip_for_deny_allow for why a
    # parse failure there fails the WHOLE unit, not just this one entry).
    # A link-local nameserver needs NO handling beyond the zone strip:
    # IPAddressAllow/Deny match on address BYTES only (confirmed
    # empirically — it is not a routing decision), so a scope-less
    # link-local address is an unambiguous, correct match rule here even
    # though it would be an ambiguous ROUTE on a multi-interface host.
    def resolver_stub_addresses
      File.readlines('/etc/resolv.conf').filter_map do |line|
        match = line.match(/\Anameserver\s+(\S+)/)
        match && parse_ip_for_deny_allow(match[1])
      end
    rescue Errno::ENOENT
      []
    end

    # IMP-bf72723ef161 review round 2 fix 4 — every address THIS HOST
    # itself has, across every family, nothing excluded (a loopback/
    # link-local entry here is a harmless duplicate of the generic tokens
    # #network_policy_argv already denies). Read fresh at spawn time,
    # never cached, same reasoning as #resolver_stub_addresses. Zone
    # suffixes stripped the same way (a real interface address, e.g.
    # "fe80::1%eth0", would otherwise fail the WHOLE unit to start — see
    # #parse_ip_for_deny_allow).
    def host_own_addresses
      Socket.ip_address_list.filter_map { |addr| parse_ip_for_deny_allow(addr.ip_address) }
    rescue StandardError => e
      logger.warn("[McpSecurityService] failed to enumerate host addresses for IPAddressDeny: #{e.class}: #{e.message}")
      []
    end

    # IMP-bf72723ef161 review round 2 fix 1 — confirmed empirically that
    # systemd-run's IPAddressAllow/Deny properties REJECT a zone-scoped
    # address outright ("Failed to parse IP address prefix:
    # fe80::...%eth0") — not a silently-ignored value, a hard parse error
    # that fails the ENTIRE unit, meaning every sandboxed spawn on that
    # host would fail closed the moment an unstripped zone reached here
    # (from either #resolver_stub_addresses or #host_own_addresses).
    # Stripped, never rejected outright for carrying one — re-confirmed
    # via the same probe that a zone-stripped link-local address still
    # parses and matches correctly. Anything that still doesn't parse as
    # an IPAddr after stripping is dropped (WARN), never passed through.
    def parse_ip_for_deny_allow(raw)
      candidate = raw.to_s.split('%').first
      IPAddr.new(candidate)
      candidate
    rescue IPAddr::Error
      logger.warn("[McpSecurityService] #{raw} does not parse as an IP — dropped from IPAddressAllow/Deny")
      nil
    end

    # IMP-bf72723ef161 review amendment 2 (DNS rebinding / SSRF) — resolves
    # every egress_allowlist entry to the concrete IPs #network_policy_argv
    # actually passes to IPAddressAllow, filtering out anything in
    # EGRESS_FORBIDDEN_RANGES along the way. This re-checks LITERAL
    # IP/CIDR entries too, not just resolved hostnames, even though the
    # server already validates literal entries at save time — never trust
    # a single validation layer for something this security-relevant (the
    # same reasoning IMP-abda86fb39be established for the worker-side
    # stdio validator being mandatory regardless of the server's own
    # checks). Each dropped entry/IP is logged at WARN; never raises — a
    # bad or now-forbidden entry is dropped from the effective set, not a
    # spawn failure.
    def resolve_egress_allowlist(entries)
      Array(entries).each_with_object([]) do |entry, resolved|
        entry_s = entry.to_s

        begin
          ipaddr = IPAddr.new(entry_s)
          if egress_ip_forbidden?(ipaddr)
            logger.warn("[McpSecurityService] egress_allowlist entry #{entry_s} is within a forbidden range — dropped")
          else
            resolved << entry_s
          end
        rescue IPAddr::Error
          # IMP-bf72723ef161 review round 2 fix 3 — a numeric/hex
          # pseudo-IP form (IPAddr just refused to parse it strictly
          # above) is dropped outright, NEVER attempted as a hostname
          # resolution — the server already refuses these at save time
          # (see McpServer's own validation), but the worker never trusts
          # that alone (same reasoning as EGRESS_FORBIDDEN_RANGES).
          if egress_entry_looks_like_pseudo_ip?(entry_s)
            logger.warn("[McpSecurityService] egress_allowlist entry #{entry_s} looks like a numeric/hex " \
                        'pseudo-IP form, not a real hostname — dropped, not resolved')
          else
            resolve_egress_hostname(entry_s, resolved)
          end
        end
      end.uniq
    end

    # See McpServer::EGRESS_NUMERIC_PSEUDO_IP_FORMAT's own comment for the
    # full reasoning — duplicated here, not shared, same as
    # EGRESS_FORBIDDEN_RANGES. No real DNS TLD is ever purely numeric, so
    # an all-numeric FINAL LABEL alone is already a safe, general reject;
    # EGRESS_NUMERIC_PSEUDO_IP_FORMAT additionally catches a single-label
    # all-hex/all-octal form whose final "label" isn't purely decimal
    # digits (e.g. "0x7f000001").
    def egress_entry_looks_like_pseudo_ip?(entry_s)
      return true if entry_s.split('.').last&.match?(/\A[0-9]+\z/)

      entry_s.match?(EGRESS_NUMERIC_PSEUDO_IP_FORMAT)
    end

    # Hostnames are resolved FRESH on every spawn, never cached — this
    # bounds staleness to a single run, and is the ONLY way DNS REBINDING
    # is caught at all: a hostname the server validated as safe when it
    # was SAVED can resolve to something forbidden by the time it's
    # actually used here.
    def resolve_egress_hostname(hostname, resolved)
      ips = begin
        Resolv.getaddresses(hostname)
      rescue StandardError => e
        logger.warn("[McpSecurityService] egress_allowlist hostname #{hostname} failed to resolve: #{e.class}: #{e.message}")
        []
      end

      logger.warn("[McpSecurityService] egress_allowlist hostname #{hostname} resolved to no addresses") if ips.empty?

      ips.each do |ip_s|
        ip = IPAddr.new(ip_s)
        if egress_ip_forbidden?(ip)
          logger.warn("[McpSecurityService] egress_allowlist hostname #{hostname} resolved to forbidden IP #{ip_s} — dropped")
        else
          resolved << ip_s
        end
      end
    end

    # Bidirectional #include? check: catches both a NARROW ip landing
    # inside a broad forbidden range (the common case, e.g. 169.254.169.254
    # inside 169.254.0.0/16) and a broad CIDR that would swallow a
    # forbidden range whole. Cross-family comparisons (v4 vs v6) return
    # false rather than raising — verified empirically.
    #
    # IMP-bf72723ef161 review round 2 fix 2 — normalized to its native
    # IPv4 form FIRST when the address is IPv4-mapped IPv6
    # (::ffff:127.0.0.1, ::ffff:169.254.169.254, ...): EGRESS_FORBIDDEN_RANGES
    # lists 127.0.0.0/8 and 169.254.0.0/16 as plain IPv4 CIDRs, which
    # never match an IPv6-family address directly (cross-family #include?
    # is always false — confirmed empirically) regardless of the address
    # the mapped form actually represents. Without this, an IPv4-mapped
    # form was a working bypass around every IPv4 entry in this list.
    def egress_ip_forbidden?(ipaddr)
      ipaddr = ipaddr.ipv4_mapped? ? ipaddr.native : ipaddr

      EGRESS_FORBIDDEN_RANGES.any? do |cidr|
        forbidden = IPAddr.new(cidr)
        forbidden.include?(ipaddr) || ipaddr.include?(forbidden)
      end
    end

    def sandbox_memory_max
      value = ENV['MCP_STDIO_SANDBOX_MEMORY_MAX']
      value.present? ? value : DEFAULT_SANDBOX_MEMORY_MAX
    end

    def sandbox_tasks_max
      value = Integer(ENV['MCP_STDIO_SANDBOX_TASKS_MAX'], exception: false)
      value&.positive? ? value.to_s : DEFAULT_SANDBOX_TASKS_MAX
    end

    def sandbox_cpu_quota
      value = ENV['MCP_STDIO_SANDBOX_CPU_QUOTA']
      value.present? ? value : DEFAULT_SANDBOX_CPU_QUOTA
    end

    # ENV-overridable like the other sandbox settings — MCP_STDIO_SANDBOX_ENV_DIR
    # is not meant for operators to routinely change (the production
    # default is fine on every target host), but /run/powernode is
    # root-owned 0755, so a non-root TEST process cannot create a
    # subdirectory under it at all; this is what lets specs point
    # #write_sandbox_env_file at a tmp dir they actually own, without
    # weakening the production default or needing root just to unit-test
    # argv/file-content construction.
    def sandbox_env_file_dir
      value = ENV['MCP_STDIO_SANDBOX_ENV_DIR']
      value.present? ? value : DEFAULT_SANDBOX_ENV_FILE_DIR
    end

    # Writes the sandboxed child's FULL env (server-supplied vars
    # included) to a fresh, root-owned, mode-0600 file under a mode-0700
    # private directory — never `--setenv`/`Environment=`, which a plain
    # local user can read back via `systemctl show -p Environment` even
    # for a unit started by root (verified empirically). systemd reads
    # this file itself when the unit starts; the caller (#spawn_stdio)
    # deletes it in its own OUTER `ensure` (wrapping this call, argv
    # construction AND the popen3 spawn itself), via
    # #cleanup_sandbox_env_file — see review blocker 3.
    def write_sandbox_env_file(env)
      dir = sandbox_env_file_dir
      ensure_sandbox_env_file_dir!(dir)
      path = File.join(dir, "#{SecureRandom.uuid}.env")
      body = env.map { |key, value| format_sandbox_env_file_line(key, value) }.join("\n")

      # IMP-a50680fd53d8 review blocker 3 (atomic creation) — the previous
      # File.write + File.chmod(0o600) two-step left a window where the
      # file existed at the process's DEFAULT umask-derived mode (commonly
      # 0644, world-readable BY CONTENT, not just by path) before the
      # chmod landed. O_EXCL|O_CREAT with the target mode passed to
      # sysopen means the file is created ALREADY at 0600 or not at all —
      # no readable-then-tightened window, and no risk of silently
      # following/overwriting a pre-existing file at this (UUID) path.
      fd = IO.sysopen(path, File::WRONLY | File::CREAT | File::EXCL, 0o600)
      io = IO.new(fd)
      begin
        io.write(body)
      rescue StandardError
        # IMP-a50680fd53d8 review round 2 — a write failure AFTER the
        # O_EXCL create (e.g. Errno::ENOSPC) would otherwise leave a
        # PARTIAL, 0600 file sitting on disk that #spawn_stdio's own
        # ensure never learns the path of (it re-raises past the point
        # #spawn_stdio captures env_file_path) — cleaned up here, at the
        # point of failure, then re-raised unchanged.
        io.close unless io.closed?
        begin
          File.delete(path)
        rescue Errno::ENOENT
          nil
        end
        raise
      ensure
        io.close unless io.closed?
      end
      path
    end

    # IMP-a50680fd53d8 review blocker 3 (directory check) — fail closed
    # rather than write a secrets file through a directory this process
    # doesn't actually control. `FileUtils.mkdir_p` is a no-op on an
    # ALREADY-existing path regardless of its ownership/mode/type, so
    # "we called mkdir_p" is not itself evidence the directory is safe —
    # this must be verified on every call, not just the first one that
    # happens to create it. `File.lstat` (never `File.stat`, which
    # follows symlinks) so a directory swapped for a symlink to, say,
    # another user's writable directory is caught instead of silently
    # traversed.
    def ensure_sandbox_env_file_dir!(dir)
      FileUtils.mkdir_p(dir, mode: 0o700) unless File.exist?(dir)
      stat = File.lstat(dir)

      if stat.symlink?
        raise EnvironmentViolationError, "sandbox env file directory #{dir} is a symlink, refusing to write secrets through it"
      end
      unless stat.directory?
        raise EnvironmentViolationError, "sandbox env file directory #{dir} is not a directory"
      end
      unless stat.uid == Process.euid
        raise EnvironmentViolationError,
              "sandbox env file directory #{dir} is owned by uid=#{stat.uid}, not this process's uid=#{Process.euid} — refusing to write secrets through it"
      end
      unless (stat.mode & 0o777) == 0o700
        raise EnvironmentViolationError,
              format('sandbox env file directory %s has unsafe permissions %o (expected 0700)', dir, stat.mode & 0o777)
      end
    end

    # IMP-a50680fd53d8 review blocker 2 — a systemd EnvironmentFile is a
    # tiny KEY=VALUE parser, not shell: a bare, unquoted value is split on
    # its own rules for whitespace/backslash/quote characters, and a raw
    # newline inside a value starts an entirely new KEY=VALUE line the
    # parser reads as ANOTHER environment variable, entirely bypassing
    # whatever key that value was actually written under (e.g. smuggling
    # in a fabricated `LD_PRELOAD=...` entry via a value, not a key, that
    # never mentions LD_PRELOAD at all). Every value is written
    # double-quoted with `\` and `"` escaped, matching systemd's own
    # quoting rules for EnvironmentFile (see systemd.exec(5) "Environment
    # variables ... may be quoted ... which follow the shell/quoting
    # rules for the file"), and both the key and value are rejected
    # outright — never sanitized/silently rewritten — if they can't be
    # made safe this way.
    def format_sandbox_env_file_line(key, value)
      key_s = key.to_s
      value_s = value.to_s

      unless key_s.match?(SANDBOX_ENV_FILE_KEY_PATTERN)
        raise EnvironmentViolationError, "sandbox env var name #{key_s.inspect} is not a safe systemd EnvironmentFile key"
      end
      if value_s.match?(/[\n\r\0]/)
        raise EnvironmentViolationError, "sandbox env var #{key_s} contains a newline, carriage return or NUL byte, unsafe in a systemd EnvironmentFile"
      end

      escaped = value_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')
      "#{key_s}=\"#{escaped}\""
    end

    def cleanup_sandbox_env_file(path)
      File.delete(path)
    rescue Errno::ENOENT
      nil
    end

    # Kills the WHOLE process group #spawn_stdio's child started as leader
    # of (pgroup: true) — a negative pid signals every process in that
    # group, including any grandchild the child forked, not just the
    # direct child — then reaps it (wait_thr.value blocks until the OS
    # confirms it's gone) and raises StdioTimeoutError. Reap happens via
    # wait_thr (Open3.popen3's own reaper thread), never a manual
    # Process.waitpid on the same pid — that would race wait_thr's own
    # internal wait and risk Errno::ECHILD on whichever call loses.
    def raise_stdio_timeout!(pid, wait_thr, command, timeout, unit_name: nil)
      terminate_process_group!(pid, wait_thr, unit_name: unit_name)
      raise StdioTimeoutError, "stdio MCP server '#{command}' exceeded #{timeout}s and was killed"
    end

    # TERM, a bounded grace period, then KILL if still alive on the LOCAL
    # process (the systemd-run client, when sandboxed) — SIGKILL cannot
    # be caught or ignored, so the final wait_thr.join (no timeout) is
    # guaranteed to return once the OS finishes tearing the group down.
    # Errno::ESRCH (the process already exited on its own, e.g. between
    # the deadline check and this call) is swallowed at EITHER kill —
    # there is nothing left to signal, not a failure.
    #
    # IMP-a50680fd53d8 — when `unit_name` is present, ALSO runs
    # `systemctl stop <unit_name>` first (via #stop_sandboxed_unit!, bounded
    # — see review blocker 4). Verified empirically that this is not
    # redundant with the kill below: killing the systemd-run CLIENT's
    # local process (even its whole process group) does NOT stop the
    # actual sandboxed unit — it runs under systemd's own cgroup via
    # D-Bus, decoupled from the client's process group entirely, and was
    # observed still `active (running)` after the client was SIGKILLed.
    # `systemctl stop` is a best-effort call (its own exit status is
    # ignored) run BEFORE the local kill, not instead of it: the local
    # kill still matters for reclaiming the client's own pipes/pid.
    def terminate_process_group!(pid, wait_thr, unit_name: nil)
      stop_sandboxed_unit!(unit_name) if unit_name

      Process.kill('TERM', -pid)
      return if wait_thr.join(STDIO_TERM_GRACE_SECONDS)

      Process.kill('KILL', -pid)
      wait_thr.join
    rescue Errno::ESRCH
      nil
    ensure
      wait_thr.value
    end

    # IMP-a50680fd53d8 review blocker 4 — `systemctl stop` itself can hang
    # (a wedged D-Bus call, a stuck cgroup teardown, ...); the previous
    # bare `system(...)` call had no bound at all, so a wedged stop could
    # block #terminate_process_group! — and therefore #spawn_stdio's own
    # deadline enforcement — indefinitely, defeating the very bound this
    # whole method exists to guarantee. Spawned as its own process group
    # (pgroup: true) so a hung `systemctl stop` that has itself forked
    # (e.g. a helper) is fully reclaimed on timeout, not just its direct
    # pid. Bounded to STDIO_TERM_GRACE_SECONDS, the same grace period the
    # local TERM/KILL sequence above uses. Best-effort throughout: this
    # never raises past its own rescue, and its exit status is ignored —
    # `-p TimeoutStopSec=STDIO_TERM_GRACE_SECONDS` on the unit itself (see
    # #sandboxed_spawn_argv) means systemd was already told to force-kill
    # the unit's own processes on that same bound regardless of whether
    # this client is still around to observe the result.
    def stop_sandboxed_unit!(unit_name)
      pid = Process.spawn('systemctl', 'stop', unit_name, out: File::NULL, err: File::NULL, pgroup: true)
      thr = Process.detach(pid)
      return if thr.join(STDIO_TERM_GRACE_SECONDS)

      Process.kill('KILL', -pid)
      thr.join
    rescue Errno::ESRCH
      nil
    rescue StandardError => e
      # IMP-a50680fd53d8 review round 2 — Process.spawn('systemctl', ...)
      # itself can raise (Errno::ENOENT if systemctl isn't on PATH,
      # Errno::EAGAIN under fork pressure, ...), not just the ESRCH this
      # method already tolerates. A narrower rescue here left the caller's
      # local TERM/KILL sequence (#terminate_process_group!) never running
      # at all — this call is best-effort exactly like the ESRCH case
      # above; only the class and message are logged, never full
      # backtraces that could carry command-line detail.
      logger.warn("[McpSecurityService] stop_sandboxed_unit! failed for #{unit_name}: #{e.class}: #{e.message}")
      nil
    end

    # IMP-e2cba83ee39f: the ONLY env the spawned stdio MCP server process
    # ever sees (paired with #spawn_stdio's unsetenv_others: true) — a
    # small, fixed passthrough from the WORKER's own environment
    # (STDIO_ENV_PASSTHROUGH_KEYS: PATH, HOME, LANG, LC_ALL, TZ, TMPDIR —
    # whichever are actually set), with the validated/sanitized SERVER env
    # merged on top. PATH and HOME are FORBIDDEN in the server env (see
    # FORBIDDEN_ENV_VARS) specifically so a malicious server config can
    # never override them: a server-supplied PATH could point a bare
    # command name like "node" at an attacker-controlled binary resolved
    # through it — the worker's own PATH/HOME always win. Every other
    # passthrough key CAN be overridden by an explicit, validated server
    # env value (e.g. a server-supplied LANG/TZ), same as "merge on top"
    # for everything else.
    def build_stdio_env(env, strict_env: false)
      sanitized = sanitize_environment(env, strict: strict_env).transform_keys(&:to_s)

      base_passthrough = STDIO_ENV_PASSTHROUGH_KEYS.each_with_object({}) do |key, memo|
        value = ENV[key]
        memo[key] = value if value
      end

      base_passthrough.merge(sanitized)
    end

    # Shellwords-split a command string into argv tokens. An unparseable
    # string (unbalanced quoting/escaping, e.g. "node -e 'x") is refused
    # outright rather than silently falling back to some other split — a
    # command whose shape can't even be determined has no business being
    # spawned (IMP-97b6b1185748 item 7).
    def tokenize_command(command)
      return [] if command.blank?

      Shellwords.split(command.to_s)
    rescue ArgumentError
      raise CommandNotAllowedError, "Command is unparseable (unbalanced quoting or escaping): #{command.to_s.inspect}"
    end

    def extract_base_command(command)
      tokenize_command(command).first.to_s
    end

    def env_wrapper?(base_command)
      File.basename(base_command.to_s) == 'env'
    end

    # IMP-97b6b1185748 item 2 (DECISION): `env` / `/usr/bin/env` is refused
    # as the command entirely — not unwrapped to find a "real" interpreter
    # inside it. The worker already sanitizes server['env'] before spawning
    # (see #sanitize_environment), so the wrapper adds nothing legitimate;
    # it only ever existed as a way to set ad hoc variables via argv
    # (`env FOO=1 node ...`) or, as this task found, to smuggle an
    # unvalidated interpreter+flags past the whitelist.
    def raise_if_env_wrapper!(base_command)
      return unless env_wrapper?(base_command)

      raise CommandNotAllowedError,
            "The 'env' wrapper is not allowed for stdio MCP servers — use the interpreter directly " \
            '(e.g. "node", not "env node") and set environment variables via the server\'s own env, ' \
            "not via env's argv."
    end

    def allowed_commands(allow_extended)
      allow_extended ? (ALLOWED_COMMANDS + EXTENDED_COMMANDS) : ALLOWED_COMMANDS
    end

    # Validate an EXACT, already-resolved single command token — no
    # tokenizing here (see #validate_stdio_server!'s comment for why a
    # second tokenize pass is unsafe). #validate_command! is the public,
    # raw-command-STRING-accepting entry point that tokenizes once and
    # delegates here.
    def validate_exact_base_command!(base_command, allow_extended: false)
      return if base_command.blank?

      raise_if_env_wrapper!(base_command)

      allowed = allowed_commands(allow_extended)

      return if base_command_in_allowed_list?(base_command, allowed)

      raise CommandNotAllowedError,
            "Command '#{base_command}' is not in the allowed list. " \
            "Allowed commands: #{allowed.join(', ')}"
    end

    # IMP-b6be9d979e13: exact-match only — see ALLOWED_ABSOLUTE_COMMAND_DIRS'
    # comment for the full rationale. No File.basename/end_with? matching:
    # those accepted ANY directory a command happened to sit in
    # ("/tmp/evil/node" read as "node"). Decision: plain string equality,
    # not File.expand_path — expand_path would resolve "/usr/bin/../../tmp/
    # node" down to "/tmp/node" and reject it that way too, but silently
    # normalizing a path before checking it is unnecessary complexity here
    # (this never touches the filesystem either way) and invites a future
    # normalization mismatch with whatever exec/Open3 actually resolves at
    # spawn time. Rejecting any ".." segment explicitly, before the exact
    # match, is simplest and makes the refusal reason unambiguous — a
    # traversal segment is refused on sight, not because the resulting
    # string merely fails to match (belt-and-suspenders: it would fail the
    # exact match anyway, since expand_path is never applied). Whitespace is
    # rejected the same way, for the same reason ("/usr/bin/node " differs
    # from "/usr/bin/node" as a string already, but reject it explicitly so
    # the refusal reason is legible, not an incidental match failure).
    def base_command_in_allowed_list?(base_command, allowed)
      return false if base_command.match?(/\s/)
      return false if base_command.split('/').include?('..')

      return allowed.include?(base_command) unless base_command.start_with?('/')

      ALLOWED_ABSOLUTE_COMMAND_DIRS.any? do |dir|
        allowed.any? { |name| base_command == "#{dir}/#{name}" }
      end
    end

    def validate_command_arguments!(command)
      dangerous_patterns = [
        /[;&|`$]/,
        /\$\(/,
        /\$\{/,
        %r{>\s*/},
        %r{<\s*/},
        /\|\s*\w+/,
        /\beval\b/,
        /\bexec\b/,
        /\bsource\b/,
        %r{\.\s*/}
      ]

      args_portion = command.to_s.split(/\s+/, 2)[1].to_s

      dangerous_patterns.each do |pattern|
        if args_portion.match?(pattern)
          raise CommandNotAllowedError,
                "Potentially dangerous pattern detected in command arguments: #{pattern.source}"
        end
      end
    end

    def raise_on_shell_metacharacters!(args)
      args.each do |arg|
        next unless arg.include?("\0") || arg.match?(SHELL_METACHARACTER_PATTERN)

        raise CommandNotAllowedError,
              "Argument contains a forbidden shell metacharacter or NUL byte: #{arg.inspect}. " \
              'If this value is a URL or secret that legitimately contains one of these characters, ' \
              'pass it via the environment instead of a command-line argument.'
      end
    end

    # IMP-97b6b1185748 item 8: refuses a bare "-" or a stdin device path
    # (/dev/stdin, /proc/self/fd/0, /dev/fd/0, and their "." / ".." / "//"
    # spellings — see #stdin_device_path?) appearing ANYWHERE in args —
    # whether as the script positional itself ("node /dev/stdin") or as
    # the separate-token value of a flag like -r/--import ("node -r
    # /proc/self/fd/0"). The attached-value form ("--import=/dev/stdin")
    # isn't a standalone array element, so it's caught separately by
    # #stdio_arg_looks_like_path? excluding these same device paths.
    def raise_on_stdin_source_arg!(interpreter, args)
      return unless STDIN_DASH_INTERPRETERS.include?(interpreter)

      hit = args.find { |a| a == '-' || stdin_device_path?(a) }
      return unless hit

      raise CommandNotAllowedError,
            "Reading the program from stdin (#{hit.inspect}) is not allowed for stdio MCP servers " \
            '(stdin already carries the MCP JSON-RPC protocol messages)'
    end

    # IMP-97b6b1185748 item 3 (round 4): lexically normalize `value` (never
    # touching the filesystem — File.expand_path, not File.realpath) and
    # check the result against STDIN_DEVICE_PATH_PATTERN. A blank/nil value
    # is never a device path; expand_path itself can raise on a handful of
    # pathological inputs (e.g. embedded NUL — though that's already
    # refused earlier by #raise_on_shell_metacharacters!), so this fails
    # closed to "not a device path" rather than propagating a surprise
    # error out of what's meant to be a boolean predicate.
    def stdin_device_path?(value)
      return false if value.blank?

      File.expand_path(value).match?(STDIN_DEVICE_PATH_PATTERN)
    rescue ArgumentError
      false
    end

    def interpreter_key_for(command)
      name = File.basename(command.to_s)
      return name if INLINE_CODE_RULES_BY_INTERPRETER.key?(name)
      return 'deno' if name == 'deno'

      nil
    end

    # IMP-97b6b1185748 item 4: deno's subcommand — not a flag — decides
    # whether inline code runs (`deno eval`, `deno repl`) or a package is
    # installed/compiled/tested rather than simply launched (`deno task`,
    # `deno install`, `deno compile`, ...). Only `run` and `serve` are the
    # ordinary "launch an MCP server" pattern. #deno_subcommand! raises
    # directly (fail-closed) for any token it can't classify — see its
    # comment. No subcommand at all defaults to deno's REPL, refused too.
    def raise_on_deno_subcommand!(args)
      subcommand = deno_subcommand!(args)

      return if DENO_ALLOWED_SUBCOMMANDS.include?(subcommand)

      label = subcommand.nil? ? '(none — deno defaults to its REPL)' : "'#{subcommand}'"
      raise CommandNotAllowedError,
            "Deno subcommand #{label} is not allowed for stdio MCP servers (only 'run' and 'serve' are)"
    end

    # IMP-97b6b1185748 round 8 BLOCKER: deno had the SAME "assume an
    # unrecognized flag is boolean" bug class round 5 fixed for
    # node/bun/ruby/python, just never audited — `deno --v8-flags run
    # eval x` would have skipped "--v8-flags" as if boolean and landed on
    # "eval" as if it were the subcommand check's positional, except the
    # subcommand check ran and refused "eval" anyway, so the practical
    # exposure was more theoretical than proven; still the same shape of
    # mistake. UNLIKE node/bun/ruby/python's fix, this does NOT fall back
    # to "scan everything" on ambiguity — deno has no inline-code FLAG to
    # scan for (its risk is entirely in the SUBCOMMAND, which this method
    # exists to find), so there is nothing a fallback scan could check.
    # The only fail-closed choice is to refuse outright.
    #
    # Only these may be skipped before the subcommand is found:
    #   -q / --quiet            — boolean, no value.
    #   -L / --log-level        — takes a value, separate ("-L debug",
    #     "--log-level debug") or attached ("--log-level=debug").
    #   --unstable*             — boolean (--unstable, --unstable-kv, ...).
    #   any attached "--flag=value" — self-contained regardless of
    #     whether "flag" is one of the above (no separate-arg ambiguity
    #     possible), same reasoning as node/bun/ruby/python's long-flag
    #     handling.
    # Any OTHER dash-prefixed token, long or short, before the
    # subcommand — REFUSED, not skipped.
    def deno_subcommand!(args)
      i = 0
      while i < args.length
        arg = args[i]
        return arg unless arg.start_with?('-')

        consumed = deno_global_flag_tokens(arg)
        if consumed.nil?
          raise CommandNotAllowedError,
                "An unrecognized flag (#{arg.inspect}) appears before deno's subcommand, so it cannot be " \
                "confirmed as 'run' or 'serve', and is not allowed for stdio MCP servers"
        end

        i += consumed
      end
      nil
    end

    def deno_global_flag_tokens(arg)
      return 1 if DENO_BOOLEAN_GLOBAL_FLAGS.include?(arg)
      return 1 if arg.start_with?(DENO_UNSTABLE_PREFIX)
      return 2 if arg == '-L'

      if arg.start_with?('--')
        name, sep, = arg[2..].partition('=')
        return 1 if sep.present?
        return 2 if name == 'log-level'
      end

      nil
    end

    # IMP-97b6b1185748 item 1 (round 4, tightened round 5): walk `args` left
    # to right, checking each dash-prefixed token against `rules` (raising
    # exactly as before for a blocked/non-path/non-MCP-module flag), until
    # either: (a) a value-consuming flag matched
    # `stdio_arg_looks_like_mcp_module?` (python's -m into an MCP module —
    # Python's OWN option parsing ends right there), (b) an explicit "--"
    # is reached (POSIX end-of-options — everything after unconditionally
    # belongs to the program, for every interpreter here), or (c) a token
    # that doesn't start with "-" is reached — the interpreter's own
    # positional (script file). For every OTHER interpreter with rules
    # (currently just npx — see STOP_AT_FIRST_POSITIONAL_INTERPRETERS),
    # positionals are simply skipped over rather than stopping the scan,
    # preserving the original "scan everything" behavior.
    #
    # FAIL-CLOSED RULE (round 5, real-spawn-proven regression): early stop
    # is trustworthy ONLY as long as every token seen so far was FULLY
    # UNDERSTOOD — a known boolean flag, a known value-taking flag whose
    # value was actually consumed, an attached "--flag=value" (self
    # contained regardless of whether "flag" is recognized), or a short
    # cluster (already deterministic character by character). The bug this
    # closes: an unrecognized bare long flag WITHOUT "=" (e.g. "--title",
    # "--conditions", "--dns-result-order") was silently assumed to be
    # boolean, so its SEPARATE next-arg value ("foo" in "--title foo") was
    # wrongly treated as the first positional — stopping the scan one
    # token early and hiding a real "-e"/"-c" right after it. The instant
    # such a flag appears (see #raise_on_long_flag!'s :ambiguous return),
    # this scan gives up on early-stop ENTIRELY for the rest of `args` and
    # falls back to checking every remaining token independently, exactly
    # like round 3 did before item 1 existed — ambiguous always means
    # "scan everything", never the other way round.
    #
    # @return [Array(Integer, Boolean)] the index in `args` of the first
    #   positional (or `args.length` if none was found — including the
    #   "python -m <mcp module>"/"--" early-stop cases, and the npx "scan
    #   everything" case, where the index is unused), and whether the scan
    #   ever went ambiguous (an unrecognized bare long flag was seen before
    #   any positional was confidently identified — callers with their own
    #   extra positional-dependent logic, e.g. bun's script-name check,
    #   MUST refuse rather than trust that index when this is true).
    def scan_interpreter_flags!(args, rules, interpreter)
      stop_at_positional = STOP_AT_FIRST_POSITIONAL_INTERPRETERS.include?(interpreter)
      ambiguous = false

      i = 0
      while i < args.length
        arg = args[i]

        unless arg.start_with?('-')
          break if stop_at_positional && !ambiguous

          i += 1
          next
        end

        consumed = raise_if_inline_code_flag!(arg, args[i + 1], rules)

        case consumed
        when :stop, :end_of_options
          break
        when :ambiguous
          ambiguous = true
          i += 1
        else
          i += ambiguous ? 1 : consumed
        end
      end

      [i, ambiguous]
    end

    # IMP-97b6b1185748 item 2 (round 4, tightened round 5): `bun run <x>`
    # and bare `bun <x>` look up `x` in package.json's "scripts" and run
    # whatever shell command is defined there when `x` isn't itself a real
    # file — the same arbitrary-code-by-name-lookup shape as the env-var
    # injection vectors this service refuses elsewhere, just routed
    # through package.json instead of an env var. `bun x <pkg>` (bun's own
    # package RUNNER, unrelated to "bun run") stays the launcher-by-design
    # exemption (see the class-level SCOPE note) — same as `npx <pkg>`.
    #
    # `ambiguous` (round 5): if #scan_interpreter_flags! couldn't reliably
    # find bun's real positional (an unrecognized flag like "--cwd"
    # appeared first), REFUSE outright rather than trust whatever token it
    # landed on — "bun --cwd x run build" must not be read as "the
    # positional is 'x'" (bun's launcher-exempt package-runner subcommand)
    # when "x" is actually --cwd's directory argument.
    def raise_on_bun_shell_script!(args, positional_index, ambiguous)
      if ambiguous
        raise CommandNotAllowedError,
              'An unrecognized flag appears before the bun run target, so it cannot be confirmed as a real ' \
              'file path or the "x" package-runner subcommand, and is not allowed for stdio MCP servers'
      end

      return if positional_index >= args.length

      first = args[positional_index]
      return if first == 'x'

      if first == 'run'
        target = args[positional_index + 1]
        return if target && stdio_arg_looks_like_path?(target)

        raise CommandNotAllowedError,
              "'bun run #{target.inspect}' runs a package.json script through the shell and is not allowed " \
              'for stdio MCP servers (pass a direct file path instead, e.g. "bun run ./server.js")'
      end

      return if stdio_arg_looks_like_path?(first)

      raise CommandNotAllowedError,
            "'bun #{first.inspect}' runs a package.json script through the shell and is not allowed for " \
            'stdio MCP servers (pass a direct file path instead, e.g. "bun ./server.js")'
    end

    # @return [Integer, :stop, :ambiguous, :end_of_options] tokens consumed
    #   from `args` starting at this flag (1, or 2 when the flag's value
    #   came from the SEPARATE next arg rather than being attached to this
    #   token); or :stop for a successful python -m/MCP-module match; or
    #   :end_of_options for a bare "--"; or :ambiguous for an unrecognized
    #   bare long flag whose value-taking-ness can't be determined — see
    #   #scan_interpreter_flags! and #raise_on_long_flag! for the full
    #   contract each of these drives.
    def raise_if_inline_code_flag!(arg, next_arg, rules)
      return raise_on_long_flag!(arg, next_arg, rules) if arg.start_with?('--')
      return 1 unless arg.start_with?('-')

      scan_short_flag_cluster!(arg, next_arg, rules)
    end

    # IMP-97b6b1185748 item 3: scan a short-flag token's letters left to
    # right. A blocked letter anywhere is a hit. A letter that consumes a
    # value (blocked-with-a-value, path-exempt, mcp-module-exempt, or
    # value_only) means every character after it in this token IS that
    # flag's attached value — scanning stops there rather than misreading
    # the value as more flags (e.g. python's "-Wc": W takes a value, so
    # the "c" is -W's value "c", not a separate -c; ruby's
    # "-W:no-deprecated": W takes a value, so the "e" buried in
    # "deprecated" is never reached).
    # Index-based (not each_char) because ruby_warning_short/
    # ruby_encoding_short (round 7) need to consume a variable, sometimes
    # zero-width, number of characters WITHIN the token and then resume
    # scanning — each_char's implicit one-char-per-iteration stride can't
    # express "skip exactly one more character, then keep going".
    def scan_short_flag_cluster!(arg, next_arg, rules)
      body = arg[1..]
      return 1 if body.blank?

      i = 0
      while i < body.length
        char = body[i]
        attached_value = body.length > i + 1 ? body[(i + 1)..] : nil

        if rules[:blocked_short].include?(char)
          raise CommandNotAllowedError,
                "Inline-code flag '-#{char}' is not allowed for stdio MCP servers"
        end

        if rules[:path_exempt_short]&.include?(char)
          raise_unless_path_like!("-#{char}", attached_value || next_arg)
          return attached_value.blank? ? 2 : 1
        end

        if rules[:mcp_module_short]&.include?(char)
          raise_unless_mcp_module!("-#{char}", attached_value || next_arg)
          return :stop
        end

        return attached_value.blank? ? 2 : 1 if rules[:value_only_short].include?(char)

        # optional_value_short (round 6): NEVER a separate next-arg,
        # whether or not a value is attached — always exactly 1 token.
        return 1 if rules[:optional_value_short]&.include?(char)

        if rules[:ruby_warning_short]&.include?(char)
          i = ruby_warning_flag_next_index(body, i)
          next
        end

        if rules[:ruby_encoding_short]&.include?(char)
          # Consumes exactly the ONE following character (whatever it
          # is), if one exists — round 7, CONFIRMED BY EXECUTION on this
          # host (`ruby -K0e ...`, `ruby -Kab ...`: the character right
          # after K is always eaten as its 1-char encoding regardless of
          # what it is, then scanning resumes from the character after
          # THAT). Never a separate next-arg either way.
          i += body.length > i + 1 ? 2 : 1
          next
        end

        i += 1
      end

      1
    end

    # IMP-97b6b1185748 round 7 BLOCKER — real-spawn-proven regression:
    # `ruby -We 'code'`, `ruby -W2e 'code'` both ran the code. Ruby's -W
    # (CONFIRMED BY EXECUTION on this host, `ruby -W<X>e ...` for every
    # X) does NOT simply take-or-not-take a value the way optional_value_short
    # assumed — within a single token it can consume PART of the
    # remaining text and then resume interpreting the REST as further
    # flags:
    #   -W: followed by ":" — the rest of the token is a warning
    #     CATEGORY value ("-W:no-deprecated") — stops the cluster scan
    #     entirely, same as an ordinary attached value.
    #   -W: followed by a digit 0, 1 or 2 — that ONE digit is the warning
    #     LEVEL and is consumed; scanning resumes at the character right
    #     after it (so "-W2e" reaches "e" and correctly raises — real
    #     ruby does execute that code, confirmed by spawn).
    #   -W: followed by anything else, or nothing at all — W itself took
    #     no value; scanning resumes from that very next character (or,
    #     if there is none, the token is simply finished).
    # A bare "-W" at the end of a token NEVER reaches into a separate
    # next-arg in any of these branches.
    def ruby_warning_flag_next_index(body, i)
      nxt = body[i + 1]

      return body.length if nxt == ':' # stop the cluster scan (rest of token is the value)
      return i + 2 if %w[0 1 2].include?(nxt) # consume exactly one digit, then resume

      i + 1 # W took nothing; resume from the very next character
    end

    # @return [Integer, :ambiguous, :end_of_options] see
    #   #scan_interpreter_flags! for the full contract. A bare "--" is an
    #   unconditional, unambiguous end-of-options marker (POSIX
    #   convention, honored by node/bun/ruby/python alike) — everything
    #   after belongs to the program, full stop. An attached "--flag=value"
    #   is self-contained (1 token) regardless of whether "flag" is
    #   recognized: there's no separate-arg value to misidentify. A bare
    #   "--flag" (no "=") that isn't blocked/path-exempt/in the small
    #   per-interpreter `boolean_long` list is :ambiguous — we genuinely
    #   don't know whether it takes a separate value, so we refuse to
    #   guess (round 5; see #scan_interpreter_flags!'s comment).
    def raise_on_long_flag!(arg, next_arg, rules)
      name, sep, attached_value = arg[2..].partition('=')

      return :end_of_options if name.empty? && sep.empty?

      if rules[:blocked_long].include?(name) || blocked_long_prefix_match?(name, rules[:blocked_long_prefixes])
        raise CommandNotAllowedError,
              "Inline-code flag '--#{name}' is not allowed for stdio MCP servers"
      end

      if rules[:path_exempt_long].include?(name)
        raise_unless_path_like!("--#{name}", attached_value.presence || next_arg)
        return attached_value.blank? ? 2 : 1
      end

      return 1 if sep.present? || rules[:boolean_long]&.include?(name)

      :ambiguous
    end

    def blocked_long_prefix_match?(name, prefixes)
      return false if prefixes.blank?

      prefixes.any? { |prefix| name == prefix || name.start_with?("#{prefix}-") }
    end

    def raise_unless_path_like!(flag_label, value)
      return if stdio_arg_looks_like_path?(value)

      raise CommandNotAllowedError,
            "Argument '#{flag_label}' loads an arbitrary (non-path) module and is not allowed for stdio MCP servers"
    end

    def raise_unless_mcp_module!(flag_label, value)
      return if stdio_arg_looks_like_mcp_module?(value)

      raise CommandNotAllowedError,
            "Argument '#{flag_label}' does not name an MCP server module and is not allowed for stdio MCP servers"
    end

    # IMP-97b6b1185748 item 6: a value is a path ONLY if it starts with
    # "/", "./" or "../" — dropped the earlier extension-based heuristic
    # (it let a bare, non-path module name like "highlight.js" or
    # "foo.rb" through just because it happened to end in a known
    # extension). IMP-97b6b1185748 item 8: a stdin device path is never
    # path-like here even though it starts with "/" — reading "the file"
    # from /dev/stdin or /proc/self/fd/0 is the same "program from stdin"
    # problem as a bare "-" (see #raise_on_stdin_source_arg!), just spelled
    # as a file.
    def stdio_arg_looks_like_path?(value)
      return false if value.nil?
      return false if stdin_device_path?(value)

      value.start_with?('/', './', '../')
    end

    # IMP-97b6b1185748 item 2 (DECISION): python's -m runs an arbitrary
    # installed module, but `-m <mcp-server-package>` is also the ordinary
    # way many MCP servers are launched. Split the difference: allow it
    # only when the value looks like a plain dotted module identifier
    # (MCP_MODULE_NAME_PATTERN — no flags, no paths, no shell syntax) AND
    # the full name mentions "mcp" (case-insensitive) somewhere, e.g.
    # "mcp_server_git" or "awslabs.foo_mcp_server". Anything else — code,
    # pdb, pip, http.server, runpy, antigravity, ... — is refused.
    def stdio_arg_looks_like_mcp_module?(value)
      return false if value.nil?
      return false unless value.match?(MCP_MODULE_NAME_PATTERN)

      value.downcase.include?('mcp')
    end

    # IMP-2c760325c102 — the SPAWN-time face of package-launcher pinning,
    # called by #validate_stdio_server! AFTER the inline-code rules (so an
    # `npx -c` is still refused as inline code, and a launcher is only ever
    # examined once the command itself is allowed).
    def raise_on_unpinned_package!(base_command, args)
      violation = package_pin_violation_for_argv(base_command, args)
      raise CommandNotAllowedError, violation if violation
    end

    # Dispatches an already-resolved base command + argv to its launcher's
    # grammar. nil for anything that is not a package launcher.
    def package_pin_violation_for_argv(base_command, args)
      launcher = package_launcher_for(base_command)
      return nil unless launcher

      args = Array(args).map(&:to_s)
      case launcher
      when 'npx' then package_launcher_pin_violation('npx', args, PACKAGE_LAUNCHER_RULES['npx'])
      when 'uvx' then package_launcher_pin_violation('uvx', args, PACKAGE_LAUNCHER_RULES['uvx'])
      when 'uv' then uv_pin_violation(args)
      when 'pipx' then pipx_pin_violation(args)
      when 'bun' then bun_x_pin_violation(args)
      when 'deno' then deno_specifier_pin_violation(args)
      end
    end

    # Basename only: the command has already passed the exact-path
    # whitelist (#base_command_in_allowed_list?) on the spawn path, and on
    # the save path the model only needs to know WHICH grammar applies.
    def package_launcher_for(base_command)
      name = File.basename(base_command.to_s)
      PACKAGE_LAUNCHER_COMMANDS.include?(name) ? name : nil
    end

    # The shared option scan (see PACKAGE_LAUNCHER_RULES for the shape).
    # Walks argv up to the first positional (or a bare "--", whose next
    # token is the positional), classifying every option against the
    # launcher's allowlists and refusing anything unlisted; then holds
    # every collected package spec, and the positional when it is a
    # package, to the launcher's pinned-spec pattern.
    def package_launcher_pin_violation(launcher, args, rules)
      packages = []
      positional = nil
      i = 0
      while i < args.length
        arg = args[i]
        if arg == '--'
          positional = args[i + 1]
          break
        end
        unless arg.start_with?('-')
          positional = arg
          break
        end

        name, attached = arg.split('=', 2)
        # "-p=x" is not a form any of these launchers parse as p + x;
        # refuse it rather than guess. Only long options attach with "=".
        return unknown_launcher_option_message(launcher, arg, rules) if attached && !name.start_with?('--')

        if rules[:package_flags].include?(name) || rules[:selector_flags].include?(name)
          value = attached || args[i + 1]
          return "#{launcher} option #{name} needs a package spec" if value.nil? || value.start_with?('-')

          value.split(',').each { |spec| packages << [ name, spec ] }
          i += attached ? 1 : 2
        elsif rules[:value_flags].include?(name)
          return "#{launcher} option #{name} needs a value" if attached.nil? && args[i + 1].nil?

          i += attached ? 1 : 2
        elsif rules[:boolean_flags].include?(name) && attached.nil?
          i += 1
        else
          return unknown_launcher_option_message(launcher, arg, rules)
        end
      end

      packages.each do |flag, spec|
        next if pinned_package_spec?(spec, rules[:pinned])

        return unpinned_package_message(launcher, spec, rules[:pinned], via: flag)
      end

      return nil if rules[:positional] != :package
      return nil if packages.any? { |flag, _spec| rules[:selector_flags].include?(flag) }
      return "#{launcher}: no package was given to run" if positional.nil?
      return nil if pinned_package_spec?(positional, rules[:pinned])

      unpinned_package_message(launcher, positional, rules[:pinned], via: nil)
    end

    def unknown_launcher_option_message(launcher, arg, rules)
      recognized = (rules[:boolean_flags] + rules[:value_flags] + rules[:package_flags] + rules[:selector_flags]).join(' ')
      "#{launcher} option #{arg.inspect} is not allowed before the #{rules[:positional]} for stdio MCP servers " \
        '(an unrecognized option could change which package or registry is used); options recognized there: ' \
        "#{recognized}. Options for the package itself go after it."
    end

    # `uvx` IS `uv tool run`; `uv run` launches a local script/command but
    # its --with pulls registry packages. Every other uv subcommand is not
    # a launcher (and `uv pip install ...` as a server command just exits).
    def uv_pin_violation(args)
      if args[0] == 'tool' && args[1] == 'run'
        package_launcher_pin_violation('uv tool run', args.drop(2), PACKAGE_LAUNCHER_RULES['uvx'])
      elsif args[0] == 'run'
        package_launcher_pin_violation('uv run', args.drop(1), PACKAGE_LAUNCHER_RULES['uv run'])
      end
    end

    def pipx_pin_violation(args)
      return nil unless args[0] == 'run'

      package_launcher_pin_violation('pipx run', args.drop(1), PACKAGE_LAUNCHER_RULES['pipx run'])
    end

    # `bun x <pkg>` is bun's package runner. Its position is found with the
    # same scan #raise_on_bun_shell_script! trusts; an ambiguous scan (an
    # unrecognized bun flag before the subcommand) is refused here too, so
    # the save-time gate cannot be more lenient than the spawn-time one.
    def bun_x_pin_violation(args)
      positional_index, ambiguous = scan_interpreter_flags!(args, INLINE_CODE_RULES_BY_INTERPRETER['bun'], 'bun')
      if ambiguous
        return 'bun: an unrecognized flag appears before the subcommand, so whether this is a "bun x" package launch ' \
               'cannot be determined, and it is not allowed for stdio MCP servers'
      end
      return nil unless args[positional_index] == 'x'

      package_launcher_pin_violation('bun x', args.drop(positional_index + 1), PACKAGE_LAUNCHER_RULES['bun x'])
    end

    # deno resolves `npm:`/`jsr:` specifiers from the registries at run
    # time wherever they appear (the script positional, an --import, ...),
    # so EVERY argv token in one of those schemes must be pinned — no
    # positional modelling needed, and none attempted. Plain URL scripts
    # (https://deno.land/x/...) are out of this rule's scope.
    def deno_specifier_pin_violation(args)
      args.each do |arg|
        if arg.start_with?('npm:')
          next if arg.match?(DENO_NPM_PINNED_SPECIFIER_PATTERN)

          return unpinned_package_message('deno', arg, :npm, via: nil)
        elsif arg.start_with?('jsr:')
          next if arg.match?(DENO_JSR_PINNED_SPECIFIER_PATTERN)

          return unpinned_package_message('deno', arg, :jsr, via: nil)
        end
      end
      nil
    end

    def pinned_package_spec?(spec, kind)
      case kind
      when :npm then spec.match?(NPM_PINNED_PACKAGE_PATTERN)
      when :pypi then spec.match?(PYPI_PINNED_PACKAGE_PATTERN)
      when :jsr then spec.match?(JSR_PINNED_PACKAGE_PATTERN)
      else false
      end
    end

    # The actionable refusal: names the launcher, the offending spec (and
    # the option it came through), the exact shape to write it in with the
    # caller's own package name filled in, and what is refused and why.
    def unpinned_package_message(launcher, spec, kind, via:)
      source = via ? " (via #{via})" : ''
      case kind
      when :pypi
        bare = spec.sub(/[\[=@<>~!].*\z/, '')
        shape = "#{bare}==<version> or #{bare}@<version> (e.g. #{bare}==2026.8.18)"
        refused = 'ranges (>=, ~=, !=, ==1.*), arbitrary equality (===), git/URL/path specs and requirements files'
      when :jsr
        bare = spec.sub(/(?<=.)@[^@\/]*\z/, '')
        shape = "#{bare}@<major>.<minor>.<patch> (e.g. #{bare}@1.2.3)"
        refused = 'dist-tags and ranges'
      else
        bare = spec.sub(/(?<=.)@[^@\/]*\z/, '')
        shape = "#{bare}@<major>.<minor>.<patch> (e.g. #{bare}@1.2.3)"
        refused = 'dist-tags (latest, next), ranges (^, ~, >=, *, x), git/URL/tarball/path specs and npm: aliases'
      end

      "#{launcher}: package #{spec.inspect}#{source} is not pinned to an exact version. " \
        "Write it as #{shape}; #{refused} are refused."
    end
  end
end
