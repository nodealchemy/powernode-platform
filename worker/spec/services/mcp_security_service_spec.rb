# frozen_string_literal: true

require 'rails_helper'
require_relative '../../app/services/mcp_security_service'

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
          .to raise_error(McpSecurityService::CommandNotAllowedError)
      end

      it 'allows uvx with allow_extended flag' do
        expect { described_class.validate_command!('uvx mcp-server-git', allow_extended: true) }
          .not_to raise_error
      end

      it 'allows docker with allow_extended flag' do
        expect { described_class.validate_command!('docker run mcp-server', allow_extended: true) }
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

      it 'blocks backtick command substitution' do
        expect { described_class.validate_command!('node `whoami`') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /dangerous pattern/)
      end

      it 'blocks $() command substitution' do
        expect { described_class.validate_command!('node $(cat /etc/passwd)') }
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

      it 'allows MCP_ prefixed variables' do
        env = { 'MCP_SERVER_URL' => 'https://api.example.com', 'MCP_API_KEY' => 'secret' }
        result = described_class.sanitize_environment(env)

        expect(result).to include('MCP_SERVER_URL', 'MCP_API_KEY')
      end

      it 'allows OPENAI_ prefixed variables' do
        env = { 'OPENAI_API_KEY' => 'sk-...' }
        result = described_class.sanitize_environment(env)

        expect(result).to include('OPENAI_API_KEY')
      end

      it 'allows ANTHROPIC_ prefixed variables' do
        env = { 'ANTHROPIC_API_KEY' => 'sk-ant-...' }
        result = described_class.sanitize_environment(env)

        expect(result).to include('ANTHROPIC_API_KEY')
      end
    end

    context 'with forbidden variables' do
      it 'removes LD_PRELOAD' do
        env = { 'LD_PRELOAD' => '/tmp/evil.so', 'PATH' => '/usr/bin' }
        result = described_class.sanitize_environment(env)

        expect(result).not_to include('LD_PRELOAD')
        expect(result).to include('PATH')
      end

      it 'removes LD_LIBRARY_PATH' do
        env = { 'LD_LIBRARY_PATH' => '/tmp/libs' }
        result = described_class.sanitize_environment(env)

        expect(result).not_to include('LD_LIBRARY_PATH')
      end

      it 'removes NODE_OPTIONS' do
        env = { 'NODE_OPTIONS' => '--require=/tmp/evil.js' }
        result = described_class.sanitize_environment(env)

        expect(result).not_to include('NODE_OPTIONS')
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

        expect(result).to include('PATH', 'MCP_API_KEY')
        expect(result).not_to include('CUSTOM_VAR')
      end
    end

    it 'handles blank environment' do
      expect(described_class.sanitize_environment(nil)).to eq({})
      expect(described_class.sanitize_environment({})).to eq({})
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
        .to raise_error(McpSecurityService::EnvironmentViolationError)
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
      expect(result[:env]).to include('PATH', 'MCP_API_KEY')
    end

    it 'raises for forbidden env vars (validates before sanitizing)' do
      expect do
        described_class.validate_stdio_execution!(
          command: 'node server.js',
          env: { 'PATH' => '/usr/bin', 'LD_PRELOAD' => '/tmp/evil.so' }
        )
      end.to raise_error(McpSecurityService::EnvironmentViolationError)
    end

    it 'returns sanitized env without unknown vars in strict mode' do
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

  describe 'ALLOWED_COMMANDS constant' do
    it 'includes common MCP commands' do
      expect(McpSecurityService::ALLOWED_COMMANDS).to include('npx', 'node', 'python', 'python3', 'ruby')
    end
  end

  describe 'EXTENDED_COMMANDS constant' do
    it 'includes container and tool commands' do
      expect(McpSecurityService::EXTENDED_COMMANDS).to include('uvx', 'docker', 'podman')
    end
  end

  describe 'FORBIDDEN_ENV_VARS constant' do
    it 'includes security-sensitive variables' do
      expect(McpSecurityService::FORBIDDEN_ENV_VARS).to include(
        'LD_PRELOAD', 'LD_LIBRARY_PATH', 'DYLD_INSERT_LIBRARIES', 'NODE_OPTIONS'
      )
    end
  end
end
