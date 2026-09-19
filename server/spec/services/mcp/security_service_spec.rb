# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::SecurityService do
  describe '.validate_command!' do
    context 'with allowed commands' do
      it 'allows npx command' do
        expect { described_class.validate_command!('npx @modelcontextprotocol/server-filesystem') }
          .not_to raise_error
      end

      it 'allows node command' do
        expect { described_class.validate_command!('node server.js') }
          .not_to raise_error
      end

      it 'allows python command' do
        expect { described_class.validate_command!('python mcp_server.py') }
          .not_to raise_error
      end

      it 'allows python3 command' do
        expect { described_class.validate_command!('python3 server.py') }
          .not_to raise_error
      end

      it 'allows ruby command' do
        expect { described_class.validate_command!('ruby mcp_server.rb') }
          .not_to raise_error
      end

      it 'allows deno command' do
        expect { described_class.validate_command!('deno run server.ts') }
          .not_to raise_error
      end

      it 'allows bun command' do
        expect { described_class.validate_command!('bun run server.ts') }
          .not_to raise_error
      end

      it 'allows full path to node' do
        expect { described_class.validate_command!('/usr/bin/node server.js') }
          .not_to raise_error
      end

      # IMP-176a386fef98 (ported from the worker's IMP-97b6b1185748 item 2):
      # `env` is now refused as the command entirely, never unwrapped to
      # find a "real" interpreter inside it.
      it "refuses /usr/bin/env entirely (the env wrapper is never unwrapped)" do
        expect { described_class.validate_command!('/usr/bin/env node server.js') }
          .to raise_error(Mcp::SecurityService::CommandNotAllowedError, /'env' wrapper is not allowed/)
      end

      it 'allows blank commands without error' do
        expect { described_class.validate_command!('') }.not_to raise_error
        expect { described_class.validate_command!(nil) }.not_to raise_error
      end
    end

    context 'with extended commands' do
      it 'blocks uvx by default' do
        expect { described_class.validate_command!('uvx mcp-server-git') }
          .to raise_error(Mcp::SecurityService::CommandNotAllowedError, /not in the allowed list/)
      end

      it 'allows uvx with allow_extended flag' do
        expect { described_class.validate_command!('uvx mcp-server-git', allow_extended: true) }
          .not_to raise_error
      end

      it 'allows docker with allow_extended flag' do
        expect { described_class.validate_command!('docker run mcp-server', allow_extended: true) }
          .not_to raise_error
      end

      it 'allows uv with allow_extended flag' do
        expect { described_class.validate_command!('uv run server.py', allow_extended: true) }
          .not_to raise_error
      end
    end

    context 'with blocked commands' do
      it 'blocks bash' do
        expect { described_class.validate_command!('bash -c "rm -rf /"') }
          .to raise_error(Mcp::SecurityService::CommandNotAllowedError)
      end

      it 'blocks sh' do
        expect { described_class.validate_command!('sh script.sh') }
          .to raise_error(Mcp::SecurityService::CommandNotAllowedError)
      end

      it 'blocks curl' do
        expect { described_class.validate_command!('curl https://evil.com') }
          .to raise_error(Mcp::SecurityService::CommandNotAllowedError)
      end

      it 'blocks wget' do
        expect { described_class.validate_command!('wget https://evil.com') }
          .to raise_error(Mcp::SecurityService::CommandNotAllowedError)
      end

      it 'blocks arbitrary executables' do
        expect { described_class.validate_command!('/tmp/malware') }
          .to raise_error(Mcp::SecurityService::CommandNotAllowedError)
      end
    end

    context 'with dangerous argument patterns' do
      it 'blocks semicolon command chaining' do
        expect { described_class.validate_command!('node server.js; rm -rf /') }
          .to raise_error(Mcp::SecurityService::CommandNotAllowedError, /dangerous pattern/)
      end

      it 'blocks pipe command chaining' do
        expect { described_class.validate_command!('node server.js | bash') }
          .to raise_error(Mcp::SecurityService::CommandNotAllowedError, /dangerous pattern/)
      end

      it 'blocks ampersand command chaining' do
        expect { described_class.validate_command!('node server.js && rm -rf /') }
          .to raise_error(Mcp::SecurityService::CommandNotAllowedError, /dangerous pattern/)
      end

      it 'blocks backtick command substitution' do
        expect { described_class.validate_command!('node `whoami`') }
          .to raise_error(Mcp::SecurityService::CommandNotAllowedError, /dangerous pattern/)
      end

      it 'blocks $() command substitution' do
        expect { described_class.validate_command!('node $(cat /etc/passwd)') }
          .to raise_error(Mcp::SecurityService::CommandNotAllowedError, /dangerous pattern/)
      end

      it 'blocks ${} variable expansion' do
        expect { described_class.validate_command!('node ${PATH}') }
          .to raise_error(Mcp::SecurityService::CommandNotAllowedError, /dangerous pattern/)
      end

      it 'blocks output redirection' do
        expect { described_class.validate_command!('node server.js > /etc/passwd') }
          .to raise_error(Mcp::SecurityService::CommandNotAllowedError, /dangerous pattern/)
      end

      it 'blocks eval' do
        expect { described_class.validate_command!('node -e "eval(process.argv[1])"') }
          .to raise_error(Mcp::SecurityService::CommandNotAllowedError, /dangerous pattern/)
      end
    end
  end

  describe '.command_allowed?' do
    it 'returns true for allowed commands' do
      expect(described_class.command_allowed?('npx')).to be true
      expect(described_class.command_allowed?('node')).to be true
      expect(described_class.command_allowed?('python')).to be true
    end

    it 'returns false for blocked commands' do
      expect(described_class.command_allowed?('bash')).to be false
      expect(described_class.command_allowed?('sh')).to be false
      expect(described_class.command_allowed?('curl')).to be false
    end

    it 'respects allow_extended flag' do
      expect(described_class.command_allowed?('uvx', allow_extended: false)).to be false
      expect(described_class.command_allowed?('uvx', allow_extended: true)).to be true
    end
  end

  describe '.sanitize_environment' do
    context 'with allowed variables' do
      # IMP-176a386fef98 (ported from the worker's IMP-e2cba83ee39f): PATH
      # and HOME are now FORBIDDEN in server-supplied env — a server env is
      # never the source of truth for either; see #build_stdio_env's
      # worker-own-process passthrough instead.
      it 'allows USER (PATH/HOME moved to forbidden — see the .validate_environment! block below)' do
        env = { 'USER' => 'mcp-runner' }
        result = described_class.sanitize_environment(env)

        expect(result).to include('USER' => 'mcp-runner')
      end

      it 'allows MCP_ prefixed variables' do
        env = { 'MCP_SERVER_URL' => 'https://api.example.com', 'MCP_API_KEY' => 'secret' }
        result = described_class.sanitize_environment(env)

        expect(result).to include('MCP_SERVER_URL' => 'https://api.example.com')
        expect(result).to include('MCP_API_KEY' => 'secret')
      end

      it 'allows OPENAI_ prefixed variables' do
        env = { 'OPENAI_API_KEY' => 'sk-...' }
        result = described_class.sanitize_environment(env)

        expect(result).to include('OPENAI_API_KEY' => 'sk-...')
      end

      it 'allows ANTHROPIC_ prefixed variables' do
        env = { 'ANTHROPIC_API_KEY' => 'sk-ant-...' }
        result = described_class.sanitize_environment(env)

        expect(result).to include('ANTHROPIC_API_KEY' => 'sk-ant-...')
      end

      it 'allows NODE_ENV' do
        env = { 'NODE_ENV' => 'production' }
        result = described_class.sanitize_environment(env)

        expect(result).to include('NODE_ENV' => 'production')
      end
    end

    context 'with forbidden variables' do
      it 'removes LD_PRELOAD' do
        env = { 'LD_PRELOAD' => '/tmp/evil.so', 'MCP_API_KEY' => 'secret' }
        result = described_class.sanitize_environment(env)

        expect(result).not_to include('LD_PRELOAD')
        expect(result).to include('MCP_API_KEY' => 'secret')
      end

      it 'removes PATH and HOME (server env is never the source of truth for either)' do
        env = { 'PATH' => '/tmp/evil-bin', 'HOME' => '/tmp/evil-home' }
        result = described_class.sanitize_environment(env)

        expect(result).not_to include('PATH', 'HOME')
      end

      it 'removes LD_LIBRARY_PATH' do
        env = { 'LD_LIBRARY_PATH' => '/tmp/libs' }
        result = described_class.sanitize_environment(env)

        expect(result).not_to include('LD_LIBRARY_PATH')
      end

      it 'removes DYLD_INSERT_LIBRARIES (macOS)' do
        env = { 'DYLD_INSERT_LIBRARIES' => '/tmp/evil.dylib' }
        result = described_class.sanitize_environment(env)

        expect(result).not_to include('DYLD_INSERT_LIBRARIES')
      end

      it 'removes NODE_OPTIONS' do
        env = { 'NODE_OPTIONS' => '--require=/tmp/evil.js' }
        result = described_class.sanitize_environment(env)

        expect(result).not_to include('NODE_OPTIONS')
      end

      it 'removes BASH_ENV' do
        env = { 'BASH_ENV' => '/tmp/evil.sh' }
        result = described_class.sanitize_environment(env)

        expect(result).not_to include('BASH_ENV')
      end
    end

    context 'with strict mode' do
      it 'only allows explicitly allowed variables in strict mode' do
        env = {
          'USER' => 'mcp-runner',
          'CUSTOM_VAR' => 'value',
          'MCP_API_KEY' => 'secret'
        }
        result = described_class.sanitize_environment(env, strict: true)

        expect(result).to include('USER' => 'mcp-runner')
        expect(result).to include('MCP_API_KEY' => 'secret')
        expect(result).not_to include('CUSTOM_VAR')
      end

      it 'allows custom variables in non-strict mode' do
        env = { 'CUSTOM_VAR' => 'value' }
        result = described_class.sanitize_environment(env, strict: false)

        expect(result).to include('CUSTOM_VAR' => 'value')
      end
    end

    it 'handles blank environment' do
      expect(described_class.sanitize_environment(nil)).to eq({})
      expect(described_class.sanitize_environment({})).to eq({})
    end

    it 'converts symbol keys to strings' do
      env = { USER: 'mcp-runner' }
      result = described_class.sanitize_environment(env)

      expect(result).to include('USER' => 'mcp-runner')
    end
  end

  describe '.env_allowed?' do
    it 'returns true for allowed variables' do
      expect(described_class.env_allowed?('USER')).to be true
      expect(described_class.env_allowed?('MCP_API_KEY')).to be true
    end

    it 'returns false for forbidden variables' do
      expect(described_class.env_allowed?('LD_PRELOAD')).to be false
      expect(described_class.env_allowed?('NODE_OPTIONS')).to be false
      expect(described_class.env_allowed?('PATH')).to be false
      expect(described_class.env_allowed?('HOME')).to be false
    end

    it 'is case insensitive' do
      expect(described_class.env_allowed?('user')).to be true
      expect(described_class.env_allowed?('ld_preload')).to be false
    end

    it 'respects strict mode' do
      expect(described_class.env_allowed?('CUSTOM_VAR', strict: false)).to be true
      expect(described_class.env_allowed?('CUSTOM_VAR', strict: true)).to be false
    end
  end

  describe '.validate_environment!' do
    it 'does not raise for allowed variables' do
      env = { 'USER' => 'mcp-runner', 'MCP_API_KEY' => 'secret' }

      expect { described_class.validate_environment!(env) }.not_to raise_error
    end

    it 'raises for a server-supplied PATH or HOME' do
      expect { described_class.validate_environment!({ 'PATH' => '/tmp/evil-bin' }) }
        .to raise_error(Mcp::SecurityService::EnvironmentViolationError, /PATH/)
      expect { described_class.validate_environment!({ 'HOME' => '/tmp/evil-home' }) }
        .to raise_error(Mcp::SecurityService::EnvironmentViolationError, /HOME/)
    end

    it 'raises for forbidden variables' do
      env = { 'LD_PRELOAD' => '/tmp/evil.so' }

      expect { described_class.validate_environment!(env) }
        .to raise_error(Mcp::SecurityService::EnvironmentViolationError, /Forbidden environment variables/)
    end

    it 'lists all forbidden variables in error' do
      env = { 'LD_PRELOAD' => 'x', 'NODE_OPTIONS' => 'y' }

      expect { described_class.validate_environment!(env) }
        .to raise_error(Mcp::SecurityService::EnvironmentViolationError, /LD_PRELOAD.*NODE_OPTIONS|NODE_OPTIONS.*LD_PRELOAD/)
    end

    it 'handles blank environment' do
      expect { described_class.validate_environment!(nil) }.not_to raise_error
      expect { described_class.validate_environment!({}) }.not_to raise_error
    end
  end

  # IMP-176a386fef98: `validate_stdio_execution!` (command:/env: keyword API,
  # returning {command:, env:}) is REMOVED — ported from the worker, which
  # made the identical decision for the identical reason (IMP-97b6b1185748
  # item 9): `command grep`-ing server/app for callers besides
  # Mcp::SyncExecutionService (already migrated to #validate_stdio_server!
  # as part of this task) and this spec found none. Every real stdio spawn
  # site now goes through #validate_stdio_server!, which takes the `server`
  # hash directly and returns the additional resolved `argv`.
  describe '.validate_stdio_server!' do
    it 'returns [command, string-keyed env, argv] for a whitelisted command' do
      command, env, argv = described_class.validate_stdio_server!(
        'command' => 'npx', 'args' => ['@modelcontextprotocol/server-filesystem'],
        'env' => { 'MCP_API_KEY' => 'secret' }
      )

      expect(command).to eq('npx')
      expect(argv).to eq(['@modelcontextprotocol/server-filesystem'])
      expect(env).to include('MCP_API_KEY' => 'secret', 'PATH' => ENV['PATH'])
    end

    it 'raises CommandNotAllowedError for blocked commands, before ever building an env' do
      expect { described_class.validate_stdio_server!('command' => 'bash', 'args' => ['-c', 'evil']) }
        .to raise_error(Mcp::SecurityService::CommandNotAllowedError)
    end

    it 'raises EnvironmentViolationError for forbidden env vars' do
      expect { described_class.validate_stdio_server!('command' => 'node', 'env' => { 'LD_PRELOAD' => '/tmp/evil.so' }) }
        .to raise_error(Mcp::SecurityService::EnvironmentViolationError)
    end

    it 'raises for a node -e inline-code argument (args are validated too, not just the command)' do
      expect { described_class.validate_stdio_server!('command' => 'node', 'args' => ['-e', 'evil']) }
        .to raise_error(Mcp::SecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
    end

    it 'respects allow_extended_commands via capabilities' do
      expect do
        described_class.validate_stdio_server!(
          'command' => 'uvx', 'args' => ['mcp-server-git'], 'capabilities' => { 'allow_extended_commands' => true }
        )
      end.not_to raise_error
    end

    it 'respects strict_environment via capabilities' do
      _command, env, = described_class.validate_stdio_server!(
        'command' => 'node', 'env' => { 'CUSTOM_VAR' => 'value' }, 'capabilities' => { 'strict_environment' => true }
      )

      expect(env).not_to include('CUSTOM_VAR')
    end

    # IMP-176a386fef98 BLOCKER: this used to spawn @server.command as a
    # bare STRING with `*Array(@server.args)` — Process.spawn/Open3 runs a
    # lone command STRING through `/bin/sh -c` when given no additional
    # args, so `args: []` would have let the command string alone execute
    # arbitrary shell syntax even though the command itself passed the
    # whitelist.
    it 'refuses shell metacharacters in an arg (defense the old bare-string spawn had none of)' do
      expect { described_class.validate_stdio_server!('command' => 'node', 'args' => ['s.js; rm -rf /']) }
        .to raise_error(Mcp::SecurityService::CommandNotAllowedError, /forbidden shell metacharacter/)
    end
  end

  describe '.spawn_stdio' do
    it 'always passes unsetenv_others: true' do
      success_status = instance_double(Process::Status, success?: true)
      expect(Open3).to receive(:capture3) do |_env, command, *_args, **opts|
        expect(command).to eq(['node', 'node'])
        expect(opts[:unsetenv_others]).to be true
        ['{}', '', success_status]
      end

      described_class.spawn_stdio('node', { 'PATH' => ENV['PATH'] }, ['s.js'], stdin_data: '')
    end

    # IMP-176a386fef98 BLOCKER, real-child-spawn proof (mirrors the
    # worker's IMP-e2cba83ee39f spec): a real, unstubbed child process is
    # spawned through the actual Rails process's ENV, with a sentinel
    # standing in for a real Rails secret — proving unsetenv_others: true
    # actually keeps the whole Rails process environment (DATABASE_URL,
    # secret_key_base, ...) out of the child, not just that the Hash this
    # class BUILDS looks clean.
    it 'spawns a real child whose observed env excludes Rails process secrets, sentinel absent' do
      original = ENV.to_hash
      ENV['MCP_RAILS_SECRET_SENTINEL'] = 'do-not-leak-me'

      begin
        require 'tempfile'
        script = Tempfile.new(['mcp_env_probe', '.rb'])
        begin
          script.write('puts ENV.keys.sort.join(",")')
          script.close

          command, env, args = described_class.validate_stdio_server!(
            'command' => 'ruby', 'args' => [script.path], 'env' => { 'MCP_API_KEY' => 'secret' }
          )
          stdout, stderr, status = described_class.spawn_stdio(command, env, args, stdin_data: '')

          expect(status).to be_success, "ruby child failed: #{stderr}"
          child_keys = stdout.strip.split(',')

          expect(child_keys).not_to include('MCP_RAILS_SECRET_SENTINEL')
          expect(child_keys.sort).to eq(env.keys.sort)
        ensure
          script.unlink
        end
      ensure
        ENV.replace(original)
      end
    end
  end

  describe 'error classes' do
    it 'defines SecurityError as base class' do
      expect(Mcp::SecurityService::SecurityError).to be < StandardError
    end

    it 'defines CommandNotAllowedError' do
      expect(Mcp::SecurityService::CommandNotAllowedError).to be < Mcp::SecurityService::SecurityError
    end

    it 'defines EnvironmentViolationError' do
      expect(Mcp::SecurityService::EnvironmentViolationError).to be < Mcp::SecurityService::SecurityError
    end
  end
end
