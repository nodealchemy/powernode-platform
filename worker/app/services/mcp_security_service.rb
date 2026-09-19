# frozen_string_literal: true

require 'shellwords'

# Service for MCP security hardening in worker
# Provides command whitelist validation and environment sanitization
# Mirror of server/app/services/mcp/security_service.rb (Mcp::SecurityService)
#
# SCOPE (IMP-97b6b1185748 review item 7): this stops CASUAL inline-code
# smuggling through a command/args pair that's supposed to be "just run an
# interpreter against a script file" — it is NOT a sandbox. Launchers like
# `npx -y <pkg>`, `uvx <pkg>`, `deno run -A <url>`, `bun x <pkg>`, and
# `pip install`-then-run all execute arbitrary code BY DESIGN — that's the
# entire point of a package launcher, and no argument-shape check can (or
# should try to) distinguish a legitimate package from a malicious one. The
# real security boundary is who is allowed to write server['command'] /
# server['args'] in the first place, plus whatever child-process isolation
# wraps the spawned interpreter — not this validator.
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

  # Allowed commands for stdio MCP servers. NOTE: "/usr/bin/env" and bare
  # "env" are deliberately NOT here — see #raise_if_env_wrapper!.
  ALLOWED_COMMANDS = %w[
    npx
    node
    python
    python3
    ruby
    deno
    bun
    /usr/bin/node
    /usr/bin/python
    /usr/bin/python3
    /usr/bin/ruby
    /usr/local/bin/node
    /usr/local/bin/npx
    /usr/local/bin/python
    /usr/local/bin/python3
    /usr/local/bin/ruby
    /usr/local/bin/deno
    /usr/local/bin/bun
  ].freeze

  # Extended commands enabled by configuration
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

  # Explicitly allowed environment variables
  ALLOWED_ENV_VARS = %w[
    PATH
    HOME
    USER
    LANG
    LC_ALL
    LC_CTYPE
    TERM
    TZ
    NODE_ENV
    PYTHON_PATH
    PYTHONPATH
    RUBY_VERSION
    GEM_HOME
    GEM_PATH
    BUNDLE_PATH
    XDG_CONFIG_HOME
    XDG_DATA_HOME
    XDG_CACHE_HOME
    TMPDIR
    TEMP
    TMP
  ].freeze

  # Forbidden environment variables (security sensitive)
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
  ].freeze

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

      allowed = allow_extended ? (ALLOWED_COMMANDS + EXTENDED_COMMANDS) : ALLOWED_COMMANDS

      allowed.any? do |allowed_cmd|
        base_command == allowed_cmd ||
          base_command.end_with?("/#{allowed_cmd}") ||
          File.basename(base_command) == allowed_cmd
      end
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

      return false if FORBIDDEN_ENV_VARS.include?(key)
      return true if ALLOWED_ENV_PREFIXES.any? { |prefix| key.start_with?(prefix) }
      return true if ALLOWED_ENV_VARS.include?(key)

      !strict
    end

    # Validate environment and raise if forbidden vars present
    def validate_environment!(env)
      return if env.blank?

      forbidden = env.keys.map(&:to_s).map(&:upcase) & FORBIDDEN_ENV_VARS

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

      sanitized_env = sanitize_environment(env, strict: strict_env).transform_keys(&:to_s)

      [base_command, sanitized_env, combined_args]
    end

    private

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

    # Check if base command is in the allowed list
    def base_command_in_allowed_list?(base_command, allowed)
      allowed.any? do |allowed_cmd|
        base_command == allowed_cmd ||
          base_command.end_with?("/#{allowed_cmd}") ||
          File.basename(base_command) == allowed_cmd
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
  end
end
