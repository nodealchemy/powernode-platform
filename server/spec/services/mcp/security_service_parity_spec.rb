# frozen_string_literal: true

require 'rails_helper'

# PARITY ORACLE (IMP-176a386fef98): proves Mcp::SecurityService (this
# process's Rails class) produces IDENTICAL verdicts to the worker's
# top-level McpSecurityService — the class this file was ported from — over
# one shared adversarial fixture table. A future change to either side
# that isn't mirrored to the other fails this spec, not silently drifts.
#
# SPEC-ONLY REQUIRE, NEVER RUNTIME: the server and worker apps deploy
# separately (see server/CLAUDE.md / worker/CLAUDE.md) — production code
# in app/ must NEVER require anything from worker/. This `require_relative`
# only ever runs inside the RSpec process.
#
# CONSTANT-NAME CLASH GUARD: the worker's class is top-level `McpSecurityService`
# (unnamespaced) — `defined?` guards against double-`require_relative`
# re-opening it (harmless either way, since Ruby's `require_relative` is
# itself idempotent by realpath, but explicit here so the intent is clear
# to a future reader who might otherwise assume this needs a manual reset
# between runs).
worker_security_service_path = File.expand_path('../../../../worker/app/services/mcp_security_service', __dir__)
require_relative worker_security_service_path unless defined?(::McpSecurityService)

RSpec.describe "Mcp::SecurityService parity with the worker's McpSecurityService" do
  worker_klass = ::McpSecurityService
  server_klass = ::Mcp::SecurityService

  # The exact set of security-relevant constants both classes must agree
  # on byte-for-byte — command/env allow+forbid lists, interpreter argv
  # rules, deno/bun/stdin-device handling, everything #validate_stdio_server!
  # consults. Anything added to one side and not the other fails here
  # immediately, before a single fixture even runs.
  PARITY_CONSTANTS = %w[
    ALLOWED_COMMANDS
    EXTENDED_COMMANDS
    ALLOWED_ABSOLUTE_COMMAND_DIRS
    ALLOWED_ENV_PREFIXES
    ALLOWED_ENV_VARS
    FORBIDDEN_ENV_VARS
    FORBIDDEN_ENV_PREFIXES
    STDIO_ENV_PASSTHROUGH_KEYS
    INLINE_CODE_RULES_BY_INTERPRETER
    MCP_MODULE_NAME_PATTERN
    DENO_ALLOWED_SUBCOMMANDS
    DENO_BOOLEAN_GLOBAL_FLAGS
    DENO_VALUE_GLOBAL_FLAGS
    DENO_UNSTABLE_PREFIX
    STDIN_DASH_INTERPRETERS
    STDIN_DEVICE_PATH_PATTERN
    SHELL_METACHARACTER_PATTERN
    STOP_AT_FIRST_POSITIONAL_INTERPRETERS
  ].freeze

  describe 'constants' do
    PARITY_CONSTANTS.each do |const_name|
      it "#{const_name} is identical on both classes" do
        worker_value = worker_klass.const_get(const_name)
        server_value = server_klass.const_get(const_name)

        expect(server_value).to eq(worker_value),
                                 "#{const_name} diverged — worker: #{worker_value.inspect}, " \
                                 "server: #{server_value.inspect}"
      end
    end
  end

  # Each fixture: { name:, command:, args:, env:, capabilities: }. Built
  # from the reviewer's real-spawn-adversarial probes (probe97b.rb,
  # probe97c.rb, probe97d.rb — every `t(...)` call across all three,
  # mechanically extracted so no case was hand-transcribed and silently
  # dropped or altered) plus the forbidden-env-var/prefix classes from
  # IMP-e2cba83ee39f (rounds 1-3) and the exact-path command-whitelist
  # cases from IMP-b6be9d979e13.
  MCP_SECURITY_PARITY_FIXTURES = [
      {:name=>"node -e", :command=>"node", :args=>["-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"cmd ruby -e", :command=>"ruby -e p:ok", :args=>[], :env=>{}, :capabilities=>{}},
      {:name=>"env -i ruby -e", :command=>"/usr/bin/env", :args=>["-i", "ruby", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"env -S", :command=>"/usr/bin/env", :args=>["-S", "ruby -e x"], :env=>{}, :capabilities=>{}},
      {:name=>"cmd env node", :command=>"env node", :args=>["x.js"], :env=>{}, :capabilities=>{}},
      {:name=>"python3 -Ic", :command=>"python3", :args=>["-Ic", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby -we", :command=>"ruby", :args=>["-we", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby -ne", :command=>"ruby", :args=>["-ne", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"node -ie", :command=>"node", :args=>["-ie", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"npx -c", :command=>"npx", :args=>["-c", "id"], :env=>{}, :capabilities=>{}},
      {:name=>"npx --call=", :command=>"npx", :args=>["--call=id"], :env=>{}, :capabilities=>{}},
      {:name=>"npx -yc", :command=>"npx", :args=>["-yc", "id"], :env=>{}, :capabilities=>{}},
      {:name=>"node --loader", :command=>"node", :args=>["--loader", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"node --experimental-loader=data", :command=>"node", :args=>["--experimental-loader=data:text/javascript,1"], :env=>{}, :capabilities=>{}},
      {:name=>"node -i", :command=>"node", :args=>["-i"], :env=>{}, :capabilities=>{}},
      {:name=>"python3 -i", :command=>"python3", :args=>["-i"], :env=>{}, :capabilities=>{}},
      {:name=>"python3 -m code", :command=>"python3", :args=>["-m", "code"], :env=>{}, :capabilities=>{}},
      {:name=>"python3 -", :command=>"python3", :args=>["-"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby -I/tmp -revil.rb", :command=>"ruby", :args=>["-I/tmp", "-revil.rb"], :env=>{}, :capabilities=>{}},
      {:name=>"node -r highlight.js", :command=>"node", :args=>["-r", "highlight.js"], :env=>{}, :capabilities=>{}},
      {:name=>"node -r ./x.js", :command=>"node", :args=>["-r", "./x.js"], :env=>{}, :capabilities=>{}},
      {:name=>"node --import ./reg.mjs", :command=>"node", :args=>["--import", "./reg.mjs"], :env=>{}, :capabilities=>{}},
      {:name=>"node --import tsx", :command=>"node", :args=>["--import", "tsx"], :env=>{}, :capabilities=>{}},
      {:name=>"quoted node", :command=>"\"node\" -e x", :args=>[], :env=>{}, :capabilities=>{}},
      {:name=>"tab", :command=>"node\t-e\tx", :args=>[], :env=>{}, :capabilities=>{}},
      {:name=>"newline", :command=>"node\n-e\nx", :args=>[], :env=>{}, :capabilities=>{}},
      {:name=>"unbalanced", :command=>"node -e 'x", :args=>[], :env=>{}, :capabilities=>{}},
      {:name=>"unbalanced basename trick", :command=>"ruby -e p:ok #'/node", :args=>[], :env=>{}, :capabilities=>{}},
      {:name=>"escaped space", :command=>"node\\ -e x", :args=>[], :env=>{}, :capabilities=>{}},
      {:name=>"single-quoted -e", :command=>"node '-e' x", :args=>[], :env=>{}, :capabilities=>{}},
      {:name=>"-- then -e", :command=>"node", :args=>["--", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"--e", :command=>"node", :args=>["--e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"--eval ''", :command=>"node", :args=>["--eval", ""], :env=>{}, :capabilities=>{}},
      {:name=>"--eval=", :command=>"node", :args=>["--eval="], :env=>{}, :capabilities=>{}},
      {:name=>"--EVAL", :command=>"node", :args=>["--EVAL", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"-E node", :command=>"node", :args=>["-E", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"python -um code", :command=>"python3", :args=>["-um", "code"], :env=>{}, :capabilities=>{}},
      {:name=>"python -Wc (value)", :command=>"python3", :args=>["-Wc", "x.py"], :env=>{}, :capabilities=>{}},
      {:name=>"python -X c", :command=>"python3", :args=>["-X", "importtime", "-c", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"python -Xc (attached)", :command=>"python3", :args=>["-Xc"], :env=>{}, :capabilities=>{}},
      {:name=>"python -W then -c separate", :command=>"python3", :args=>["-W", "ignore", "-c", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"python -m mcp_server_git", :command=>"python", :args=>["-m", "mcp_server_git", "--repository", "/r"], :env=>{}, :capabilities=>{}},
      {:name=>"python3 -m uvicorn", :command=>"python3", :args=>["-m", "uvicorn", "app:app"], :env=>{}, :capabilities=>{}},
      {:name=>"python3 script.py", :command=>"python3", :args=>["server.py"], :env=>{}, :capabilities=>{}},
      {:name=>"python3 /dev/stdin", :command=>"python3", :args=>["/dev/stdin"], :env=>{}, :capabilities=>{}},
      {:name=>"node /dev/stdin", :command=>"node", :args=>["/dev/stdin"], :env=>{}, :capabilities=>{}},
      {:name=>"node --import=/dev/stdin", :command=>"node", :args=>["--import=/dev/stdin"], :env=>{}, :capabilities=>{}},
      {:name=>"node -r /proc/self/fd/0", :command=>"node", :args=>["-r", "/proc/self/fd/0"], :env=>{}, :capabilities=>{}},
      {:name=>"node --inspect=0.0.0.0", :command=>"node", :args=>["--inspect=0.0.0.0:9229", "s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"node --inspect-brk", :command=>"node", :args=>["--inspect-brk", "s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"node --env-file", :command=>"node", :args=>["--env-file=/tmp/.env", "s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"node --run", :command=>"node", :args=>["--run", "build"], :env=>{}, :capabilities=>{}},
      {:name=>"node --test", :command=>"node", :args=>["--test"], :env=>{}, :capabilities=>{}},
      {:name=>"node -C cond", :command=>"node", :args=>["-C", "x", "s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"node -pe cluster", :command=>"node", :args=>["-pe", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"node -rfoo attached", :command=>"node", :args=>["-rfoo"], :env=>{}, :capabilities=>{}},
      {:name=>"node -r=./x? ", :command=>"node", :args=>["-r=./x"], :env=>{}, :capabilities=>{}},
      {:name=>"node --require=pkg", :command=>"node", :args=>["--require=pkg"], :env=>{}, :capabilities=>{}},
      {:name=>"node --require (next)", :command=>"node", :args=>["--require", "pkg"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby -S irb", :command=>"ruby", :args=>["-S", "irb"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby -x", :command=>"ruby", :args=>["-x"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby -rjson", :command=>"ruby", :args=>["-rjson", "s.rb"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby -W:no-deprecated", :command=>"ruby", :args=>["-W:no-deprecated", "s.rb"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby --enable=frozen", :command=>"ruby", :args=>["--enable=frozen-string-literal", "s.rb"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby --crash-report", :command=>"ruby", :args=>["--crash-report=/tmp/x", "s.rb"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby -p (loop)", :command=>"ruby", :args=>["-p", "s.rb"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby -de?", :command=>"ruby", :args=>["-de", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"deno eval", :command=>"deno", :args=>["eval", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"deno -L debug eval", :command=>"deno", :args=>["-L", "debug", "eval", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"deno --log-level debug eval", :command=>"deno", :args=>["--log-level", "debug", "eval", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"deno run -", :command=>"deno", :args=>["run", "-"], :env=>{}, :capabilities=>{}},
      {:name=>"deno task", :command=>"deno", :args=>["task", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"deno repl", :command=>"deno", :args=>["repl"], :env=>{}, :capabilities=>{}},
      {:name=>"deno run -A url", :command=>"deno", :args=>["run", "-A", "https://e/x.ts"], :env=>{}, :capabilities=>{}},
      {:name=>"bun run -", :command=>"bun", :args=>["run", "-"], :env=>{}, :capabilities=>{}},
      {:name=>"bun -e", :command=>"bun", :args=>["-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"bun x pkg", :command=>"bun", :args=>["x", "pkg"], :env=>{}, :capabilities=>{}},
      {:name=>"bun --print", :command=>"bun", :args=>["--print", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"npx node -e", :command=>"npx", :args=>["-y", "node", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"npx -y @mcp/server", :command=>"npx", :args=>["-y", "@modelcontextprotocol/server-filesystem", "/tmp"], :env=>{}, :capabilities=>{}},
      {:name=>"node dist/index.js", :command=>"node", :args=>["dist/index.js"], :env=>{}, :capabilities=>{}},
      {:name=>"uvx", :command=>"uvx", :args=>["mcp-server-fetch"], :env=>{}, :capabilities=>{"allow_extended_commands"=>true}},
      {:name=>"attacker path node", :command=>"/tmp/evil/node", :args=>["s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"./node", :command=>"./node", :args=>["s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"nil command", :command=>nil, :args=>[], :env=>{}, :capabilities=>{}},
      {:name=>"empty", :command=>"", :args=>[], :env=>{}, :capabilities=>{}},
      {:name=>"spaces only", :command=>"   ", :args=>[], :env=>{}, :capabilities=>{}},
      {:name=>"cmd with ;", :command=>"node;id", :args=>[], :env=>{}, :capabilities=>{}},
      {:name=>"arg metachar in cmd", :command=>"node s.js a&b", :args=>[], :env=>{}, :capabilities=>{}},
      {:name=>"docker -e ext", :command=>"docker", :args=>["run", "-e", "A=1", "img"], :env=>{}, :capabilities=>{"allow_extended_commands"=>true}},
      {:name=>"basename trick", :command=>"ruby -e p:ok #'/node", :args=>[], :env=>{}, :capabilities=>{}},
      {:name=>"ruby -W:no-dep", :command=>"ruby", :args=>["-W:no-deprecated", "s.rb"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby -Ke", :command=>"ruby", :args=>["-Ke", "s.rb"], :env=>{}, :capabilities=>{}},
      {:name=>"node -Cdev", :command=>"node", :args=>["-Cdevelopment", "s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby -WS? cluster", :command=>"ruby", :args=>["-wS", "irb"], :env=>{}, :capabilities=>{}},
      {:name=>"node --inspect", :command=>"node", :args=>["--inspect", "s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"--inspect-port", :command=>"node", :args=>["--inspect-port=0", "s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"--inspect-publish-uid", :command=>"node", :args=>["--inspect-publish-uid=http", "s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"--inspectX", :command=>"node", :args=>["--inspectfoo"], :env=>{}, :capabilities=>{}},
      {:name=>"--debug-port", :command=>"node", :args=>["--debug-port=9229", "s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"--env-file", :command=>"node", :args=>["--env-file=.env", "s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"--run", :command=>"node", :args=>["--run", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"--openssl-config", :command=>"node", :args=>["--openssl-config=/tmp/x.cnf", "s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"--redirect-warnings", :command=>"node", :args=>["--redirect-warnings=/tmp/x", "s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"bun --inspect-brk", :command=>"bun", :args=>["--inspect-brk", "s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"bun --run?", :command=>"bun", :args=>["run", "s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"-m mcp_server_git", :command=>"python", :args=>["-m", "mcp_server_git"], :env=>{}, :capabilities=>{}},
      {:name=>"-mmcp_server_git", :command=>"python3", :args=>["-mmcp_server_git"], :env=>{}, :capabilities=>{}},
      {:name=>"-Im mcp_x", :command=>"python3", :args=>["-Im", "mcp_x"], :env=>{}, :capabilities=>{}},
      {:name=>"-uImcp? (value)", :command=>"python3", :args=>["-uImmcp_x"], :env=>{}, :capabilities=>{}},
      {:name=>"-m=mcp_x", :command=>"python3", :args=>["-m=mcp_x"], :env=>{}, :capabilities=>{}},
      {:name=>"-m MCP_X", :command=>"python3", :args=>["-m", "MCP_X"], :env=>{}, :capabilities=>{}},
      {:name=>"-m code", :command=>"python3", :args=>["-m", "code"], :env=>{}, :capabilities=>{}},
      {:name=>"-m awslabs.x_mcp_server", :command=>"python3", :args=>["-m", "awslabs.x_mcp_server"], :env=>{}, :capabilities=>{}},
      {:name=>"-m mcp", :command=>"python3", :args=>["-m", "mcp"], :env=>{}, :capabilities=>{}},
      {:name=>"-m mcp.cli", :command=>"python3", :args=>["-m", "mcp.cli"], :env=>{}, :capabilities=>{}},
      {:name=>"-m pip.mcp?", :command=>"python3", :args=>["-m", "pip.mcp"], :env=>{}, :capabilities=>{}},
      {:name=>"-m pdb_mcp", :command=>"python3", :args=>["-m", "pdb_mcp"], :env=>{}, :capabilities=>{}},
      {:name=>"-m mcp; later -c", :command=>"python3", :args=>["-m", "mcp_x", "-c", "conf.yaml"], :env=>{}, :capabilities=>{}},
      {:name=>"-m no value", :command=>"python3", :args=>["-m"], :env=>{}, :capabilities=>{}},
      {:name=>"-Wx -m code", :command=>"python3", :args=>["-Wx", "-m", "code"], :env=>{}, :capabilities=>{}},
      {:name=>"-Xmcp -m code", :command=>"python3", :args=>["-Xfoo", "-mcode"], :env=>{}, :capabilities=>{}},
      {:name=>"-m ../mcp", :command=>"python3", :args=>["-m", "../mcp"], :env=>{}, :capabilities=>{}},
      {:name=>"-m mcp-x (dash)", :command=>"python3", :args=>["-m", "mcp-x"], :env=>{}, :capabilities=>{}},
      {:name=>"-m unicode", :command=>"python3", :args=>["-m", "mcpс"], :env=>{}, :capabilities=>{}},
      {:name=>"deno run", :command=>"deno", :args=>["run", "-A", "s.ts"], :env=>{}, :capabilities=>{}},
      {:name=>"deno --log-level=debug eval", :command=>"deno", :args=>["--log-level=debug", "eval", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"deno -q eval", :command=>"deno", :args=>["-q", "eval", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"deno --unknown v run(eval)", :command=>"deno", :args=>["--unstable-x", "run", "s.ts"], :env=>{}, :capabilities=>{}},
      {:name=>"deno -L run eval", :command=>"deno", :args=>["-L", "run", "eval", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"deno --config run eval", :command=>"deno", :args=>["--config", "run", "eval", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"deno --v8-flags run eval?", :command=>"deno", :args=>["--v8-flags", "run", "eval", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"deno --import-map=x eval", :command=>"deno", :args=>["--import-map=x", "eval", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"deno -Ldebug eval", :command=>"deno", :args=>["-Ldebug", "eval", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"deno script.ts", :command=>"deno", :args=>["s.ts"], :env=>{}, :capabilities=>{}},
      {:name=>"deno (none)", :command=>"deno", :args=>[], :env=>{}, :capabilities=>{}},
      {:name=>"deno run --eval?", :command=>"deno", :args=>["run", "--eval", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"deno serve", :command=>"deno", :args=>["serve", "s.ts"], :env=>{}, :capabilities=>{}},
      {:name=>"deno x", :command=>"deno", :args=>["x", "pkg"], :env=>{}, :capabilities=>{}},
      {:name=>"deno run /dev/stdin", :command=>"deno", :args=>["run", "/dev/stdin"], :env=>{}, :capabilities=>{}},
      {:name=>"node -r /dev/./stdin", :command=>"node", :args=>["-r", "/dev/./stdin"], :env=>{}, :capabilities=>{}},
      {:name=>"--import=//dev/stdin", :command=>"node", :args=>["--import=//dev/stdin"], :env=>{}, :capabilities=>{}},
      {:name=>"python3 /dev//stdin", :command=>"python3", :args=>["/dev//stdin"], :env=>{}, :capabilities=>{}},
      {:name=>"npx -y server", :command=>"npx", :args=>["-y", "@modelcontextprotocol/server-filesystem", "/tmp"], :env=>{}, :capabilities=>{}},
      {:name=>"node s.js -e (script arg)", :command=>"node", :args=>["s.js", "-e", "foo"], :env=>{}, :capabilities=>{}},
      {:name=>"python -m mcp_x --repo /r", :command=>"python", :args=>["-m", "mcp_server_git", "--repository", "/r"], :env=>{}, :capabilities=>{}},
      {:name=>"node --title foo -e", :command=>"node", :args=>["--title", "foo", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"node --conditions c -e", :command=>"node", :args=>["--conditions", "c", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"node --input-type module -e", :command=>"node", :args=>["--input-type", "module", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"node --unhandled-rejections strict -e", :command=>"node", :args=>["--unhandled-rejections", "strict", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"node --dns-result-order v4 -e", :command=>"node", :args=>["--dns-result-order", "ipv4first", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"python -W ignore -c", :command=>"python3", :args=>["-W", "ignore", "-c", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"python --check-hash-based-pycs always -c", :command=>"python3", :args=>["--check-hash-based-pycs", "always", "-c", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"python -X dev -c", :command=>"python3", :args=>["-X", "dev", "-c", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby --encoding utf-8 -e", :command=>"ruby", :args=>["--encoding", "utf-8", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby --backtrace-limit 3 -e", :command=>"ruby", :args=>["--backtrace-limit", "3", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby --enable frozen -e", :command=>"ruby", :args=>["--enable", "frozen-string-literal", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby -C dir -e", :command=>"ruby", :args=>["-C", "dir", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby -E enc -e", :command=>"ruby", :args=>["-E", "utf-8", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"python -W (sep) then -c", :command=>"python3", :args=>["-W", "-c", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"node --require ./a.js -e", :command=>"node", :args=>["--require", "./a.js", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"node -r ./a.js -e", :command=>"node", :args=>["-r", "./a.js", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"node -- -e", :command=>"node", :args=>["--", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"node -- script -e", :command=>"node", :args=>["--", "s.js", "-e"], :env=>{}, :capabilities=>{}},
      {:name=>"python -- -c", :command=>"python3", :args=>["--", "-c", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"bun --cwd x run build", :command=>"bun", :args=>["--cwd", "x", "run", "build"], :env=>{}, :capabilities=>{}},
      {:name=>"bun run build", :command=>"bun", :args=>["run", "build"], :env=>{}, :capabilities=>{}},
      {:name=>"bun run ./s.js", :command=>"bun", :args=>["run", "./s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"bun ./s.js", :command=>"bun", :args=>["./s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"bun start", :command=>"bun", :args=>["start"], :env=>{}, :capabilities=>{}},
      {:name=>"bun --smol -e", :command=>"bun", :args=>["--smol", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"python -m code -e", :command=>"python3", :args=>["-m", "code", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"python -m mcp_x -e (prog arg)", :command=>"python3", :args=>["-m", "mcp_server_x", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"python -Wc then -e", :command=>"python3", :args=>["-Wc", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"node -C x -e", :command=>"node", :args=>["-C", "x", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"ruby -Ke -e", :command=>"ruby", :args=>["-Ke", "-e", "x"], :env=>{}, :capabilities=>{}},
      {:name=>"node s.js -e (prog)", :command=>"node", :args=>["s.js", "-e", "foo"], :env=>{}, :capabilities=>{}},
      {:name=>"python -m mcp_x --repo", :command=>"python", :args=>["-m", "mcp_server_git", "--repository", "/r"], :env=>{}, :capabilities=>{}},
      {:name=>"relative path bin/node", :command=>"bin/node", :args=>["s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"parent-relative path ../x/node", :command=>"../x/node", :args=>["s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"absolute path outside canonical dirs (/opt/x/python3)", :command=>"/opt/x/python3", :args=>["server.py"], :env=>{}, :capabilities=>{}},
      {:name=>"whitelisted absolute path with trailing whitespace", :command=>"\"/usr/bin/node \" server.js", :args=>[], :env=>{}, :capabilities=>{}},
      {:name=>"traversal path normalizing to a whitelisted one", :command=>"/usr/bin/../../tmp/node", :args=>["s.js"], :env=>{}, :capabilities=>{}},
      {:name=>"exact /usr/local/bin match", :command=>"/usr/local/bin/python3", :args=>["server.py"], :env=>{}, :capabilities=>{}},
      {:name=>"exact /bin match", :command=>"/bin/ruby", :args=>["mcp_server.rb"], :env=>{}, :capabilities=>{}},
      {:name=>"extended command refused without allow_extended_commands", :command=>"/usr/bin/docker", :args=>["run", "img"], :env=>{}, :capabilities=>{}},
      {:name=>"extended command allowed with allow_extended_commands", :command=>"/usr/bin/docker", :args=>["run", "img"], :env=>{}, :capabilities=>{"allow_extended_commands"=>true}},
      {:name=>"env: LD_PRELOAD forbidden", :command=>"node", :args=>["s.js"], :env=>{"LD_PRELOAD"=>"/tmp/evil.so"}, :capabilities=>{}},
      {:name=>"env: LD_AUDIT forbidden (prefix)", :command=>"node", :args=>["s.js"], :env=>{"LD_AUDIT"=>"/tmp/evil.so"}, :capabilities=>{}},
      {:name=>"env: DYLD_INSERT_LIBRARIES forbidden", :command=>"node", :args=>["s.js"], :env=>{"DYLD_INSERT_LIBRARIES"=>"/tmp/evil.dylib"}, :capabilities=>{}},
      {:name=>"env: DYLD_FRAMEWORK_PATH forbidden (prefix)", :command=>"node", :args=>["s.js"], :env=>{"DYLD_FRAMEWORK_PATH"=>"/tmp/evil"}, :capabilities=>{}},
      {:name=>"env: server-supplied PATH forbidden", :command=>"node", :args=>["s.js"], :env=>{"PATH"=>"/tmp/evil-bin"}, :capabilities=>{}},
      {:name=>"env: server-supplied HOME forbidden", :command=>"node", :args=>["s.js"], :env=>{"HOME"=>"/tmp/evil-home"}, :capabilities=>{}},
      {:name=>"env: NODE_PATH forbidden", :command=>"node", :args=>["s.js"], :env=>{"NODE_PATH"=>"/tmp/evil"}, :capabilities=>{}},
      {:name=>"env: PYTHONPATH forbidden", :command=>"python3", :args=>["s.py"], :env=>{"PYTHONPATH"=>"/tmp/evil"}, :capabilities=>{}},
      {:name=>"env: PYTHONUSERBASE forbidden", :command=>"python3", :args=>["s.py"], :env=>{"PYTHONUSERBASE"=>"/tmp/evil"}, :capabilities=>{}},
      {:name=>"env: GEM_HOME forbidden", :command=>"ruby", :args=>["s.rb"], :env=>{"GEM_HOME"=>"/tmp/evil"}, :capabilities=>{}},
      {:name=>"env: BUNDLE_PATH forbidden", :command=>"ruby", :args=>["s.rb"], :env=>{"BUNDLE_PATH"=>"/tmp/evil"}, :capabilities=>{}},
      {:name=>"env: BUNDLE_GEMFILE forbidden", :command=>"ruby", :args=>["s.rb"], :env=>{"BUNDLE_GEMFILE"=>"/tmp/evil/Gemfile"}, :capabilities=>{}},
      {:name=>"env: GCONV_PATH forbidden", :command=>"node", :args=>["s.js"], :env=>{"GCONV_PATH"=>"/tmp/evil"}, :capabilities=>{}},
      {:name=>"env: HOSTALIASES forbidden", :command=>"node", :args=>["s.js"], :env=>{"HOSTALIASES"=>"/tmp/evil-hosts"}, :capabilities=>{}},
      {:name=>"env: NPM_CONFIG_REGISTRY forbidden (prefix)", :command=>"npx", :args=>["-y", "pkg"], :env=>{"NPM_CONFIG_REGISTRY"=>"https://evil.example"}, :capabilities=>{}},
      {:name=>"env: PIP_INDEX_URL forbidden (prefix)", :command=>"python3", :args=>["s.py"], :env=>{"PIP_INDEX_URL"=>"https://evil.example"}, :capabilities=>{}},
      {:name=>"env: BUN_CONFIG_REGISTRY forbidden (prefix)", :command=>"bun", :args=>["s.js"], :env=>{"BUN_CONFIG_REGISTRY"=>"https://evil.example"}, :capabilities=>{}},
      {:name=>"env: UV_INDEX_URL forbidden (named)", :command=>"uvx", :args=>["pkg"], :env=>{"UV_INDEX_URL"=>"https://evil.example"}, :capabilities=>{"allow_extended_commands"=>true}},
      {:name=>"env: CLASSPATH forbidden", :command=>"java", :args=>["-jar", "s.jar"], :env=>{"CLASSPATH"=>"/tmp/evil.jar"}, :capabilities=>{"allow_extended_commands"=>true}},
      {:name=>"env: DOCKER_HOST forbidden", :command=>"docker", :args=>["run", "img"], :env=>{"DOCKER_HOST"=>"tcp://evil.example:2375"}, :capabilities=>{"allow_extended_commands"=>true}},
      {:name=>"env: GOPROXY forbidden", :command=>"go", :args=>["run", "."], :env=>{"GOPROXY"=>"https://evil.example"}, :capabilities=>{"allow_extended_commands"=>true}},
      {:name=>"env: legit MCP_/OPENAI_ prefixed vars pass through", :command=>"node", :args=>["s.js"], :env=>{"MCP_API_KEY"=>"secret", "OPENAI_API_KEY"=>"secret2"}, :capabilities=>{}},
      {:name=>"env: legit LANG/TZ override passes through", :command=>"node", :args=>["s.js"], :env=>{"LANG"=>"en_US.UTF-8", "TZ"=>"America/New_York"}, :capabilities=>{}}
    ].freeze

  def self.verdict_for(klass, fixture)
    server_hash = {
      'command' => fixture[:command],
      'args' => fixture[:args] || [],
      'env' => fixture[:env] || {},
      'capabilities' => fixture[:capabilities] || {}
    }
    command, env, argv = klass.validate_stdio_server!(server_hash)
    { allowed: true, command: command, env: env, argv: argv }
  rescue klass::SecurityError => e
    { allowed: false, error_class: e.class.name.split('::').last, message: e.message }
  end

  MCP_SECURITY_PARITY_FIXTURES.each do |fixture|
    it "agrees with the worker on: #{fixture[:name]}" do
      worker_verdict = self.class.verdict_for(worker_klass, fixture)
      server_verdict = self.class.verdict_for(server_klass, fixture)

      expect(server_verdict[:allowed]).to eq(worker_verdict[:allowed]),
                                           "verdict diverged for #{fixture[:name].inspect} — " \
                                           "worker: #{worker_verdict.inspect}, server: #{server_verdict.inspect}"

      if worker_verdict[:allowed]
        expect(server_verdict[:command]).to eq(worker_verdict[:command])
        expect(server_verdict[:argv]).to eq(worker_verdict[:argv])
        expect(server_verdict[:env]).to eq(worker_verdict[:env])
      else
        expect(server_verdict[:error_class]).to eq(worker_verdict[:error_class])
        expect(server_verdict[:message]).to eq(worker_verdict[:message])
      end
    end
  end
end
