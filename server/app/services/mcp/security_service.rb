# frozen_string_literal: true

require "shellwords"

# Service for MCP security hardening (server-side).
#
# PORTED FROM THE WORKER (IMP-176a386fef98): worker/app/services/mcp_security_service.rb
# (top-level McpSecurityService) grew, over many review rounds, a much more
# thorough stdio command/argv/env validator than this file ever had, while
# Mcp::PromptService#send_stdio_request and Mcp::ResourceService
# #send_stdio_request Open3'd the server's command/args/env with NO
# validation at all, and Mcp::SyncExecutionService#execute_stdio validated
# only the bare command string (never args) and spawned a command STRING
# rather than the [cmd, cmd] argv-only exec form, inheriting the full Rails
# process environment. This file is now a deliberate PORT of the worker's
# rules at worker HEAD 2965b98c5 (dev-loop/dev-improve) — same constants,
# same validation logic, same error messages/verdicts, so a server-refused
# stdio config is exactly as hardened as a worker-refused one.
#
# IMP-abda86fb39be (MCP isolation Phase 0 T1) — this file NO LONGER SPAWNS
# anything. #spawn_stdio (and its process-group-kill machinery) moved to
# the worker's McpSecurityService exclusively: the server now only
# VALIDATES (#validate_stdio_server!, for early, no-network-hop refusal of
# an obviously bad config) and hands the validated request to
# Mcp::WorkerStdioClient, which POSTs it to the worker for actual
# execution via the worker's own hardened spawn_stdio. Every one of the 3
# server-side stdio call sites (Mcp::SyncExecutionService#execute_stdio,
# Mcp::PromptService/Mcp::ResourceService#send_stdio_request) now follows:
# validate here (unchanged) -> Mcp::WorkerStdioClient.execute -> map the
# worker's {result:}/{error:{message:}} response into this call site's
# existing return shape (see each file's own comment for that mapping).
# The worker independently re-validates via its OWN validate_stdio_server!
# before it ever spawns anything — this file's validation is a fast local
# refusal, never the only gate.
#
# STDIO_TERM_GRACE_SECONDS/MAX_STDIO_TIMEOUT_SECONDS are KEPT here (even
# though nothing spawns server-side anymore) because Mcp::WorkerStdioClient
# needs the SAME numbers: the grace to size its own HTTP read_timeout so
# the server never gives up on the worker before the worker's own
# deadline+grace would have, and the ceiling to clamp the configured
# deadline to before the worker would refuse it — see that file's comment.
#
# KEPT IN SYNC BY A PARITY SPEC: spec/services/mcp/security_service_parity_spec.rb
# `require`s the worker class by relative path (spec-only — the two apps
# deploy separately; this file does NOT runtime-require anything from
# worker/) and asserts identical constants, identical verdicts (allow/
# refuse, plus returned argv/env) over one shared adversarial fixture
# table, AND identical normalized source for every method/constant this
# file still shares with the worker (validate_stdio_server! and its
# private helpers, plus the two timeout constants above). It does NOT
# compare #spawn_stdio or its own private helpers
# (raise_stdio_timeout!/terminate_process_group!) or StdioTimeoutError —
# those exist ONLY on the worker now; there is nothing here to diverge
# from them any more.
module Mcp
  class SecurityService
  # IMP-2c760325c102 round 1 — a refusal carries WHERE it hit (`rule`, a
  # short stable name; `arg_index`, the offending token's position in the
  # resolved argv) so the audit log can record that instead of argv or the
  # message, both of which may carry tokens. Pre-existing raise sites leave
  # both nil; only the error class is recorded for those.
  class SecurityError < StandardError
    attr_reader :rule, :arg_index

    def initialize(message = nil, rule: nil, arg_index: nil)
      super(message)
      @rule = rule
      @arg_index = arg_index
    end
  end
  class CommandNotAllowedError < SecurityError; end
  class EnvironmentViolationError < SecurityError; end

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
  # resolved through THIS PROCESS's own PATH at spawn time, which the MCP
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
  # HOME can redirect config/rc-file loading the same way — this process's
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
    UV_CONFIG_FILE
    XDG_CONFIG_HOME
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
  # NEVER reach the child. See #build_stdio_env here and the worker's own
  # #spawn_stdio, which actually applies this list. TMPDIR is
  # deliberately server-overridable (unlike PATH/HOME) — a server pointing
  # its own child-scoped scratch dir elsewhere is accepted, not a security
  # boundary the way a binary-resolution or config-file path is.
  STDIO_ENV_PASSTHROUGH_KEYS = %w[PATH HOME LANG LC_ALL TZ TMPDIR].freeze

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
  # --find-links), requirements/constraints files, --with-editable,
  # --allow-insecure-host, AND (round 1) the config/project steering options
  # (--config-file, --project, --directory, --cache-dir — each can point uv at
  # an attacker-written uv.toml/pyproject/cache) are deliberately ABSENT:
  # absent means refused. -p/--python is handled by `python_flags` below and
  # must be a bare version number, never an interpreter path or name.
  UV_COMMON_BOOLEAN_FLAGS = %w[
    -q --quiet -v --verbose -n --no-cache --offline --no-progress --no-config --no-index --refresh --reinstall
    --isolated --managed-python --no-managed-python --native-tls --no-native-tls --no-env-file
    --no-python-downloads --compile-bytecode --no-compile-bytecode --no-build --no-binary --no-sources
  ].freeze
  UV_COMMON_VALUE_FLAGS = %w[
    --python-preference --color --link-mode --resolution --exclude-newer --prerelease --index-strategy
    --keyring-provider --python-platform --no-build-package --no-binary-package --reinstall-package
    --refresh-package -P --upgrade-package --fork-strategy
  ].freeze

  # Round 1: the only accepted shape for a launcher's -p/--python value — a
  # bare version ("3", "3.12", "3.12.1"). A path ("/tmp/evil-python") or an
  # implementation name ("pypy3") would select which interpreter RUNS the
  # package and is refused.
  LAUNCHER_PYTHON_VERSION_PATTERN = /\A\d+(\.\d+)*\z/.freeze

  # Round 1: with a selector (`npx -p <pinned> <positional>`) the positional
  # is a BIN NAME inside the selected package — held to a bin-name shape, so
  # a path, a URL or anything else cannot ride through as "the command".
  NPX_BIN_NAME_PATTERN = /\A[a-z0-9][a-z0-9._-]*\z/.freeze

  # Round 1 blocker 1 — a package manager run THROUGH its interpreter
  # (`node .../npx-cli.js -y evil`, `ruby /usr/local/bin/gem install evil`,
  # `python /usr/bin/pip install evil`) is the same registry fetch the
  # launcher rule refuses, without the launcher ever being argv[0]. Any
  # script-like value an interpreter would execute (its first positional,
  # a `deno run` target, a -r/--require/--import value) is refused when it
  # names one of these entry points. This is a DENYLIST: it covers the
  # well-known entry basenames and anything living under npm/corepack/
  # pnpm/yarn's own node_modules tree, after lexical normalization and
  # (when the path exists) symlink resolution — `/usr/local/bin/npx` is
  # itself a symlink to npx-cli.js. It does not cover a renamed copy of a
  # package manager, a vendored one under another directory name, or a
  # script that merely `require`s one; see docs/operations/mcp-stdio-servers.md.
  PACKAGE_MANAGER_ENTRY_BASENAMES = %w[
    npx-cli.js npm-cli.js npm npx corepack pnpm yarn yarn.js gem bundle bundler pip pip3 pipx uv uvx
  ].freeze
  PACKAGE_MANAGER_ENTRY_PATH_PATTERN = %r{/node_modules/(npm|corepack|pnpm|yarn)/}.freeze

  # Per-launcher option grammar for #package_launcher_pin_violation:
  #   boolean_flags  — take no value.
  #   value_flags    — take one value (attached with "=" on a long flag, or
  #                    the next token); the value is not a package.
  #   python_flags   — take one value that MUST match
  #                    LAUNCHER_PYTHON_VERSION_PATTERN.
  #   package_flags  — ADD a package (uvx/uv `--with`, pipx `--preinstall`);
  #                    each value (comma-separated for uv) must be pinned,
  #                    and the positional is still the package to pin.
  #   selector_flags — SELECT the package (npx `-p/--package`, uvx `--from`,
  #                    pipx `--spec`); must be pinned, and the positional is
  #                    then a bin/command NAME inside that package
  #                    (NPX_BIN_NAME_PATTERN), not a package spec.
  #   pinned         — :npm or :pypi, which pattern a spec is held to.
  #   positional     — :package (must be pinned unless a selector was given,
  #                    and must be present) or :script (`uv run`: a LOCAL
  #                    path — never a URL or a bare interpreter name — not
  #                    pinned; only its --with is).
  PACKAGE_LAUNCHER_RULES = {
    'npx' => {
      boolean_flags: %w[-y --yes --no -q --quiet --no-install --prefer-online --prefer-offline --ignore-existing].freeze,
      value_flags: [].freeze,
      python_flags: [].freeze,
      package_flags: [].freeze,
      selector_flags: %w[-p --package].freeze,
      pinned: :npm,
      positional: :package
    }.freeze,
    'bun x' => {
      boolean_flags: %w[-b --bun].freeze,
      value_flags: [].freeze,
      python_flags: [].freeze,
      package_flags: [].freeze,
      selector_flags: [].freeze,
      pinned: :npm,
      positional: :package
    }.freeze,
    'uvx' => {
      boolean_flags: UV_COMMON_BOOLEAN_FLAGS,
      value_flags: UV_COMMON_VALUE_FLAGS,
      python_flags: %w[-p --python].freeze,
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
      python_flags: %w[-p --python].freeze,
      package_flags: %w[-w --with].freeze,
      selector_flags: [].freeze,
      pinned: :pypi,
      positional: :script
    }.freeze,
    'pipx run' => {
      boolean_flags: %w[-v --verbose -q --quiet --no-cache --system-site-packages --fetch-missing-python].freeze,
      value_flags: [].freeze,
      python_flags: %w[-p --python].freeze,
      package_flags: %w[--preinstall].freeze,
      selector_flags: %w[--spec].freeze,
      pinned: :pypi,
      positional: :package
    }.freeze
  }.freeze

  # Grace period between SIGTERM and SIGKILL when the worker's own
  # deadline expires — gives a well-behaved child a chance to exit cleanly
  # before the harder signal. Kept here, identically to the worker's copy
  # (see the class comment above), because Mcp::WorkerStdioClient's
  # read_timeout must outlast the deadline it sends + this grace (+ a
  # margin) or the SERVER gives up on the worker before the worker gives
  # up on the child, and the operator sees "worker timeout" instead of the
  # real error.
  STDIO_TERM_GRACE_SECONDS = 2

  # IMP-f010c9fc7051 — the largest per-request deadline the worker's
  # /api/v1/mcp/execute_stdio accepts (it refuses anything above with a
  # 422). Kept here, identically to the worker's copy, so
  # Mcp::WorkerStdioClient can clamp the operator's configured deadline to
  # it instead of sending a value the worker will refuse.
  MAX_STDIO_TIMEOUT_SECONDS = 60

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
        raise_on_package_manager_entry!(command, args)
        return
      end

      rules = INLINE_CODE_RULES_BY_INTERPRETER[interpreter]
      return unless rules

      positional_index, ambiguous = scan_interpreter_flags!(args, rules, interpreter)
      raise_on_bun_shell_script!(args, positional_index, ambiguous) if interpreter == 'bun'
      raise_on_package_manager_entry!(command, args)
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

      argv = tokens.drop(1) + Array(args).map(&:to_s)
      raise_on_package_manager_entry!(tokens.first, argv)
      package_pin_violation_for_argv(tokens.first, argv)
    rescue CommandNotAllowedError => e
      e.message
    end


    # Shared validated-spawn entry point for every stdio MCP call site
    # (Mcp::SyncExecutionService#execute_stdio, Mcp::PromptService
    # #send_stdio_request, Mcp::ResourceService#send_stdio_request — the
    # server-side equivalents of the worker's stdio call sites). Takes the
    # `server` hash
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

    private

    # IMP-2c760325c102 — per-side hook called by the shared
    # #validate_stdio_server! on EVERY refusal (the worker's
    # McpSecurityService has its own, posting through the internal audit
    # endpoint). This side writes the AuditLog row directly. A refusal
    # reaching this process's validation never reaches the worker, so a
    # refused server is audited exactly once, by whichever side saw it.
    # Skipped when the server hash carries no id/account (nothing to
    # attach a row to — the parity fixtures, for one). Never raises: the
    # caller re-raises the refusal regardless.
    #
    # Round 1: the row records WHERE the refusal hit (launcher, resolved
    # argv size, offending index, rule name — SecurityError#rule/#arg_index)
    # and the error class; never argv or the message, which quotes argv and
    # may carry a token. The refusal text itself still reaches the operator
    # through the request's error / the row's last_error.
    def record_spawn_refusal_audit(server, error)
      return if server['id'].blank? || server['account_id'].blank?

      command_tokens = begin
        tokenize_command(server['command'])
      rescue CommandNotAllowedError
        server['command'].to_s.split(/\s+/)
      end

      AuditLog.create!(
        action: 'mcp.servers.spawn_refused',
        resource_type: 'McpServer',
        resource_id: server['id'],
        account_id: server['account_id'],
        user_id: nil,
        source: 'api',
        severity: 'medium',
        risk_level: 'medium',
        metadata: {
          launcher: command_tokens.first.blank? ? nil : File.basename(command_tokens.first),
          arg_count: command_tokens.drop(1).size + Array(server['args']).size,
          arg_index: error.respond_to?(:arg_index) ? error.arg_index : nil,
          rule: error.respond_to?(:rule) ? error.rule : nil,
          error_class: error.class.name.split('::').last,
          stage: 'server_validation'
        }
      )
    rescue StandardError => e
      Rails.logger.error("[Mcp::SecurityService] failed to record a stdio spawn refusal audit row: #{e.class}: #{e.message}")
    end

    # IMP-e2cba83ee39f: the ONLY env a spawned stdio MCP server process
    # ever sees (paired with the worker's own spawn_stdio's
    # unsetenv_others: true) — a
    # small, fixed passthrough from THIS RAILS PROCESS's own environment
    # (STDIO_ENV_PASSTHROUGH_KEYS: PATH, HOME, LANG, LC_ALL, TZ, TMPDIR —
    # whichever are actually set), with the validated/sanitized SERVER env
    # merged on top. PATH and HOME are FORBIDDEN in the server env (see
    # FORBIDDEN_ENV_VARS) specifically so a malicious server config can
    # never override them: a server-supplied PATH could point a bare
    # command name like "node" at an attacker-controlled binary resolved
    # through it — this process's own PATH/HOME always win. Every other
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
      if stdio_arg_looks_like_path?(value)
        if package_manager_entry?(value)
          raise CommandNotAllowedError.new(
            "Argument '#{flag_label}' loads a package manager entry point (#{value.inspect}) and is not allowed for " \
            'stdio MCP servers',
            rule: 'package_manager_entry', arg_index: nil
          )
        end
        return
      end

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
      package_pin_violation_for_argv(base_command, args)
    end

    # Dispatches an already-resolved base command + argv to its launcher's
    # grammar; raises CommandNotAllowedError (with #rule / #arg_index set,
    # see SecurityError) on a violation, returns nil otherwise. nil for
    # anything that is not a package launcher.
    def package_pin_violation_for_argv(base_command, args)
      launcher = package_launcher_for(base_command)
      return nil unless launcher

      args = Array(args).map(&:to_s)
      case launcher
      when 'npx' then package_launcher_pin_violation('npx', args, PACKAGE_LAUNCHER_RULES['npx'], offset: 0)
      when 'uvx' then package_launcher_pin_violation('uvx', args, PACKAGE_LAUNCHER_RULES['uvx'], offset: 0)
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
    # package, to the launcher's pinned-spec pattern. `offset:` is the
    # index of args[0] within the full resolved argv, so every refusal can
    # name the offending token's absolute position for the audit log.
    def package_launcher_pin_violation(launcher, args, rules, offset:)
      packages = []
      positional = nil
      positional_at = nil
      i = 0
      while i < args.length
        arg = args[i]
        if arg == '--'
          positional = args[i + 1]
          positional_at = offset + i + 1
          break
        end
        unless arg.start_with?('-')
          positional = arg
          positional_at = offset + i
          break
        end

        name, attached = arg.split('=', 2)
        # "-p=x" is not a form any of these launchers parse as p + x;
        # refuse it rather than guess. Only long options attach with "=".
        raise_unknown_launcher_option!(launcher, arg, rules, offset + i) if attached && !name.start_with?('--')

        if rules[:package_flags].include?(name) || rules[:selector_flags].include?(name)
          value = attached || args[i + 1]
          if value.nil? || value.start_with?('-')
            raise CommandNotAllowedError.new("#{launcher} option #{name} needs a package spec",
                                             rule: 'launcher_missing_value', arg_index: offset + i)
          end

          value.split(',').each { |spec| packages << [ name, spec, offset + i ] }
          i += attached ? 1 : 2
        elsif rules[:python_flags].include?(name)
          value = attached || args[i + 1]
          unless value.to_s.match?(LAUNCHER_PYTHON_VERSION_PATTERN)
            raise CommandNotAllowedError.new(
              "#{launcher} option #{name} must name a python version (e.g. 3.12), not an interpreter path or name " \
              '(the interpreter that runs the package is chosen by the host, not the server config)',
              rule: 'launcher_python_version', arg_index: offset + i
            )
          end
          i += attached ? 1 : 2
        elsif rules[:value_flags].include?(name)
          if attached.nil? && args[i + 1].nil?
            raise CommandNotAllowedError.new("#{launcher} option #{name} needs a value",
                                             rule: 'launcher_missing_value', arg_index: offset + i)
          end

          i += attached ? 1 : 2
        elsif rules[:boolean_flags].include?(name) && attached.nil?
          i += 1
        else
          raise_unknown_launcher_option!(launcher, arg, rules, offset + i)
        end
      end

      packages.each do |flag, spec, at|
        next if pinned_package_spec?(spec, rules[:pinned])

        raise_unpinned_package!(launcher, spec, rules[:pinned], via: flag, arg_index: at)
      end

      if rules[:positional] == :script
        raise_unless_local_script!(launcher, positional, positional_at) if positional
        return nil
      end
      if packages.any? { |flag, _spec, _at| rules[:selector_flags].include?(flag) }
        raise_unless_bin_name!(launcher, positional, positional_at) if positional
        return nil
      end
      if positional.nil?
        raise CommandNotAllowedError.new("#{launcher}: no package was given to run",
                                         rule: 'launcher_missing_package', arg_index: nil)
      end
      return nil if pinned_package_spec?(positional, rules[:pinned])

      raise_unpinned_package!(launcher, positional, rules[:pinned], via: nil, arg_index: positional_at)
    end

    def raise_unknown_launcher_option!(launcher, arg, rules, arg_index)
      recognized = (rules[:boolean_flags] + rules[:value_flags] + rules[:python_flags] +
                    rules[:package_flags] + rules[:selector_flags]).join(' ')
      raise CommandNotAllowedError.new(
        "#{launcher} option #{arg.inspect} is not allowed before the #{rules[:positional]} for stdio MCP servers " \
        '(an unrecognized option could change which package, registry or configuration is used); options ' \
        "recognized there: #{recognized}. Options for the package itself go after it.",
        rule: 'launcher_option', arg_index: arg_index
      )
    end

    # `uv run <target>`: the target is a LOCAL script path, never a URL and
    # never a bare interpreter name (`uv run python ...` would hand uv's
    # managed interpreter whatever follows).
    def raise_unless_local_script!(launcher, positional, arg_index)
      return if stdio_arg_looks_like_path?(positional)

      raise CommandNotAllowedError.new(
        "#{launcher}: #{positional.inspect} must be a local path (./server.py, /opt/app/server.py) for stdio MCP " \
        'servers — not a bare script name, a URL, or an interpreter',
        rule: 'launcher_script_path', arg_index: arg_index
      )
    end

    def raise_unless_bin_name!(launcher, positional, arg_index)
      return if positional.match?(NPX_BIN_NAME_PATTERN)

      raise CommandNotAllowedError.new(
        "#{launcher}: with a package selector the positional must be a bin name inside that package " \
        "(lowercase letters, digits, '.', '_', '-'), not #{positional.inspect}",
        rule: 'launcher_bin_name', arg_index: arg_index
      )
    end

    # Round 1 blocker 2 — a global option BEFORE the subcommand (`uv -q tool
    # run`, `pipx --quiet run`) would move the subcommand off args[0] and
    # skip the launcher grammar entirely. Refused outright: put options
    # after the subcommand, where the grammar sees them.
    def raise_on_launcher_global_option!(launcher, args)
      return unless args[0].to_s.start_with?('-')

      raise CommandNotAllowedError.new(
        "#{launcher}: a global option (#{args[0].inspect}) before the subcommand is not allowed for stdio MCP " \
        'servers; put options after the subcommand',
        rule: 'launcher_global_option', arg_index: 0
      )
    end

    # `uvx` IS `uv tool run`; `uv run` launches a local script but its
    # --with pulls registry packages. Every other uv subcommand is not a
    # launcher (and `uv pip install ...` as a server command just exits).
    def uv_pin_violation(args)
      raise_on_launcher_global_option!('uv', args)
      if args[0] == 'tool' && args[1] == 'run'
        package_launcher_pin_violation('uv tool run', args.drop(2), PACKAGE_LAUNCHER_RULES['uvx'], offset: 2)
      elsif args[0] == 'run'
        package_launcher_pin_violation('uv run', args.drop(1), PACKAGE_LAUNCHER_RULES['uv run'], offset: 1)
      end
    end

    def pipx_pin_violation(args)
      raise_on_launcher_global_option!('pipx', args)
      return nil unless args[0] == 'run'

      package_launcher_pin_violation('pipx run', args.drop(1), PACKAGE_LAUNCHER_RULES['pipx run'], offset: 1)
    end

    # `bun x <pkg>` is bun's package runner. Its position is found with the
    # same scan #raise_on_bun_shell_script! trusts; an ambiguous scan (an
    # unrecognized bun flag before the subcommand) is refused here too, so
    # the save-time gate cannot be more lenient than the spawn-time one.
    def bun_x_pin_violation(args)
      positional_index, ambiguous = scan_interpreter_flags!(args, INLINE_CODE_RULES_BY_INTERPRETER['bun'], 'bun')
      if ambiguous
        raise CommandNotAllowedError.new(
          'bun: an unrecognized flag appears before the subcommand, so whether this is a "bun x" package launch ' \
          'cannot be determined, and it is not allowed for stdio MCP servers',
          rule: 'launcher_option', arg_index: nil
        )
      end
      return nil unless args[positional_index] == 'x'

      package_launcher_pin_violation('bun x', args.drop(positional_index + 1), PACKAGE_LAUNCHER_RULES['bun x'],
                                     offset: positional_index + 1)
    end

    # deno resolves `npm:`/`jsr:` specifiers from the registries at run
    # time wherever they appear — a positional, or (round 1) the value of
    # an attached flag (`--preload=npm:pkg`) — so EVERY argv token in one of
    # those schemes must be pinned, with no positional modelling needed.
    # An attached flag value that is a remote URL (`--import-map=https://`,
    # `--config=http://`) is refused outright: it steers resolution from a
    # host that is not under review. A separate-token flag value is NOT
    # distinguished from the script positional (not modelled), which is
    # why `deno run https://...` itself remains allowed — deno's pinning is
    # partial; see docs/operations/mcp-stdio-servers.md.
    def deno_specifier_pin_violation(args)
      args.each_with_index do |arg, index|
        value = arg
        if arg.start_with?('-') && arg.include?('=')
          value = arg.split('=', 2).last
          if value.match?(%r{\Ahttps?://}i)
            raise CommandNotAllowedError.new(
              "deno: #{arg.split('=', 2).first} points at a remote URL, which is not allowed for stdio MCP servers",
              rule: 'deno_remote_flag_value', arg_index: index
            )
          end
        end

        if value.start_with?('npm:')
          next if value.match?(DENO_NPM_PINNED_SPECIFIER_PATTERN)

          raise_unpinned_package!('deno', value, :npm, via: nil, arg_index: index)
        elsif value.start_with?('jsr:')
          next if value.match?(DENO_JSR_PINNED_SPECIFIER_PATTERN)

          raise_unpinned_package!('deno', value, :jsr, via: nil, arg_index: index)
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

    def raise_unpinned_package!(launcher, spec, kind, via:, arg_index:)
      raise CommandNotAllowedError.new(unpinned_package_message(launcher, spec, kind, via: via),
                                       rule: 'package_pin', arg_index: arg_index)
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

    # Round 1 blocker 1 — see PACKAGE_MANAGER_ENTRY_BASENAMES. Checks every
    # script-like value the interpreter would EXECUTE: for the
    # stop-at-first-positional interpreters their first positional (every
    # non-option token when the scan was ambiguous and the positional could
    # not be told apart from an option's value); for deno and bun every
    # non-option token (their subcommand grammar is not modelled past the
    # subcommand). -r/--require/--import values are checked where they are
    # accepted (#raise_unless_path_like!). Runs its own scan so the
    # save-time gate (#package_pin_violation) holds the same line as the
    # spawn-time one (#validate_stdio_args!).
    def raise_on_package_manager_entry!(base_command, args)
      interpreter = interpreter_key_for(base_command)
      return unless interpreter

      args = Array(args).map(&:to_s)
      package_manager_entry_candidates(interpreter, args).each do |index|
        next unless package_manager_entry?(args[index])

        raise CommandNotAllowedError.new(
          "#{interpreter}: #{args[index].inspect} is a package manager entry point and is not allowed for stdio " \
          'MCP servers (a package manager run through its interpreter is the same unpinned registry fetch the ' \
          'launcher rule refuses — spawn the server package directly, pinned)',
          rule: 'package_manager_entry', arg_index: index
        )
      end
      nil
    end

    # @return [Array<Integer>] indexes into `args` of the tokens to check
    def package_manager_entry_candidates(interpreter, args)
      non_option_indexes = args.each_index.reject { |i| args[i].start_with?('-') }
      return non_option_indexes if interpreter == 'deno' || interpreter == 'bun'

      rules = INLINE_CODE_RULES_BY_INTERPRETER[interpreter]
      return non_option_indexes unless rules

      positional_index, ambiguous = scan_interpreter_flags!(args, rules, interpreter)
      return non_option_indexes if ambiguous
      return [] if positional_index >= args.length

      [ positional_index ]
    rescue CommandNotAllowedError
      # The flag scan refuses inline code (-e, -c, ...) on its own; that is a
      # SPAWN-time rule (#validate_stdio_args! raises it first there) and must
      # not leak into the save-time face through this denylist, so the scan's
      # verdict is dropped here and every non-option token is checked instead.
      non_option_indexes
    end

    # Lexical normalization first (File.expand_path, never touching the
    # filesystem), then symlink resolution when the path exists
    # (File.realpath, rescued — a non-existent or unreadable path is judged
    # on its lexical form). A bare token ("npm") expands against the cwd
    # and is judged by its basename like any other.
    def package_manager_entry?(value)
      return false if value.blank?

      expanded = File.expand_path(value)
      resolved = begin
        File.realpath(expanded)
      rescue SystemCallError, ArgumentError
        expanded
      end

      [ expanded, resolved ].any? do |path|
        path.match?(PACKAGE_MANAGER_ENTRY_PATH_PATTERN) || PACKAGE_MANAGER_ENTRY_BASENAMES.include?(File.basename(path))
      end
    rescue ArgumentError
      false
    end
  end
  end
end
