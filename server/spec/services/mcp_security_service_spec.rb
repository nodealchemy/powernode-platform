# frozen_string_literal: true

require 'rails_helper'

RSpec.describe McpSecurityService do
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

      it 'allows /usr/bin/env with allowed command' do
        expect { described_class.validate_command!('/usr/bin/env node server.js') }
          .not_to raise_error
      end

      it 'allows blank commands without error' do
        expect { described_class.validate_command!('') }.not_to raise_error
        expect { described_class.validate_command!(nil) }.not_to raise_error
      end
    end

    context 'with extended commands' do
      it 'blocks uvx by default' do
        expect { described_class.validate_command!('uvx mcp-server-git') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /not in the allowed list/)
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
          .to raise_error(McpSecurityService::CommandNotAllowedError)
      end

      it 'blocks sh' do
        expect { described_class.validate_command!('sh script.sh') }
          .to raise_error(McpSecurityService::CommandNotAllowedError)
      end

      it 'blocks curl' do
        expect { described_class.validate_command!('curl https://evil.com') }
          .to raise_error(McpSecurityService::CommandNotAllowedError)
      end

      it 'blocks wget' do
        expect { described_class.validate_command!('wget https://evil.com') }
          .to raise_error(McpSecurityService::CommandNotAllowedError)
      end

      it 'blocks arbitrary executables' do
        expect { described_class.validate_command!('/tmp/malware') }
          .to raise_error(McpSecurityService::CommandNotAllowedError)
      end
    end

    context 'with dangerous argument patterns' do
      it 'blocks semicolon command chaining' do
        expect { described_class.validate_command!('node server.js; rm -rf /') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /dangerous pattern/)
      end

      it 'blocks pipe command chaining' do
        expect { described_class.validate_command!('node server.js | bash') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /dangerous pattern/)
      end

      it 'blocks ampersand command chaining' do
        expect { described_class.validate_command!('node server.js && rm -rf /') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /dangerous pattern/)
      end

      it 'blocks backtick command substitution' do
        expect { described_class.validate_command!('node `whoami`') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /dangerous pattern/)
      end

      it 'blocks $() command substitution' do
        expect { described_class.validate_command!('node $(cat /etc/passwd)') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /dangerous pattern/)
      end

      it 'blocks ${} variable expansion' do
        expect { described_class.validate_command!('node ${PATH}') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /dangerous pattern/)
      end

      it 'blocks output redirection' do
        expect { described_class.validate_command!('node server.js > /etc/passwd') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /dangerous pattern/)
      end

      it 'blocks eval' do
        expect { described_class.validate_command!('node -e "eval(process.argv[1])"') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /dangerous pattern/)
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
      it 'allows PATH' do
        env = { 'PATH' => '/usr/bin:/usr/local/bin' }
        result = described_class.sanitize_environment(env)

        expect(result).to include('PATH' => '/usr/bin:/usr/local/bin')
      end

      it 'allows HOME' do
        env = { 'HOME' => '/home/user' }
        result = described_class.sanitize_environment(env)

        expect(result).to include('HOME' => '/home/user')
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
        env = { 'LD_PRELOAD' => '/tmp/evil.so', 'PATH' => '/usr/bin' }
        result = described_class.sanitize_environment(env)

        expect(result).not_to include('LD_PRELOAD')
        expect(result).to include('PATH' => '/usr/bin')
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
          'PATH' => '/usr/bin',
          'CUSTOM_VAR' => 'value',
          'MCP_API_KEY' => 'secret'
        }
        result = described_class.sanitize_environment(env, strict: true)

        expect(result).to include('PATH' => '/usr/bin')
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
      env = { PATH: '/usr/bin' }
      result = described_class.sanitize_environment(env)

      expect(result).to include('PATH' => '/usr/bin')
    end
  end

  describe '.env_allowed?' do
    it 'returns true for allowed variables' do
      expect(described_class.env_allowed?('PATH')).to be true
      expect(described_class.env_allowed?('HOME')).to be true
      expect(described_class.env_allowed?('MCP_API_KEY')).to be true
    end

    it 'returns false for forbidden variables' do
      expect(described_class.env_allowed?('LD_PRELOAD')).to be false
      expect(described_class.env_allowed?('NODE_OPTIONS')).to be false
    end

    it 'is case insensitive' do
      expect(described_class.env_allowed?('path')).to be true
      expect(described_class.env_allowed?('ld_preload')).to be false
    end

    it 'respects strict mode' do
      expect(described_class.env_allowed?('CUSTOM_VAR', strict: false)).to be true
      expect(described_class.env_allowed?('CUSTOM_VAR', strict: true)).to be false
    end
  end

  describe '.validate_environment!' do
    it 'does not raise for allowed variables' do
      env = { 'PATH' => '/usr/bin', 'MCP_API_KEY' => 'secret' }

      expect { described_class.validate_environment!(env) }.not_to raise_error
    end

    it 'raises for forbidden variables' do
      env = { 'LD_PRELOAD' => '/tmp/evil.so' }

      expect { described_class.validate_environment!(env) }
        .to raise_error(McpSecurityService::EnvironmentViolationError, /Forbidden environment variables/)
    end

    it 'lists all forbidden variables in error' do
      env = { 'LD_PRELOAD' => 'x', 'NODE_OPTIONS' => 'y' }

      expect { described_class.validate_environment!(env) }
        .to raise_error(McpSecurityService::EnvironmentViolationError, /LD_PRELOAD.*NODE_OPTIONS|NODE_OPTIONS.*LD_PRELOAD/)
    end

    it 'handles blank environment' do
      expect { described_class.validate_environment!(nil) }.not_to raise_error
      expect { described_class.validate_environment!({}) }.not_to raise_error
    end
  end

  describe '.validate_stdio_execution!' do
    it 'returns validated command and sanitized environment' do
      result = described_class.validate_stdio_execution!(
        command: 'npx @modelcontextprotocol/server-filesystem',
        env: { 'PATH' => '/usr/bin', 'MCP_API_KEY' => 'secret' }
      )

      expect(result[:command]).to eq('npx @modelcontextprotocol/server-filesystem')
      expect(result[:env]).to include('PATH' => '/usr/bin')
      expect(result[:env]).to include('MCP_API_KEY' => 'secret')
    end

    it 'sanitizes env vars while raising for forbidden ones (validates before sanitizing)' do
      # validate_stdio_execution! validates first, then sanitizes
      # Forbidden vars trigger validation error before sanitization
      expect do
        described_class.validate_stdio_execution!(
          command: 'node server.js',
          env: { 'PATH' => '/usr/bin', 'LD_PRELOAD' => '/tmp/evil.so' }
        )
      end.to raise_error(McpSecurityService::EnvironmentViolationError)
    end

    it 'returns sanitized env without unknown vars' do
      result = described_class.validate_stdio_execution!(
        command: 'node server.js',
        env: { 'PATH' => '/usr/bin', 'CUSTOM_VAR' => 'value', 'MCP_KEY' => 'test' },
        strict_env: true
      )

      expect(result[:env]).to include('PATH')
      expect(result[:env]).to include('MCP_KEY')
      expect(result[:env]).not_to include('CUSTOM_VAR')
    end

    it 'raises CommandNotAllowedError for blocked commands' do
      expect do
        described_class.validate_stdio_execution!(
          command: 'bash -c "evil"',
          env: {}
        )
      end.to raise_error(McpSecurityService::CommandNotAllowedError)
    end

    it 'raises EnvironmentViolationError for forbidden env vars' do
      expect do
        described_class.validate_stdio_execution!(
          command: 'node server.js',
          env: { 'LD_PRELOAD' => '/tmp/evil.so' }
        )
      end.to raise_error(McpSecurityService::EnvironmentViolationError)
    end

    it 'respects allow_extended flag' do
      result = described_class.validate_stdio_execution!(
        command: 'uvx mcp-server-git',
        env: {},
        allow_extended: true
      )

      expect(result[:command]).to eq('uvx mcp-server-git')
    end

    it 'respects strict_env flag' do
      result = described_class.validate_stdio_execution!(
        command: 'node server.js',
        env: { 'PATH' => '/usr/bin', 'CUSTOM' => 'value' },
        strict_env: true
      )

      expect(result[:env]).to include('PATH')
      expect(result[:env]).not_to include('CUSTOM')
    end
  end

  describe 'error classes' do
    it 'defines SecurityError as base class' do
      expect(McpSecurityService::SecurityError).to be < StandardError
    end

    it 'defines CommandNotAllowedError' do
      expect(McpSecurityService::CommandNotAllowedError).to be < McpSecurityService::SecurityError
    end

    it 'defines EnvironmentViolationError' do
      expect(McpSecurityService::EnvironmentViolationError).to be < McpSecurityService::SecurityError
    end
  end
end
