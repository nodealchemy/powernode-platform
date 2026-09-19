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

      it 'refuses /usr/bin/env entirely (IMP-97b6b1185748 item 2 — the env wrapper is never unwrapped)' do
        # Previously unwrapped to find "node" and allowed it. DECISION: env
        # is refused as the command outright, whether alone or combined
        # with the real interpreter in the same string — the worker
        # already sanitizes server['env'] before spawning, so the wrapper
        # adds nothing legitimate.
        expect { described_class.validate_command!('/usr/bin/env node server.js') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /'env' wrapper is not allowed/)
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

  # IMP-b6be9d979e13 BLOCKER: the whitelist used to match on File.basename
  # or a trailing "/#{name}" — "/tmp/evil/node" and "./node" both passed as
  # "node". A command is now allowed ONLY as a bare whitelisted name
  # (resolved through the worker's own PATH at spawn — the server can't
  # override PATH, see FORBIDDEN_ENV_VARS) or an EXACT match against
  # ALLOWED_ABSOLUTE_COMMAND_DIRS joined with a whitelisted name. Exercised
  # via .validate_command! (raises) and .command_allowed? (bool) — both
  # delegate to the same #base_command_in_allowed_list? this targets.
  describe 'command whitelist exact-path matching (IMP-b6be9d979e13)' do
    context 'refused — never reaches Open3.capture3' do
      it 'refuses an arbitrary directory whose basename happens to match a whitelisted name' do
        expect(Open3).not_to receive(:capture3)
        expect { described_class.validate_command!('/tmp/evil/node server.js') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /not in the allowed list/)
        expect(described_class.command_allowed?('/tmp/evil/node')).to be false
      end

      it 'refuses a same-directory relative path (./node)' do
        expect(Open3).not_to receive(:capture3)
        expect { described_class.validate_command!('./node server.js') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /not in the allowed list/)
        expect(described_class.command_allowed?('./node')).to be false
      end

      it 'refuses a parent-relative path (../x/node)' do
        expect(Open3).not_to receive(:capture3)
        expect { described_class.validate_command!('../x/node server.js') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /not in the allowed list/)
        expect(described_class.command_allowed?('../x/node')).to be false
      end

      it 'refuses a bare relative path with no leading dot (bin/node)' do
        expect(Open3).not_to receive(:capture3)
        expect { described_class.validate_command!('bin/node server.js') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /not in the allowed list/)
        expect(described_class.command_allowed?('bin/node')).to be false
      end

      it 'refuses an absolute path in a directory outside ALLOWED_ABSOLUTE_COMMAND_DIRS (/opt/x/python3)' do
        expect(Open3).not_to receive(:capture3)
        expect { described_class.validate_command!('/opt/x/python3 server.py') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /not in the allowed list/)
        expect(described_class.command_allowed?('/opt/x/python3')).to be false
      end

      it 'refuses a whitelisted absolute path with trailing whitespace ("/usr/bin/node ")' do
        # Quoted so Shellwords preserves the trailing space as part of the
        # FIRST token instead of trimming it as ordinary whitespace between
        # words — an unquoted trailing space in the raw command string is
        # never actually part of the resolved base_command token at all.
        expect(Open3).not_to receive(:capture3)
        expect { described_class.validate_command!('"/usr/bin/node " server.js') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /not in the allowed list/)
        expect(described_class.command_allowed?('"/usr/bin/node "')).to be false
      end

      it 'refuses a directory-traversal path that would normalize to a whitelisted one (/usr/bin/../../tmp/node)' do
        expect(Open3).not_to receive(:capture3)
        expect { described_class.validate_command!('/usr/bin/../../tmp/node server.js') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /not in the allowed list/)
        expect(described_class.command_allowed?('/usr/bin/../../tmp/node')).to be false
      end

      it 'refuses /usr/bin/docker unless allow_extended is set' do
        expect(Open3).not_to receive(:capture3)
        expect { described_class.validate_command!('/usr/bin/docker run mcp-server') }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /not in the allowed list/)
        expect(described_class.command_allowed?('/usr/bin/docker')).to be false
      end
    end

    context 'allowed' do
      it 'allows a bare whitelisted name' do
        expect { described_class.validate_command!('node server.js') }.not_to raise_error
        expect(described_class.command_allowed?('node')).to be true
      end

      it 'allows an exact /usr/bin match' do
        expect { described_class.validate_command!('/usr/bin/node server.js') }.not_to raise_error
        expect(described_class.command_allowed?('/usr/bin/node')).to be true
      end

      it 'allows an exact /usr/local/bin match' do
        expect { described_class.validate_command!('/usr/local/bin/python3 server.py') }.not_to raise_error
        expect(described_class.command_allowed?('/usr/local/bin/python3')).to be true
      end

      it 'allows an exact /bin match' do
        expect { described_class.validate_command!('/bin/ruby mcp_server.rb') }.not_to raise_error
        expect(described_class.command_allowed?('/bin/ruby')).to be true
      end

      it 'allows /usr/bin/docker when allow_extended is set' do
        expect { described_class.validate_command!('/usr/bin/docker run mcp-server', allow_extended: true) }
          .not_to raise_error
        expect(described_class.command_allowed?('/usr/bin/docker', allow_extended: true)).to be true
      end
    end
  end

  describe '.sanitize_environment' do
    context 'with allowed variables' do
      it 'allows USER' do
        env = { 'USER' => 'mcp-runner' }
        result = described_class.sanitize_environment(env)

        expect(result).to include('USER' => 'mcp-runner')
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
        env = { 'LD_PRELOAD' => '/tmp/evil.so', 'MCP_API_KEY' => 'secret' }
        result = described_class.sanitize_environment(env)

        expect(result).not_to include('LD_PRELOAD')
        expect(result).to include('MCP_API_KEY')
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

      # IMP-e2cba83ee39f: PATH/HOME are FORBIDDEN in server-supplied env —
      # a server-supplied PATH could point a bare command name like
      # "node" at an attacker binary resolved through it; a server env is
      # never the source of truth for either, see
      # McpSecurityService.build_stdio_env's worker-side passthrough.
      it 'removes PATH and HOME' do
        env = { 'PATH' => '/tmp/evil-bin', 'HOME' => '/tmp/evil-home', 'MCP_API_KEY' => 'secret' }
        result = described_class.sanitize_environment(env)

        expect(result).not_to include('PATH', 'HOME')
        expect(result).to include('MCP_API_KEY')
      end

      # IMP-e2cba83ee39f: module/gem search-path and interpreter
      # auto-load-on-start vectors.
      it 'removes the interpreter module/gem search-path and auto-load vectors' do
        env = {
          'NODE_PATH' => '/tmp/evil', 'RUBYLIB' => '/tmp/evil', 'PYTHONPATH' => '/tmp/evil',
          'PYTHON_PATH' => '/tmp/evil', 'PYTHONHOME' => '/tmp/evil', 'PYTHONINSPECT' => '1',
          'GEM_HOME' => '/tmp/evil', 'GEM_PATH' => '/tmp/evil', 'BUN_OPTIONS' => '--evil',
          'PERL5OPT' => '-Mevil', 'PERL5LIB' => '/tmp/evil', 'JAVA_TOOL_OPTIONS' => '-evil',
          '_JAVA_OPTIONS' => '-evil', 'JDK_JAVA_OPTIONS' => '-evil', 'DOTNET_STARTUP_HOOKS' => '/tmp/evil.dll'
        }
        result = described_class.sanitize_environment(env)

        expect(result).to be_empty
      end

      it 'removes the whole DYLD_* family, not just the two explicitly-named ones' do
        env = { 'DYLD_INSERT_LIBRARIES' => '/tmp/evil.dylib', 'DYLD_FRAMEWORK_PATH' => '/tmp/evil' }
        result = described_class.sanitize_environment(env)

        expect(result).to be_empty
      end

      # IMP-e2cba83ee39f round 2 BLOCKER: LD_AUDIT/LD_PROFILE were still
      # ALLOWED in non-strict mode despite loading an arbitrary shared
      # object into the process, the same class as LD_PRELOAD (already
      # forbidden by exact name above) — this mirrors the DYLD_* prefix
      # coverage for glibc's dynamic linker.
      it 'removes the whole LD_* family, not just LD_PRELOAD/LD_LIBRARY_PATH' do
        env = { 'LD_AUDIT' => '/tmp/evil.so', 'LD_PROFILE' => 'evil', 'LD_BIND_NOW' => '1' }
        result = described_class.sanitize_environment(env)

        expect(result).to be_empty
      end

      it 'removes the glibc locale/NSS lookup-path and DNS-redirection vars' do
        env = {
          'GCONV_PATH' => '/tmp/evil', 'GLIBC_TUNABLES' => 'evil', 'LOCPATH' => '/tmp/evil',
          'NLSPATH' => '/tmp/evil', 'HOSTALIASES' => '/tmp/evil-hosts', 'RESOLV_HOST_CONF' => '/tmp/evil-resolv'
        }
        result = described_class.sanitize_environment(env)

        expect(result).to be_empty
      end

      it "removes the package manager's registry/index-redirection prefixes and uv's named source vars" do
        env = {
          'NPM_CONFIG_REGISTRY' => 'https://evil.example/npm',
          'npm_config_registry' => 'https://evil.example/npm-lowercase',
          'PIP_INDEX_URL' => 'https://evil.example/pypi',
          'PIP_EXTRA_INDEX_URL' => 'https://evil.example/pypi2',
          'PIP_FIND_LINKS' => 'https://evil.example/links',
          'BUN_CONFIG_REGISTRY' => 'https://evil.example/bun',
          'UV_INDEX_URL' => 'https://evil.example/pypi',
          'UV_EXTRA_INDEX_URL' => 'https://evil.example/pypi2',
          'UV_INDEX' => 'https://evil.example/pypi3',
          'UV_DEFAULT_INDEX' => 'https://evil.example/pypi4',
          'UV_FIND_LINKS' => 'https://evil.example/links',
          'UV_PYTHON_INSTALL_MIRROR' => 'https://evil.example/python',
          'UV_PYPY_INSTALL_MIRROR' => 'https://evil.example/pypy'
        }
        result = described_class.sanitize_environment(env)

        expect(result).to be_empty
      end

      it 'removes PYTHONUSERBASE (auto-imports usercustomize.py on interpreter start)' do
        env = { 'PYTHONUSERBASE' => '/tmp/evil-userbase' }
        result = described_class.sanitize_environment(env)

        expect(result).to be_empty
      end

      it "removes ruby's gem/bundler-redirection vars, including the now-former ALLOWED_ENV_VARS entry BUNDLE_PATH" do
        env = {
          'BUNDLE_GEMFILE' => '/tmp/evil/Gemfile', 'RUBYGEMS_GEMDEPS' => '/tmp/evil/gem.deps.rb',
          'BUNDLE_PATH' => '/tmp/evil-gems'
        }
        result = described_class.sanitize_environment(env)

        expect(result).to be_empty
      end

      it 'removes the extended-launcher (java/docker/go) vars' do
        env = {
          'CLASSPATH' => '/tmp/evil.jar', 'DOCKER_HOST' => 'tcp://evil.example:2375',
          'DOCKER_CONFIG' => '/tmp/evil-docker-config', 'GOPROXY' => 'https://evil.example',
          'GOFLAGS' => '-evil', 'GONOSUMDB' => '*', 'GONOSUMCHECK' => '1', 'GOSUMDB' => 'off',
          'GOINSECURE' => '*', 'GOPRIVATE' => '*'
        }
        result = described_class.sanitize_environment(env)

        expect(result).to be_empty
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

        expect(result).to include('USER', 'MCP_API_KEY')
        expect(result).not_to include('CUSTOM_VAR')
      end

      it 'still removes PATH/HOME in strict mode, even though PATH/HOME were once ALLOWED_ENV_VARS' do
        env = { 'PATH' => '/tmp/evil-bin', 'HOME' => '/tmp/evil-home' }
        result = described_class.sanitize_environment(env, strict: true)

        expect(result).to be_empty
      end

      it 'still removes the LD_* family, the glibc/DNS vars, and the package-source prefixes/vars in strict mode' do
        env = {
          'LD_AUDIT' => '/tmp/evil.so', 'GCONV_PATH' => '/tmp/evil', 'HOSTALIASES' => '/tmp/evil-hosts',
          'NPM_CONFIG_REGISTRY' => 'https://evil.example', 'PIP_INDEX_URL' => 'https://evil.example',
          'BUN_CONFIG_REGISTRY' => 'https://evil.example', 'UV_INDEX_URL' => 'https://evil.example'
        }
        result = described_class.sanitize_environment(env, strict: true)

        expect(result).to be_empty
      end

      # BUNDLE_PATH was ALLOWED in strict mode before round 3 (it was in
      # ALLOWED_ENV_VARS, so strict mode's default-deny didn't apply to
      # it) — this is the one round-3 addition where strict mode's
      # behavior actually CHANGES, unlike the other round-2/3 additions
      # where strict mode's default-deny already blocked them regardless.
      it 'removes BUNDLE_PATH in strict mode too, now that it is no longer in ALLOWED_ENV_VARS' do
        env = { 'BUNDLE_PATH' => '/tmp/evil-gems' }
        result = described_class.sanitize_environment(env, strict: true)

        expect(result).to be_empty
      end

      it 'still removes PYTHONUSERBASE, the ruby gem/bundler vars, and the java/docker/go vars in strict mode' do
        env = {
          'PYTHONUSERBASE' => '/tmp/evil', 'BUNDLE_GEMFILE' => '/tmp/evil/Gemfile',
          'RUBYGEMS_GEMDEPS' => '/tmp/evil/gem.deps.rb', 'CLASSPATH' => '/tmp/evil.jar',
          'DOCKER_HOST' => 'tcp://evil.example:2375', 'GOPROXY' => 'https://evil.example'
        }
        result = described_class.sanitize_environment(env, strict: true)

        expect(result).to be_empty
      end
    end

    it 'handles blank environment' do
      expect(described_class.sanitize_environment(nil)).to eq({})
      expect(described_class.sanitize_environment({})).to eq({})
    end
  end

  describe '.validate_environment!' do
    it 'does not raise for allowed variables' do
      env = { 'USER' => 'mcp-runner', 'MCP_API_KEY' => 'secret' }

      expect { described_class.validate_environment!(env) }.not_to raise_error
    end

    it 'raises for forbidden variables' do
      env = { 'LD_PRELOAD' => '/tmp/evil.so' }

      expect { described_class.validate_environment!(env) }
        .to raise_error(McpSecurityService::EnvironmentViolationError)
    end

    # IMP-e2cba83ee39f: PATH/HOME are FORBIDDEN in server-supplied env —
    # a server config that tries to set either is rejected outright
    # rather than silently overridden, same as any other forbidden var.
    it 'raises for a server-supplied PATH or HOME' do
      expect { described_class.validate_environment!({ 'PATH' => '/tmp/evil-bin' }) }
        .to raise_error(McpSecurityService::EnvironmentViolationError, /PATH/)
      expect { described_class.validate_environment!({ 'HOME' => '/tmp/evil-home' }) }
        .to raise_error(McpSecurityService::EnvironmentViolationError, /HOME/)
    end

    it 'raises for the interpreter module/gem search-path and auto-load vectors' do
      %w[NODE_PATH RUBYLIB PYTHONPATH PYTHON_PATH PYTHONHOME PYTHONINSPECT GEM_HOME GEM_PATH
         BUN_OPTIONS PERL5OPT PERL5LIB JAVA_TOOL_OPTIONS _JAVA_OPTIONS JDK_JAVA_OPTIONS
         DOTNET_STARTUP_HOOKS].each do |key|
        expect { described_class.validate_environment!({ key => 'evil' }) }
          .to raise_error(McpSecurityService::EnvironmentViolationError, /#{Regexp.escape(key)}/),
              "expected #{key} to be forbidden"
      end
    end

    it 'raises for any DYLD_* variable, not just the two explicitly-named ones' do
      expect { described_class.validate_environment!({ 'DYLD_FRAMEWORK_PATH' => '/tmp/evil' }) }
        .to raise_error(McpSecurityService::EnvironmentViolationError, /DYLD_FRAMEWORK_PATH/)
    end

    it 'raises for any LD_* variable, not just LD_PRELOAD/LD_LIBRARY_PATH' do
      expect { described_class.validate_environment!({ 'LD_AUDIT' => '/tmp/evil.so' }) }
        .to raise_error(McpSecurityService::EnvironmentViolationError, /LD_AUDIT/)
      expect { described_class.validate_environment!({ 'LD_PROFILE' => 'evil' }) }
        .to raise_error(McpSecurityService::EnvironmentViolationError, /LD_PROFILE/)
      expect { described_class.validate_environment!({ 'LD_BIND_NOW' => '1' }) }
        .to raise_error(McpSecurityService::EnvironmentViolationError, /LD_BIND_NOW/)
    end

    it 'raises for the glibc locale/NSS lookup-path and DNS-redirection vars' do
      %w[GCONV_PATH GLIBC_TUNABLES LOCPATH NLSPATH HOSTALIASES RESOLV_HOST_CONF].each do |key|
        expect { described_class.validate_environment!({ key => 'evil' }) }
          .to raise_error(McpSecurityService::EnvironmentViolationError, /#{Regexp.escape(key)}/),
              "expected #{key} to be forbidden"
      end
    end

    it "raises for the package manager's registry/index-redirection prefixes" do
      expect { described_class.validate_environment!({ 'NPM_CONFIG_REGISTRY' => 'https://evil.example' }) }
        .to raise_error(McpSecurityService::EnvironmentViolationError, /NPM_CONFIG_REGISTRY/)
      expect { described_class.validate_environment!({ 'npm_config_registry' => 'https://evil.example' }) }
        .to raise_error(McpSecurityService::EnvironmentViolationError, /NPM_CONFIG_REGISTRY/)
      expect { described_class.validate_environment!({ 'PIP_INDEX_URL' => 'https://evil.example' }) }
        .to raise_error(McpSecurityService::EnvironmentViolationError, /PIP_INDEX_URL/)
      expect { described_class.validate_environment!({ 'PIP_EXTRA_INDEX_URL' => 'https://evil.example' }) }
        .to raise_error(McpSecurityService::EnvironmentViolationError, /PIP_EXTRA_INDEX_URL/)
      expect { described_class.validate_environment!({ 'PIP_FIND_LINKS' => 'https://evil.example' }) }
        .to raise_error(McpSecurityService::EnvironmentViolationError, /PIP_FIND_LINKS/)
      expect { described_class.validate_environment!({ 'BUN_CONFIG_REGISTRY' => 'https://evil.example' }) }
        .to raise_error(McpSecurityService::EnvironmentViolationError, /BUN_CONFIG_REGISTRY/)
    end

    it "raises for uv's named package-source vars (the UV_ prefix itself stays allowed)" do
      %w[UV_INDEX_URL UV_EXTRA_INDEX_URL UV_INDEX UV_DEFAULT_INDEX UV_FIND_LINKS
         UV_PYTHON_INSTALL_MIRROR UV_PYPY_INSTALL_MIRROR].each do |key|
        expect { described_class.validate_environment!({ key => 'https://evil.example' }) }
          .to raise_error(McpSecurityService::EnvironmentViolationError, /#{Regexp.escape(key)}/),
              "expected #{key} to be forbidden"
      end
    end

    it 'raises for PYTHONUSERBASE (auto-imports usercustomize.py on interpreter start)' do
      expect { described_class.validate_environment!({ 'PYTHONUSERBASE' => '/tmp/evil-userbase' }) }
        .to raise_error(McpSecurityService::EnvironmentViolationError, /PYTHONUSERBASE/)
    end

    it "raises for ruby's gem/bundler-redirection vars, including the now-former ALLOWED_ENV_VARS entry BUNDLE_PATH" do
      %w[BUNDLE_GEMFILE RUBYGEMS_GEMDEPS BUNDLE_PATH].each do |key|
        expect { described_class.validate_environment!({ key => '/tmp/evil' }) }
          .to raise_error(McpSecurityService::EnvironmentViolationError, /#{Regexp.escape(key)}/),
              "expected #{key} to be forbidden"
      end
    end

    it 'raises for the extended-launcher (java/docker/go) vars' do
      %w[CLASSPATH DOCKER_HOST DOCKER_CONFIG GOPROXY GOFLAGS GONOSUMDB GONOSUMCHECK GOSUMDB
         GOINSECURE GOPRIVATE].each do |key|
        expect { described_class.validate_environment!({ key => 'evil' }) }
          .to raise_error(McpSecurityService::EnvironmentViolationError, /#{Regexp.escape(key)}/),
              "expected #{key} to be forbidden"
      end
    end

    it 'handles blank environment' do
      expect { described_class.validate_environment!(nil) }.not_to raise_error
      expect { described_class.validate_environment!({}) }.not_to raise_error
    end
  end

  describe '.validate_stdio_server!' do
    # Shared entry point for every stdio call site (IMP-7046f6e448d6 review
    # item 2): McpServerConnectionJob, McpServerHealthCheckJob,
    # McpToolDiscoveryJob, Mcp::McpTransportClient. Takes the `server` hash
    # directly, string-keyed as BackendApiClient actually returns it.
    it 'returns [command, string-keyed env] for a whitelisted command' do
      server = { 'command' => 'node', 'args' => [], 'env' => { 'MCP_API_KEY' => 'secret' } }

      command, env = described_class.validate_stdio_server!(server)

      expect(command).to eq('node')
      # IMP-e2cba83ee39f: env is now the worker's own base passthrough
      # (PATH/HOME/LANG/LC_ALL/TZ/TMPDIR, whichever are set) merged with
      # the validated server env — never an exact match on the server env
      # alone (see the dedicated 'worker env passthrough' describe block
      # below for the full contract).
      expect(env).to include('MCP_API_KEY' => 'secret', 'PATH' => ENV['PATH'])
      expect(env.keys).to all(be_a(String))
    end

    it 'raises CommandNotAllowedError for a non-whitelisted command' do
      server = { 'command' => '/usr/bin/mcp-server', 'env' => {} }

      expect { described_class.validate_stdio_server!(server) }
        .to raise_error(McpSecurityService::CommandNotAllowedError)
    end

    it 'raises EnvironmentViolationError for a forbidden env var' do
      server = { 'command' => 'node', 'env' => { 'LD_PRELOAD' => '/tmp/evil.so' } }

      expect { described_class.validate_stdio_server!(server) }
        .to raise_error(McpSecurityService::EnvironmentViolationError)
    end

    it 'reads allow_extended/strict_env from server["capabilities"]' do
      server = {
        'command' => 'uvx',
        'env' => {},
        'capabilities' => { 'allow_extended_commands' => true }
      }

      command, = described_class.validate_stdio_server!(server)

      expect(command).to eq('uvx')
    end

    it 'refuses an extended command (docker) without capabilities.allow_extended_commands' do
      server = { 'command' => 'docker', 'env' => {} }

      expect { described_class.validate_stdio_server!(server) }
        .to raise_error(McpSecurityService::CommandNotAllowedError)
    end

    it 'allows an extended command (docker) when capabilities.allow_extended_commands == true' do
      server = {
        'command' => 'docker',
        'env' => {},
        'capabilities' => { 'allow_extended_commands' => true }
      }

      command, = described_class.validate_stdio_server!(server)

      expect(command).to eq('docker')
    end

    it 'drops non-allowlisted env keys and returns String env keys when capabilities.strict_environment == true' do
      server = {
        'command' => 'node',
        'env' => { 'USER' => 'mcp-runner', 'MCP_API_KEY' => 'secret', 'CUSTOM_UNLISTED_VAR' => 'value' },
        'capabilities' => { 'strict_environment' => true }
      }

      _command, env = described_class.validate_stdio_server!(server)

      expect(env).to include('USER', 'MCP_API_KEY', 'PATH')
      expect(env).not_to include('CUSTOM_UNLISTED_VAR')
      expect(env.keys).to all(be_a(String))
    end

    it 'works with an indifferent-access server too' do
      server = { 'command' => 'node', 'env' => {} }.with_indifferent_access

      command, env = described_class.validate_stdio_server!(server)

      expect(command).to eq('node')
      expect(env).to include('PATH' => ENV['PATH'])
    end

    it 'refuses inline code via args even though command and env are both fine (IMP-97b6b1185748)' do
      # This is the actual defect: validate_command! only ever looked at the
      # `command` string. `node` is whitelisted; args ["-e", "<code>"] used
      # to sail straight through untouched.
      server = { 'command' => 'node', 'args' => ['-e', 'require("child_process").exec("rm -rf /")'], 'env' => {} }

      expect { described_class.validate_stdio_server!(server) }
        .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
    end

    it 'returns [command, env, argv] as a 3-tuple, with argv as the fully resolved argument list' do
      server = { 'command' => 'node', 'args' => ['server.js', '--port', '3000'], 'env' => {} }

      command, env, argv = described_class.validate_stdio_server!(server)

      expect(command).to eq('node')
      expect(env).to include('PATH' => ENV['PATH'])
      expect(argv).to eq(['server.js', '--port', '3000'])
    end

    # IMP-97b6b1185748 item 1 BLOCKER — real bypass found by the reviewer:
    # with args left empty, flags hidden entirely inside the `command`
    # STRING reached the spawn unchecked, because Open3.capture3 given a
    # single string command (no additional args) runs it through `/bin/sh
    # -c`, and nothing in this class ever split that string to find them.
    it 'Shellwords-splits the command string and validates every token as an arg, not just server[\'args\']' do
      server = { 'command' => 'ruby -e p:ok', 'args' => [], 'env' => {} }

      expect { described_class.validate_stdio_server!(server) }
        .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
    end

    it 'returns argv with the command string\'s own tokens (after the first) folded in ahead of server[\'args\']' do
      server = { 'command' => 'node server.js', 'args' => ['--port', '3000'], 'env' => {} }

      command, _env, argv = described_class.validate_stdio_server!(server)

      expect(command).to eq('node')
      expect(argv).to eq(['server.js', '--port', '3000'])
    end

    # IMP-97b6b1185748 item 2 BLOCKER (DECISION): env / /usr/bin/env is
    # refused as the command entirely — never unwrapped to find "the real"
    # interpreter, in the command string OR via args[0].
    describe 'the env wrapper is always refused' do
      it 'refuses a bare "env" command' do
        expect { described_class.validate_stdio_server!({ 'command' => 'env', 'args' => [], 'env' => {} }) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /'env' wrapper is not allowed/)
      end

      it 'refuses "env -i node -e ..." (env -i clears the environment before running the real command)' do
        server = { 'command' => '/usr/bin/env', 'args' => ['-i', 'node', '-e', 'x'], 'env' => {} }

        expect { described_class.validate_stdio_server!(server) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /'env' wrapper is not allowed/)
      end

      it 'refuses "env -S \'node -e x\'" (env\'s own shell-like re-splitting of its argument)' do
        server = { 'command' => '/usr/bin/env', 'args' => ['-S', 'node -e x'], 'env' => {} }

        expect { described_class.validate_stdio_server!(server) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /'env' wrapper is not allowed/)
      end

      it 'refuses "env FOO=1 node -e ..." (env setting a var via argv before the real command)' do
        server = { 'command' => '/usr/bin/env', 'args' => ['FOO=1', 'node', '-e', 'x'], 'env' => {} }

        expect { described_class.validate_stdio_server!(server) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /'env' wrapper is not allowed/)
      end

      it 'refuses "env --" (the GNU env long-option terminator)' do
        server = { 'command' => 'env', 'args' => ['--', 'node', 'server.js'], 'env' => {} }

        expect { described_class.validate_stdio_server!(server) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /'env' wrapper is not allowed/)
      end

      it 'refuses env embedded in the command string too ("env -i node")' do
        server = { 'command' => 'env -i node', 'args' => ['-e', 'x'], 'env' => {} }

        expect { described_class.validate_stdio_server!(server) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /'env' wrapper is not allowed/)
      end
    end

    # IMP-97b6b1185748 item 7 BLOCKER — an unparseable command string is a
    # hard refusal, and the resolved base command is validated EXACTLY
    # (no second Shellwords pass) so an escaped-space token can't
    # re-split into a whitelisted first word downstream.
    describe 'unparseable command strings and no second tokenize' do
      it 'refuses an unbalanced-quote command string with a clear error' do
        server = { 'command' => "ruby -e p:ok #'/node", 'args' => [], 'env' => {} }

        expect { described_class.validate_stdio_server!(server) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /unparseable/i)
      end

      it 'refuses another unbalanced-quote command string' do
        server = { 'command' => "node -e 'x", 'args' => [], 'env' => {} }

        expect { described_class.validate_stdio_server!(server) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /unparseable/i)
      end

      it 'refuses an escaped-space command string rather than re-splitting the resolved token into a whitelisted word' do
        # Shellwords.split("node\\ -e x") resolves to a SINGLE token
        # "node -e" (the escaped space is unescaped, not a separator) plus
        # "x". Re-tokenizing "node -e" a second time would split it back
        # into ["node", "-e"] and pass "node" as the whitelisted command —
        # exactly the bypass this closes.
        server = { 'command' => "node\\ -e x", 'args' => [], 'env' => {} }

        expect { described_class.validate_stdio_server!(server) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /not in the allowed list/)
      end
    end

    # IMP-e2cba83ee39f BLOCKER: the child stdio MCP server process must
    # NEVER inherit the worker's own environment — Process.spawn/Open3
    # MERGE a given env Hash ON TOP of the current process's full
    # environment by default (unsetenv_others defaults to false), so
    # every worker secret would otherwise leak into the spawned server
    # even though this class only ever built a small, deliberate env.
    # #spawn_stdio pairs this with unsetenv_others: true (see its own
    # specs at each of the 4 call sites) so this hash really is the ONLY
    # thing the child ever sees.
    describe 'worker env passthrough, never the worker\'s full environment' do
      around do |example|
        original = ENV.to_hash
        ENV['MCP_WORKER_SECRET_SENTINEL'] = 'do-not-leak-me'
        example.run
      ensure
        ENV.replace(original)
      end

      it 'never lets a worker secret reach the env passed to Open3, while PATH and the validated server env are present' do
        server = { 'command' => 'node', 'env' => { 'MCP_API_KEY' => 'secret' } }

        _command, env, = described_class.validate_stdio_server!(server)

        expect(env).not_to include('MCP_WORKER_SECRET_SENTINEL')
        expect(env).to include('PATH' => ENV['PATH'], 'MCP_API_KEY' => 'secret')
      end

      it 'never lets the sentinel through even in strict mode' do
        server = {
          'command' => 'node',
          'env' => { 'MCP_API_KEY' => 'secret' },
          'capabilities' => { 'strict_environment' => true }
        }

        _command, env, = described_class.validate_stdio_server!(server)

        expect(env).not_to include('MCP_WORKER_SECRET_SENTINEL')
      end

      it "passes through HOME/LANG/LC_ALL/TZ/TMPDIR from the worker's own env when present, nothing else" do
        ENV['LC_ALL'] = 'en_US.UTF-8'
        ENV['TZ'] = 'UTC'
        ENV['TMPDIR'] = '/tmp/mcp-test'

        server = { 'command' => 'node', 'env' => {} }
        _command, env, = described_class.validate_stdio_server!(server)

        expect(env).to include(
          'PATH' => ENV['PATH'],
          'HOME' => ENV['HOME'],
          'LC_ALL' => 'en_US.UTF-8',
          'TZ' => 'UTC',
          'TMPDIR' => '/tmp/mcp-test'
        )
      end

      it "a server-supplied PATH or HOME is refused outright — the worker's own values always win" do
        expect { described_class.validate_stdio_server!({ 'command' => 'node', 'env' => { 'PATH' => '/tmp/evil-bin' } }) }
          .to raise_error(McpSecurityService::EnvironmentViolationError, /PATH/)
        expect { described_class.validate_stdio_server!({ 'command' => 'node', 'env' => { 'HOME' => '/tmp/evil-home' } }) }
          .to raise_error(McpSecurityService::EnvironmentViolationError, /HOME/)
      end

      it "a server-supplied LANG/TZ/TMPDIR DOES override the worker's passthrough value (only PATH/HOME are pinned)" do
        ENV['TZ'] = 'UTC'
        server = { 'command' => 'node', 'env' => { 'TZ' => 'America/New_York' } }

        _command, env, = described_class.validate_stdio_server!(server)

        expect(env['TZ']).to eq('America/New_York')
      end

      # IMP-e2cba83ee39f round 2: everything above asserts on the Hash
      # #validate_stdio_server!/#build_stdio_env RETURN — this spawns a
      # REAL child process through #spawn_stdio (the actual call sites'
      # code path) and inspects what environment the CHILD ITSELF
      # observes, so a defect that only shows up in how Open3 actually
      # applies `env`/`unsetenv_others` (rather than in the Hash this
      # class builds) can't hide behind a stubbed Open3.
      it 'spawns a real ruby child whose observed env is exactly the passthrough plus server keys, sentinel absent' do
        require 'tempfile'
        script = Tempfile.new(['mcp_env_probe', '.rb'])
        begin
          script.write('puts ENV.keys.sort.join(",")')
          script.close

          server = { 'command' => 'ruby', 'args' => [script.path], 'env' => { 'MCP_API_KEY' => 'secret' } }
          command, env, args = described_class.validate_stdio_server!(server)

          stdout, stderr, status = described_class.spawn_stdio(command, env, args, stdin_data: '')

          expect(status).to be_success, "ruby child failed: #{stderr}"
          child_keys = stdout.strip.split(',')

          expect(child_keys).not_to include('MCP_WORKER_SECRET_SENTINEL')
          expect(child_keys.sort).to eq(env.keys.sort)
        ensure
          script.unlink
        end
      end
    end

    # IMP-4689ce5a4acb: Open3.capture3 had no deadline — a hung MCP child
    # pinned whatever job thread called #spawn_stdio forever. These are
    # real, unstubbed spawns — a mocked Open3/popen3 can't prove the
    # actual kill/reap/no-zombie behavior, only that this class INTENDED
    # to call something.
    describe '#spawn_stdio deadline enforcement' do
      # A grandchild that outlives its immediate parent gets reparented —
      # commonly to PID 1 — which is responsible for reaping it once it
      # actually exits. That reaping is not instantaneous and is not
      # #spawn_stdio's job (a grandchild is never in wait_thr's own reap
      # scope), so briefly polling for either full removal (ESRCH) or a
      # zombie state ('Z' in /proc/<pid>/stat — dead, just not yet
      # reaped) both count as "the kill reached it"; a live, non-zombie
      # process after the poll window does not.
      def self.process_dead?(pid, timeout: 2)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          begin
            Process.kill(0, pid)
          rescue Errno::ESRCH
            return true
          end
          stat = File.read("/proc/#{pid}/stat")
          return true if stat.include?(') Z ')
          return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep 0.05
        end
      rescue Errno::ENOENT
        true # /proc/<pid> disappeared between the kill(0) check and the read — gone.
      end

      it 'spawns the child as leader of its OWN process group (pgroup: true) — a hung grandchild in the group is still killable, not just the direct child' do
        require 'tempfile'
        script = Tempfile.new(['mcp_pgrp_probe', '.rb'])
        begin
          script.write('puts Process.getpgrp')
          script.close

          command, env, args = described_class.validate_stdio_server!(
            'command' => 'ruby', 'args' => [script.path]
          )
          stdout, stderr, status = described_class.spawn_stdio(command, env, args, stdin_data: '')

          expect(status).to be_success, "ruby child failed: #{stderr}"
          child_pgrp = stdout.strip.to_i

          expect(child_pgrp).not_to eq(Process.getpgrp)
        ensure
          script.unlink
        end
      end

      it 'kills a child that sleeps past its deadline, reaps it (no zombie), and kills any grandchild in its process group too' do
        require 'tempfile'
        pidfile = Tempfile.new('mcp_timeout_pids')
        script = Tempfile.new(['mcp_timeout_probe', '.rb'])
        begin
          pidfile.close
          # Writes its own pid, then a grandchild's (a plain `sleep`,
          # inheriting this process's group since pgroup: true only sets
          # the DIRECT child as group leader), before sleeping well past
          # the deadline itself.
          # Both writes happen at STARTUP, well before any plausible
          # deadline — timeout: 3 (not 1) below is purely headroom
          # against a slow CI host's fork+exec+ruby-boot time, not
          # because the writes themselves are slow.
          script.write(<<~RUBY)
            File.open(ARGV[0], 'w') { |f| f.puts Process.pid }
            grandchild = Process.spawn('sleep', '60')
            File.open(ARGV[0], 'a') { |f| f.puts grandchild }
            sleep 60
          RUBY
          script.close

          command, env, args = described_class.validate_stdio_server!(
            'command' => 'ruby', 'args' => [script.path, pidfile.path]
          )

          expect do
            described_class.spawn_stdio(command, env, args, stdin_data: '', timeout: 3)
          end.to raise_error(described_class::StdioTimeoutError, /exceeded 3s/)

          child_pid, grandchild_pid = File.readlines(pidfile.path).map(&:to_i)
          expect(grandchild_pid).to be_a(Integer).and be_positive

          # ECHILD (not a live/zombie status) means the OS has already
          # fully reaped this process — proving #spawn_stdio's kill path
          # actually waited it out rather than abandoning it as a zombie.
          expect { Process.waitpid(child_pid) }.to raise_error(Errno::ECHILD)
          expect(self.class.process_dead?(grandchild_pid)).to be true
        ensure
          script.unlink
          pidfile.unlink
        end
      end

      # IMP-4689ce5a4acb review round 1 — an Interrupt, a Thread#raise
      # injected from elsewhere, or an unexpected IOError inside the
      # select loop used to just unwind, leaving the (still-running)
      # child and its whole process group behind with nothing left to
      # ever kill it — the deadline check only fires from inside the
      # loop's own normal iteration, not from an exception path. Stubs
      # IO.select (the one syscall #spawn_stdio's loop makes every
      # iteration) to blow up once the child has actually written its
      # pid, against a REAL spawned child, so the kill/reap assertions
      # below prove something real. Every call before that is passed
      # through to the real IO.select (which blocks up to
      # STDIO_SELECT_SLICE_SECONDS ~0.2s waiting on the child's
      # stdout/stderr) — flake fix (post-round-1): gating on the
      # pidfile's own content, not a fixed call count, avoids racing a
      # slow Ruby boot on a loaded host, which could otherwise still
      # leave the pidfile empty when the stub fires on a fixed "2nd
      # call" before the child ever got scheduled.
      it 'kills the child on ANY unexpected exception inside the loop, not just a deadline' do
        require 'tempfile'
        pidfile = Tempfile.new('mcp_exception_kill_pid')
        script = Tempfile.new(['mcp_exception_kill_probe', '.rb'])
        begin
          pidfile.close
          script.write("File.write(ARGV[0], Process.pid.to_s)\nsleep 60")
          script.close

          command, env, args = described_class.validate_stdio_server!(
            'command' => 'ruby', 'args' => [script.path, pidfile.path]
          )

          original_select = IO.method(:select)
          call_count = 0
          allow(IO).to receive(:select) do |*select_args|
            call_count += 1
            if call_count > 1 && File.size?(pidfile.path)
              raise IOError, 'simulated unexpected failure'
            else
              original_select.call(*select_args)
            end
          end

          expect do
            described_class.spawn_stdio(command, env, args, stdin_data: '', timeout: 30)
          end.to raise_error(IOError, 'simulated unexpected failure')

          child_pid = File.read(pidfile.path).to_i
          expect(child_pid).to be_positive
          expect { Process.waitpid(child_pid) }.to raise_error(Errno::ECHILD)
        ensure
          script.unlink
          pidfile.unlink
        end
      end

      it 'leaves a normal, well-behaved child unaffected — returns stdout, stderr and status' do
        require 'tempfile'
        script = Tempfile.new(['mcp_normal_child', '.rb'])
        begin
          script.write("puts 1 + 1\nwarn 'to stderr'")
          script.close

          command, env, args = described_class.validate_stdio_server!('command' => 'ruby', 'args' => [script.path])
          stdout, stderr, status = described_class.spawn_stdio(command, env, args, stdin_data: '', timeout: 5)

          expect(status).to be_success, "ruby child failed: #{stderr}"
          expect(stdout.strip).to eq('2')
          expect(stderr.strip).to eq('to stderr')
        ensure
          script.unlink
        end
      end

      # The care point this proves: writing ALL of stdin before reading
      # ANY of stdout would deadlock here — the child can't finish
      # reading a payload this large from stdin without ALSO writing
      # enough to stdout to fill ITS pipe buffer first, and neither side
      # would ever unblock. #spawn_stdio interleaves both in one
      # IO.select loop specifically so this completes instead.
      it 'completes the large-stdin-plus-large-stdout case without deadlocking' do
        require 'tempfile'
        script = Tempfile.new(['mcp_echo_probe', '.rb'])
        begin
          script.write('STDOUT.write(STDIN.read)')
          script.close

          big = 'x' * 4_000_000 # far larger than a pipe's ~64KB kernel buffer
          command, env, args = described_class.validate_stdio_server!('command' => 'ruby', 'args' => [script.path])
          stdout, stderr, status = described_class.spawn_stdio(command, env, args, stdin_data: big, timeout: 15)

          expect(status).to be_success, "ruby child failed: #{stderr}"
          expect(stdout.bytesize).to eq(big.bytesize)
          expect(stdout).to eq(big)
        ensure
          script.unlink
        end
      end
    end
  end

  # IMP-a50680fd53d8 (MCP isolation Phase 1 T2) — every stdio MCP child
  # runs inside a transient systemd-run sandbox unless
  # MCP_STDIO_SANDBOX_MODE=off. spec_helper.rb sets that globally for the
  # WHOLE suite (not by changing the production default) so every OTHER
  # spec in this file — including the pre-existing IMP-4689ce5a4acb
  # real-spawn deadline/pgroup/large-stdin specs above — keeps passing
  # unprivileged, unchanged. This block covers the sandbox machinery
  # itself: everything that can be verified WITHOUT real root/systemd-run
  # (argv construction, the env file, mode resolution, fail-closed) plus
  # a root-gated block of REAL sandboxed spawns, skipped with a clear
  # message unless #real_sandbox_available? (Process.uid == 0 && a real
  # systemd-run on PATH).
  describe '#spawn_stdio sandboxing' do
    describe '.sandbox_mode' do
      it 'defaults to required when unset' do
        with_sandbox_mode(nil) { expect(described_class.sandbox_mode).to eq('required') }
      end

      it 'accepts available and off' do
        with_sandbox_mode('available') { expect(described_class.sandbox_mode).to eq('available') }
        with_sandbox_mode('off') { expect(described_class.sandbox_mode).to eq('off') }
      end

      it 'is case/whitespace-insensitive' do
        with_sandbox_mode(' Available ') { expect(described_class.sandbox_mode).to eq('available') }
      end

      it 'falls back to required on an unrecognized value — a fail-closed setting must not silently read as off' do
        with_sandbox_mode('bogus') { expect(described_class.sandbox_mode).to eq('required') }
      end
    end

    describe '#sandbox_for_this_call? (fail-closed / available-fallback)' do
      it 'returns false without calling #sandbox_available? at all when mode is off' do
        expect(described_class).not_to receive(:sandbox_available?)
        with_sandbox_mode('off') { expect(described_class.send(:sandbox_for_this_call?)).to be false }
      end

      it 'returns true when required and sandboxing is available' do
        allow(described_class).to receive(:sandbox_available?).and_return(true)
        with_sandbox_mode('required') { expect(described_class.send(:sandbox_for_this_call?)).to be true }
      end

      it 'raises SandboxUnavailableError when required and sandboxing is NOT available (fail closed)' do
        allow(described_class).to receive(:sandbox_available?).and_return(false)
        with_sandbox_mode('required') do
          expect { described_class.send(:sandbox_for_this_call?) }.to raise_error(described_class::SandboxUnavailableError)
        end
      end

      it "the required-mode error names the polkit grant when the cause is not being root (IMP-94977647c24c)" do
        allow(described_class).to receive(:sandbox_available?).and_return(false)
        allow(described_class).to receive(:systemd_run_path).and_return('/usr/bin/systemd-run')
        allow(Process).to receive(:uid).and_return(1000)
        with_sandbox_mode('required') do
          expect { described_class.send(:sandbox_for_this_call?) }
            .to raise_error(described_class::SandboxUnavailableError, /polkit/i)
        end
      end

      it 'the required-mode error names the missing binary when systemd-run is absent' do
        allow(described_class).to receive(:sandbox_available?).and_return(false)
        allow(described_class).to receive(:systemd_run_path).and_return(nil)
        with_sandbox_mode('required') do
          expect { described_class.send(:sandbox_for_this_call?) }
            .to raise_error(described_class::SandboxUnavailableError, /systemd-run/i)
        end
      end

      it 'falls back to UNSANDBOXED with a WARN log when available and sandboxing is NOT available — never silent' do
        allow(described_class).to receive(:sandbox_available?).and_return(false)
        logger_double = described_class.send(:logger)
        expect(logger_double).to receive(:warn).with(/UNSANDBOXED/)
        with_sandbox_mode('available') { expect(described_class.send(:sandbox_for_this_call?)).to be false }
      end
    end

    describe '#sandbox_available?' do
      it 'is false when not root, even with systemd-run present' do
        allow(Process).to receive(:uid).and_return(1000)
        allow(described_class).to receive(:systemd_run_path).and_return('/usr/bin/systemd-run')
        expect(described_class.send(:sandbox_available?)).to be false
      end

      it 'is false when root but systemd-run is missing' do
        allow(Process).to receive(:uid).and_return(0)
        allow(described_class).to receive(:systemd_run_path).and_return(nil)
        expect(described_class.send(:sandbox_available?)).to be false
      end

      it 'is true when root AND systemd-run is present' do
        allow(Process).to receive(:uid).and_return(0)
        allow(described_class).to receive(:systemd_run_path).and_return('/usr/bin/systemd-run')
        expect(described_class.send(:sandbox_available?)).to be true
      end
    end

    describe '#sandboxed_spawn_argv (unit — argv construction, no real spawn)' do
      let(:env_file_path) { described_class.send(:write_sandbox_env_file, {}) }

      after { described_class.send(:cleanup_sandbox_env_file, env_file_path) }

      it 'wraps the command in systemd-run with the expected hardening properties' do
        spawn_env, spawn_command, spawn_args = described_class.send(
          :sandboxed_spawn_argv, 'node', [ 'server.js' ],
          env: { 'PATH' => '/usr/bin' }, unit_name: 'mcp-stdio-test-unit',
          env_file_path: env_file_path, timeout: 30, allow_network: false
        )

        expect(spawn_command).to eq(described_class.send(:systemd_run_path))
        expect(spawn_args).to include(
          '--unit=mcp-stdio-test-unit', 'DynamicUser=yes', "User=#{described_class::SANDBOX_USER_NAME}",
          'ProtectSystem=strict', 'ProtectHome=yes', 'PrivateTmp=yes', 'NoNewPrivileges=yes',
          'RuntimeMaxSec=30', 'IPAddressDeny=any', "EnvironmentFile=#{env_file_path}",
          "CacheDirectory=#{described_class::SANDBOX_CACHE_DIR_NAME}"
        )
        expect(spawn_args.last(3)).to eq([ '--', 'node', 'server.js' ])
        # The systemd-run CLIENT's own env is NOT the sandboxed child's
        # env — deliberately minimal (see #spawn_stdio's own comment).
        expect(spawn_env).to eq('PATH' => ENV['PATH'].to_s)
      end

      it 'omits the full-deny IPAddressDeny=any when allow_network is true' do
        allow(described_class).to receive(:resolver_stub_addresses).and_return([])
        allow(described_class).to receive(:host_own_addresses).and_return([])

        _, _, spawn_args = described_class.send(
          :sandboxed_spawn_argv, 'node', [], env: {}, unit_name: 'u',
          env_file_path: env_file_path, timeout: 30, allow_network: true
        )
        expect(spawn_args).not_to include('IPAddressDeny=any')
      end

      # IMP-bf72723ef161 review — the ORIGINAL allow_network=true path
      # omitted ALL IP filtering, leaving every loopback service on the
      # host (and the cloud metadata address) reachable. Stubs
      # #resolver_stub_addresses for determinism (the real method reads
      # this machine's own /etc/resolv.conf).
      it 'denies loopback/link-local/metadata/host addresses but allows the resolver stub when allow_network is true' do
        allow(described_class).to receive(:resolver_stub_addresses).and_return([ '127.0.0.53' ])
        allow(described_class).to receive(:host_own_addresses).and_return([ '10.0.0.5', '::1' ])

        _, _, spawn_args = described_class.send(
          :sandboxed_spawn_argv, 'node', [], env: {}, unit_name: 'u',
          env_file_path: env_file_path, timeout: 30, allow_network: true
        )

        expect(spawn_args).to include(
          'RestrictAddressFamilies=AF_INET AF_INET6', 'IPAddressDeny=localhost', 'IPAddressDeny=link-local',
          "IPAddressDeny=#{described_class::EGRESS_METADATA_ADDRESS}/32", 'IPAddressAllow=127.0.0.53'
        )
        # IMP-bf72723ef161 review round 2 fix 4 — every host_own_addresses
        # entry gets its own IPAddressDeny, same as the generic tokens.
        expect(spawn_args).to include('IPAddressDeny=10.0.0.5', 'IPAddressDeny=::1')
      end

      # IMP-bf72723ef161 — the deny-except-allowlist branch: PrivateNetwork
      # must NEVER be set here (confirmed empirically it isolates DNS
      # entirely), RestrictAddressFamilies closes the AF_UNIX gap that
      # leaves, and IPAddressAllow carries the resolver stub PLUS every
      # resolved, non-forbidden entry from egress_allowlist.
      it 'builds a deny-except-allowlist policy, never PrivateNetwork, when egress_allowlist is present' do
        allow(described_class).to receive(:resolver_stub_addresses).and_return([ '127.0.0.53' ])

        _, _, spawn_args = described_class.send(
          :sandboxed_spawn_argv, 'node', [], env: {}, unit_name: 'u',
          env_file_path: env_file_path, timeout: 30, allow_network: false,
          egress_allowlist: [ '10.0.0.0/8' ]
        )

        expect(spawn_args).to include(
          'RestrictAddressFamilies=AF_INET AF_INET6', 'IPAddressAllow=127.0.0.53',
          'IPAddressAllow=10.0.0.0/8', 'IPAddressDeny=any'
        )
        expect(spawn_args).not_to include('PrivateNetwork=yes')
      end

      it 'still sets PrivateNetwork=yes for the plain full-deny path (no allow_network, no allowlist)' do
        _, _, spawn_args = described_class.send(
          :sandboxed_spawn_argv, 'node', [], env: {}, unit_name: 'u',
          env_file_path: env_file_path, timeout: 30, allow_network: false
        )
        expect(spawn_args).to include('IPAddressDeny=any', 'PrivateNetwork=yes')
        expect(spawn_args).not_to include('RestrictAddressFamilies=AF_INET AF_INET6')
      end

      it 'never puts server-supplied env (e.g. an API key) on --setenv — only this process\'s own passthrough keys' do
        _, _, spawn_args = described_class.send(
          :sandboxed_spawn_argv, 'node', [],
          env: { 'PATH' => '/usr/bin', 'API_KEY' => 'super-secret-value' },
          unit_name: 'u', env_file_path: env_file_path, timeout: 30, allow_network: false
        )
        joined = spawn_args.join(' ')
        expect(joined).not_to include('super-secret-value')
        expect(joined).to include('--setenv=PATH=/usr/bin')
      end

      it 'overrides HOME to the sandbox cache directory, never a passthrough HOME value' do
        _, _, spawn_args = described_class.send(
          :sandboxed_spawn_argv, 'node', [], env: { 'HOME' => '/home/worker' },
          unit_name: 'u', env_file_path: env_file_path, timeout: 30, allow_network: false
        )
        expect(spawn_args).to include("--setenv=HOME=/var/cache/#{described_class::SANDBOX_CACHE_DIR_NAME}")
        expect(spawn_args.join(' ')).not_to include('--setenv=HOME=/home/worker')
      end
    end

    # IMP-bf72723ef161
    describe '#resolver_stub_addresses' do
      it 'extracts nameserver IPs from /etc/resolv.conf' do
        resolv_conf = <<~RESOLV
          # comment line, ignored
          nameserver 127.0.0.53
          options edns0 trust-ad
          search example.com
        RESOLV
        allow(File).to receive(:readlines).with('/etc/resolv.conf').and_return(resolv_conf.lines)

        expect(described_class.send(:resolver_stub_addresses)).to eq([ '127.0.0.53' ])
      end

      it 'returns every nameserver line, not just the first' do
        resolv_conf = "nameserver 127.0.0.53\nnameserver 192.0.2.10\n"
        allow(File).to receive(:readlines).with('/etc/resolv.conf').and_return(resolv_conf.lines)

        expect(described_class.send(:resolver_stub_addresses)).to eq([ '127.0.0.53', '192.0.2.10' ])
      end

      it 'returns an empty array when /etc/resolv.conf does not exist' do
        allow(File).to receive(:readlines).with('/etc/resolv.conf').and_raise(Errno::ENOENT)

        expect(described_class.send(:resolver_stub_addresses)).to eq([])
      end

      # IMP-bf72723ef161 review round 2 fix 1 — a zone-scoped address
      # ("fe80::1%eth0") passed straight to `-p IPAddressAllow=` fails the
      # WHOLE unit to start (confirmed empirically), so every zone suffix
      # must be stripped before it ever reaches argv construction.
      it 'strips a %zone suffix from a link-local nameserver' do
        resolv_conf = "nameserver fe80::1%eth0\n"
        allow(File).to receive(:readlines).with('/etc/resolv.conf').and_return(resolv_conf.lines)

        expect(described_class.send(:resolver_stub_addresses)).to eq([ 'fe80::1' ])
      end

      it 'drops (with a WARN) a nameserver value that does not parse as an IP even after stripping a zone' do
        resolv_conf = "nameserver not-an-ip\n"
        allow(File).to receive(:readlines).with('/etc/resolv.conf').and_return(resolv_conf.lines)
        logger_double = instance_double(Logger, warn: nil)
        allow(described_class).to receive(:logger).and_return(logger_double)

        expect(described_class.send(:resolver_stub_addresses)).to eq([])
        expect(logger_double).to have_received(:warn).with(/not-an-ip.*dropped/)
      end
    end

    # IMP-bf72723ef161 review round 2 fix 4
    describe '#host_own_addresses' do
      it "returns every address from Socket.ip_address_list, every family, nothing excluded" do
        addr1 = instance_double(Addrinfo, ip_address: '10.0.0.5')
        addr2 = instance_double(Addrinfo, ip_address: '::1')
        allow(Socket).to receive(:ip_address_list).and_return([ addr1, addr2 ])

        expect(described_class.send(:host_own_addresses)).to eq([ '10.0.0.5', '::1' ])
      end

      it 'strips a %zone suffix from a link-local interface address' do
        addr = instance_double(Addrinfo, ip_address: 'fe80::1%eth0')
        allow(Socket).to receive(:ip_address_list).and_return([ addr ])

        expect(described_class.send(:host_own_addresses)).to eq([ 'fe80::1' ])
      end

      it 'logs a WARN and returns an empty array if enumeration itself fails' do
        allow(Socket).to receive(:ip_address_list).and_raise(StandardError, 'boom')
        logger_double = instance_double(Logger, warn: nil)
        allow(described_class).to receive(:logger).and_return(logger_double)

        expect(described_class.send(:host_own_addresses)).to eq([])
        expect(logger_double).to have_received(:warn).with(/boom/)
      end
    end

    # IMP-bf72723ef161 review amendment 2 (DNS rebinding / SSRF)
    describe '#resolve_egress_allowlist' do
      it 'keeps a literal IP/CIDR entry that is not forbidden' do
        expect(described_class.send(:resolve_egress_allowlist, [ '10.0.0.0/8', '93.184.216.34' ]))
          .to match_array([ '10.0.0.0/8', '93.184.216.34' ])
      end

      it 'drops a literal entry inside a forbidden range and logs a WARN' do
        logger_double = instance_double(Logger, warn: nil)
        allow(described_class).to receive(:logger).and_return(logger_double)

        expect(described_class.send(:resolve_egress_allowlist, [ '169.254.169.254' ])).to eq([])
        expect(logger_double).to have_received(:warn).with(/169\.254\.169\.254.*forbidden range/)
      end

      it 'resolves a hostname entry (fresh, via Resolv) and keeps its non-forbidden IPs' do
        allow(Resolv).to receive(:getaddresses).with('api.example.com').and_return([ '93.184.216.34' ])

        expect(described_class.send(:resolve_egress_allowlist, [ 'api.example.com' ])).to eq([ '93.184.216.34' ])
      end

      it "drops a resolved IP that falls in a forbidden range (DNS rebinding) and logs a WARN — never adds it" do
        allow(Resolv).to receive(:getaddresses).with('rebound.example.com').and_return([ '169.254.169.254' ])
        logger_double = instance_double(Logger, warn: nil)
        allow(described_class).to receive(:logger).and_return(logger_double)

        expect(described_class.send(:resolve_egress_allowlist, [ 'rebound.example.com' ])).to eq([])
        expect(logger_double).to have_received(:warn).with(/rebound\.example\.com.*resolved to forbidden IP/)
      end

      it 'keeps the safe IPs and drops only the forbidden ones when a hostname resolves to a mix' do
        allow(Resolv).to receive(:getaddresses).with('mixed.example.com')
                                                .and_return([ '93.184.216.34', '127.0.0.1' ])

        expect(described_class.send(:resolve_egress_allowlist, [ 'mixed.example.com' ])).to eq([ '93.184.216.34' ])
      end

      it 'logs a WARN when a hostname resolves to no addresses at all, without raising' do
        allow(Resolv).to receive(:getaddresses).with('nowhere.example.com').and_return([])
        logger_double = instance_double(Logger, warn: nil)
        allow(described_class).to receive(:logger).and_return(logger_double)

        expect { described_class.send(:resolve_egress_allowlist, [ 'nowhere.example.com' ]) }.not_to raise_error
        expect(logger_double).to have_received(:warn).with(/nowhere\.example\.com.*resolved to no addresses/)
      end

      it 'swallows a Resolv error, logs a WARN, and treats it as zero addresses' do
        allow(Resolv).to receive(:getaddresses).with('errors.example.com').and_raise(Resolv::ResolvTimeout)
        logger_double = instance_double(Logger, warn: nil)
        allow(described_class).to receive(:logger).and_return(logger_double)

        expect { described_class.send(:resolve_egress_allowlist, [ 'errors.example.com' ]) }.not_to raise_error
        expect(logger_double).to have_received(:warn).with(/errors\.example\.com.*failed to resolve/)
      end

      it 'deduplicates the final resolved set' do
        allow(Resolv).to receive(:getaddresses).with('dup.example.com').and_return([ '93.184.216.34' ])

        expect(described_class.send(:resolve_egress_allowlist, [ '93.184.216.34', 'dup.example.com' ]))
          .to eq([ '93.184.216.34' ])
      end

      # IMP-bf72723ef161 review round 2 fix 3 — a numeric/hex pseudo-IP
      # entry is dropped OUTRIGHT, never attempted as a hostname
      # resolution at all — Resolv.getaddresses must not even be called.
      it 'drops a numeric/hex pseudo-IP entry without attempting to resolve it, and logs a WARN' do
        expect(Resolv).not_to receive(:getaddresses)
        logger_double = instance_double(Logger, warn: nil)
        allow(described_class).to receive(:logger).and_return(logger_double)

        expect(described_class.send(:resolve_egress_allowlist, [ '2130706433' ])).to eq([])
        expect(logger_double).to have_received(:warn).with(/2130706433.*pseudo-IP/)
      end

      it 'keeps an IPv4-mapped IPv6 literal of an ordinary public IP but drops one naming loopback' do
        expect(described_class.send(:resolve_egress_allowlist, [ '::ffff:93.184.216.34' ]))
          .to eq([ '::ffff:93.184.216.34' ])
        expect(described_class.send(:resolve_egress_allowlist, [ '::ffff:127.0.0.1' ])).to eq([])
      end
    end

    # IMP-bf72723ef161
    describe '#egress_ip_forbidden?' do
      it 'is true for loopback, link-local and the metadata address' do
        %w[127.0.0.1 169.254.1.1 169.254.169.254 ::1 fe80::1].each do |ip|
          expect(described_class.send(:egress_ip_forbidden?, IPAddr.new(ip))).to be(true), "expected #{ip} forbidden"
        end
      end

      it 'is false for an ordinary public IP' do
        expect(described_class.send(:egress_ip_forbidden?, IPAddr.new('93.184.216.34'))).to be(false)
      end

      # IMP-bf72723ef161 review round 2 fix 2 — an IPv4-mapped IPv6
      # literal is a real, working way to NAME an IPv4 address; without
      # normalizing to its native form first, ::ffff:127.0.0.1 and
      # ::ffff:169.254.169.254 never match the plain IPv4 CIDRs in
      # EGRESS_FORBIDDEN_RANGES (cross-family #include? is always false).
      it 'is true for an IPv4-mapped IPv6 loopback or metadata address' do
        %w[::ffff:127.0.0.1 ::ffff:169.254.169.254].each do |ip|
          expect(described_class.send(:egress_ip_forbidden?, IPAddr.new(ip))).to be(true),
                                                                                  "expected #{ip} forbidden"
        end
      end

      it 'is false for an IPv4-mapped IPv6 form of an ordinary public IP' do
        expect(described_class.send(:egress_ip_forbidden?, IPAddr.new('::ffff:93.184.216.34'))).to be(false)
      end
    end

    # IMP-bf72723ef161 review round 2 fix 3
    describe '#egress_entry_looks_like_pseudo_ip?' do
      it 'is true for numeric/octal/hex pseudo-IP forms' do
        %w[2130706433 127.1 0177.0.0.1 0x7f.0.0.1 0x7f000001].each do |entry|
          expect(described_class.send(:egress_entry_looks_like_pseudo_ip?, entry)).to be(true),
                                                                                       "expected #{entry} to look like a pseudo-IP"
        end
      end

      it 'is false for a real-looking hostname' do
        expect(described_class.send(:egress_entry_looks_like_pseudo_ip?, 'api.example.com')).to be(false)
      end

      it 'is false for a hostname with a leading numeric label (e.g. NTP pool style)' do
        expect(described_class.send(:egress_entry_looks_like_pseudo_ip?, '1.pool.example.com')).to be(false)
      end
    end

    # IMP-bf72723ef161 review — the effective allow set is logged at INFO;
    # server id and resolved IPs only, never env.
    describe '#network_policy_argv logging' do
      it 'logs the server id and effective allow ips at INFO for the allowlist mode' do
        allow(described_class).to receive(:resolver_stub_addresses).and_return([ '127.0.0.53' ])
        logger_double = instance_double(Logger, info: nil)
        allow(described_class).to receive(:logger).and_return(logger_double)

        described_class.send(:network_policy_argv, allow_network: false, egress_allowlist: [ '10.0.0.0/8' ],
                                                     mcp_server_id: 'server-123')

        expect(logger_double).to have_received(:info)
          .with(/server="server-123".*mode=deny_except_allowlist.*127\.0\.0\.53.*10\.0\.0\.0\/8/)
      end

      it 'never includes env values in the logged line' do
        allow(described_class).to receive(:resolver_stub_addresses).and_return([ '127.0.0.53' ])
        logged_lines = []
        logger_double = instance_double(Logger, info: nil)
        allow(logger_double).to receive(:info) { |msg| logged_lines << msg }
        allow(described_class).to receive(:logger).and_return(logger_double)

        described_class.send(:network_policy_argv, allow_network: false, egress_allowlist: [ '10.0.0.0/8' ],
                                                     mcp_server_id: 'server-123')

        expect(logged_lines.join).not_to match(/env|secret|token/i)
      end
    end

    describe '#write_sandbox_env_file / #cleanup_sandbox_env_file' do
      it 'writes double-quoted KEY="value" lines to a mode-0600 file and cleanup removes it' do
        path = described_class.send(:write_sandbox_env_file, { 'FOO' => 'bar', 'BAZ' => 'qux' })

        # IMP-a50680fd53d8 review blocker 2 — every value is written
        # double-quoted (systemd's own EnvironmentFile quoting rule), not
        # bare KEY=value, so a value containing whitespace/quotes/
        # backslashes round-trips unambiguously. See the injection specs
        # below for the cases this format specifically defeats.
        expect(File.read(path)).to eq("FOO=\"bar\"\nBAZ=\"qux\"")
        expect(File.stat(path).mode & 0o777).to eq(0o600)

        described_class.send(:cleanup_sandbox_env_file, path)
        expect(File.exist?(path)).to be false
      end

      it 'cleanup does not raise when the file is already gone' do
        missing = File.join(described_class.send(:sandbox_env_file_dir), 'already-gone.env')
        expect { described_class.send(:cleanup_sandbox_env_file, missing) }.not_to raise_error
      end

      it 'creates the file atomically at 0600 — never a readable-then-tightened window' do
        # O_EXCL means a SECOND write to the same (deliberately re-used)
        # path must fail rather than silently follow/overwrite whatever is
        # already there.
        path = File.join(described_class.send(:sandbox_env_file_dir), "#{SecureRandom.uuid}.env")
        FileUtils.mkdir_p(described_class.send(:sandbox_env_file_dir), mode: 0o700)
        File.write(path, 'PRE_EXISTING=1')

        expect do
          fd = IO.sysopen(path, File::WRONLY | File::CREAT | File::EXCL, 0o600)
          IO.new(fd).close
        end.to raise_error(Errno::EEXIST)
      ensure
        FileUtils.rm_f(path)
      end

      # IMP-a50680fd53d8 review round 2 — a write failure AFTER the O_EXCL
      # create (e.g. Errno::ENOSPC) previously left a PARTIAL, 0600 file
      # on disk forever: the create succeeded, so O_EXCL's own protection
      # doesn't help, and #spawn_stdio's own `ensure` never learns this
      # path since the exception unwinds past the point it captures
      # env_file_path. #write_sandbox_env_file must delete its own
      # partial file before re-raising.
      it 'deletes the partial file if writing fails after the O_EXCL create (e.g. Errno::ENOSPC)' do
        allow(SecureRandom).to receive(:uuid).and_return('fixed-uuid-for-partial-write-test')
        expected_path = File.join(described_class.send(:sandbox_env_file_dir), 'fixed-uuid-for-partial-write-test.env')
        FileUtils.rm_f(expected_path)

        allow(IO).to receive(:new).and_wrap_original do |original, fd|
          io = original.call(fd)
          allow(io).to receive(:write).and_raise(Errno::ENOSPC, 'No space left on device')
          io
        end

        expect do
          described_class.send(:write_sandbox_env_file, { 'A' => 'b' })
        end.to raise_error(Errno::ENOSPC)

        expect(File.exist?(expected_path)).to be false
      ensure
        FileUtils.rm_f(expected_path)
      end

      # IMP-a50680fd53d8 review blocker 2 — a raw newline inside a VALUE
      # would otherwise start an entirely new KEY=VALUE line the systemd
      # EnvironmentFile parser reads as ANOTHER environment variable,
      # bypassing whatever key the value was actually written under (e.g.
      # smuggling in a fabricated LD_PRELOAD=... entry via a value that
      # never mentions LD_PRELOAD in its own key at all) — this must be
      # refused outright, not sanitized/stripped silently.
      it 'refuses a value containing a newline (EnvironmentFile line-injection)' do
        expect do
          described_class.send(:write_sandbox_env_file, { 'MCP_TOKEN' => "safe\nLD_PRELOAD=/tmp/evil.so" })
        end.to raise_error(McpSecurityService::EnvironmentViolationError, /newline/)
      end

      it 'refuses a value containing a carriage return or NUL byte' do
        expect do
          described_class.send(:write_sandbox_env_file, { 'A' => "x\ry" })
        end.to raise_error(McpSecurityService::EnvironmentViolationError, /carriage return/)

        expect do
          described_class.send(:write_sandbox_env_file, { 'A' => "x\0y" })
        end.to raise_error(McpSecurityService::EnvironmentViolationError, /NUL/)
      end

      it 'refuses a key that is not a safe systemd EnvironmentFile identifier' do
        expect do
          described_class.send(:write_sandbox_env_file, { 'NOT A KEY' => 'value' })
        end.to raise_error(McpSecurityService::EnvironmentViolationError, /not a safe systemd EnvironmentFile key/)

        expect do
          described_class.send(:write_sandbox_env_file, { 'FOO=BAR' => 'value' })
        end.to raise_error(McpSecurityService::EnvironmentViolationError)
      end

      it 'double-quotes and escapes a backslash and a double-quote in a value' do
        path = described_class.send(:write_sandbox_env_file, { 'X' => 'a\\b"c' })

        expect(File.read(path)).to eq('X="a\\\\b\\"c"')
      ensure
        described_class.send(:cleanup_sandbox_env_file, path)
      end

      it "fails closed when the env file directory is a symlink" do
        real_dir = described_class.send(:sandbox_env_file_dir)
        FileUtils.rm_rf(real_dir)
        elsewhere = Dir.mktmpdir
        FileUtils.ln_s(elsewhere, real_dir)

        expect do
          described_class.send(:write_sandbox_env_file, { 'A' => 'b' })
        end.to raise_error(McpSecurityService::EnvironmentViolationError, /symlink/)
      ensure
        File.delete(real_dir) if real_dir && File.symlink?(real_dir)
        FileUtils.rm_rf(elsewhere) if elsewhere
      end

      it "fails closed when the env file directory has unsafe permissions" do
        real_dir = described_class.send(:sandbox_env_file_dir)
        FileUtils.mkdir_p(real_dir, mode: 0o700)
        File.chmod(0o755, real_dir)

        expect do
          described_class.send(:write_sandbox_env_file, { 'A' => 'b' })
        end.to raise_error(McpSecurityService::EnvironmentViolationError, /unsafe permissions/)
      ensure
        File.chmod(0o700, real_dir) if real_dir && File.directory?(real_dir)
      end
    end

    describe '#terminate_process_group! with a sandboxed unit_name' do
      it 'stops the generated unit (best-effort, bounded) before the local kill' do
        require 'open3'
        # A real, already-exited child (never a live pid we might
        # accidentally signal) — Process.kill('TERM', -pid) on it below
        # raises Errno::ESRCH, which the method already rescues.
        _stdin, _stdout, _stderr, wait_thr = Open3.popen3('true')
        wait_thr.join
        pid = wait_thr.pid

        expect(described_class).to receive(:stop_sandboxed_unit!).with('mcp-stdio-test-unit')

        described_class.send(:terminate_process_group!, pid, wait_thr, unit_name: 'mcp-stdio-test-unit')
      end

      it 'does not stop any unit when unit_name is nil (unsandboxed path, unchanged)' do
        require 'open3'
        _stdin, _stdout, _stderr, wait_thr = Open3.popen3('true')
        wait_thr.join
        pid = wait_thr.pid

        expect(described_class).not_to receive(:stop_sandboxed_unit!)

        described_class.send(:terminate_process_group!, pid, wait_thr, unit_name: nil)
      end
    end

    # IMP-a50680fd53d8 review blocker 4 — #stop_sandboxed_unit! must itself
    # be bounded: a bare `system('systemctl', 'stop', ...)` had no timeout
    # at all, so a wedged `systemctl stop` (stuck D-Bus call, stuck cgroup
    # teardown) could block #terminate_process_group! — and therefore
    # #spawn_stdio's own deadline enforcement — indefinitely.
    describe '#stop_sandboxed_unit! (bounded systemctl stop)' do
      it 'spawns systemctl stop with the given unit name, in its own process group, and joins bounded' do
        fake_pid = 999_999
        fake_thread = instance_double(Thread, join: true)
        allow(Process).to receive(:spawn)
          .with('systemctl', 'stop', 'mcp-stdio-test-unit', out: File::NULL, err: File::NULL, pgroup: true)
          .and_return(fake_pid)
        allow(Process).to receive(:detach).with(fake_pid).and_return(fake_thread)

        described_class.send(:stop_sandboxed_unit!, 'mcp-stdio-test-unit')

        expect(fake_thread).to have_received(:join).with(described_class::STDIO_TERM_GRACE_SECONDS)
      end

      it "kills the systemctl process's own process group when it does not finish within the grace period" do
        # Real process, real Process.detach, real kill-on-timeout path —
        # only the ARGV `systemctl stop` would have run is substituted
        # (via the exact-args-matched stub below) for a long-sleeping real
        # child, so this proves the actual bound rather than a mocked one.
        hung_pid = Process.spawn('sleep', '10', pgroup: true)
        allow(Process).to receive(:spawn)
          .with('systemctl', 'stop', 'mcp-stdio-test-unit', out: File::NULL, err: File::NULL, pgroup: true)
          .and_return(hung_pid)

        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        described_class.send(:stop_sandboxed_unit!, 'mcp-stdio-test-unit')
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

        expect(elapsed).to be < (described_class::STDIO_TERM_GRACE_SECONDS + 2)
        expect { Process.kill(0, hung_pid) }.to raise_error(Errno::ESRCH)
      ensure
        begin
          Process.kill('KILL', -hung_pid)
          Process.wait(hung_pid)
        rescue Errno::ESRCH, Errno::ECHILD
          nil
        end
      end

      # IMP-a50680fd53d8 review round 2 — a rescue scoped to ONLY
      # Errno::ESRCH left #terminate_process_group!'s own local TERM/KILL
      # sequence never reached at all whenever Process.spawn('systemctl',
      # ...) raised something else (Errno::ENOENT if systemctl isn't on
      # PATH, Errno::EAGAIN under fork pressure, ...) — this is
      # best-effort, so ANY StandardError here must be swallowed (logged,
      # not raised) so the caller's local kill always still runs.
      it 'swallows a StandardError from Process.spawn (e.g. Errno::ENOENT) and logs it, without raising' do
        allow(Process).to receive(:spawn)
          .with('systemctl', 'stop', 'mcp-stdio-test-unit', out: File::NULL, err: File::NULL, pgroup: true)
          .and_raise(Errno::ENOENT, 'No such file or directory - systemctl')
        logger_double = instance_double(Logger, warn: nil)
        allow(described_class).to receive(:logger).and_return(logger_double)

        expect do
          described_class.send(:stop_sandboxed_unit!, 'mcp-stdio-test-unit')
        end.not_to raise_error

        expect(logger_double).to have_received(:warn).with(/stop_sandboxed_unit!.*mcp-stdio-test-unit.*Errno::ENOENT/)
      end
    end

    # IMP-a50680fd53d8 review blocker 3 — a crash BETWEEN writing the env
    # file and Open3.popen3 returning (e.g. Open3.popen3 itself raising
    # Errno::ENOENT when `command` doesn't exist, or Errno::EMFILE under
    # fd exhaustion) used to skip cleanup entirely: the OLD inner
    # begin/ensure only started AFTER popen3 returned successfully. No
    # root/real systemd-run needed here — #sandbox_for_this_call? is
    # stubbed directly so this exercises the Ruby-level exception path,
    # not the sandboxing mechanism itself.
    describe '#spawn_stdio deletes its env file even when the popen3 spawn itself fails' do
      it 'cleans up the env file when Open3.popen3 raises (e.g. Errno::ENOENT)' do
        require 'open3'
        allow(described_class).to receive(:sandbox_for_this_call?).and_return(true)
        written_path = nil
        allow(described_class).to receive(:write_sandbox_env_file).and_wrap_original do |original, env|
          written_path = original.call(env)
        end
        allow(Open3).to receive(:popen3).and_raise(Errno::ENOENT, 'no such file or directory - nonexistent-command')

        expect do
          described_class.spawn_stdio('nonexistent-command', {}, [], stdin_data: '')
        end.to raise_error(Errno::ENOENT)

        expect(written_path).not_to be_nil
        expect(File.exist?(written_path)).to be false
      end
    end

    # ROOT-GATED: exercises the REAL systemd-run sandbox. Skipped with a
    # clear message unless #real_sandbox_available? — never a hard
    # failure just because this run isn't root. Proven once by hand on
    # this dev cell via `sudo bundle exec rspec ...` (see the task's
    # report) — sudo is never part of the product or this harness itself.
    #
    # `-e <inline code>` is refused outright by #validate_stdio_args!
    # (deliberately — see that method's own comment) REGARDLESS of
    # sandboxing, so every probe here is a real SCRIPT FILE, exactly like
    # the pre-existing IMP-4689ce5a4acb real-spawn specs above. That file
    # (and any pidfile a script writes) must live under the SAME
    # CacheDirectory the sandbox itself uses (SANDBOX_CACHE_DIR_NAME,
    # i.e. $HOME inside the sandbox) — verified empirically that
    # PrivateTmp=yes isolates BOTH /tmp AND /var/tmp from a HOST path
    # written there, so a Tempfile under either would be invisible to
    # the sandboxed child; #{CacheDirectory} is the one real, shared,
    # host-visible path both sides can see.
    describe '#spawn_stdio real sandboxed spawn (root-gated)' do
      before do
        skip 'requires real root + a real systemd-run on PATH (not available in this run)' unless real_sandbox_available?
      end

      # Absolute host path to the SAME directory systemd's
      # CacheDirective= creates/points HOME at inside the sandbox —
      # visible to both this (root) test process and the sandboxed
      # child. Created directly (no sandbox involved) so a script can be
      # written there before the spawn.
      def sandbox_probe_dir
        dir = "/var/cache/#{described_class::SANDBOX_CACHE_DIR_NAME}"
        FileUtils.mkdir_p(dir)
        dir
      end

      def write_probe_script(body)
        path = File.join(sandbox_probe_dir, "probe-#{SecureRandom.uuid}.js")
        File.write(path, body)
        path
      end

      it 'spawns the child under a DIFFERENT (DynamicUser) uid than this process' do
        script_path = write_probe_script('console.log(process.getuid())')

        with_sandbox_mode('required') do
          command, env, args = described_class.validate_stdio_server!('command' => 'node', 'args' => [ script_path ])
          stdout, stderr, status = described_class.spawn_stdio(command, env, args, stdin_data: '', timeout: 15)

          expect(status).to be_success, "node child failed: #{stderr}"
          expect(stdout.strip.to_i).not_to eq(Process.uid)
        end
      ensure
        File.delete(script_path) if script_path && File.exist?(script_path)
      end

      it 'blocks network by default, denies loopback/link-local/metadata/host addresses, and allows a non-host LAN address when allow_network: true' do
        require 'socket'
        # IMP-bf72723ef161 review round 2 fix 4 — the target for the
        # "denied while sandboxed" side is THIS HOST'S OWN LAN address:
        # #host_own_addresses now denies every address Socket.ip_address_list
        # reports for this host (so a service bound to 0.0.0.0, e.g.
        # worker-web/Puma, isn't reachable via the host's own LAN IP even
        # under allow_network: true) — a plain full-deny probe against
        # 127.0.0.1 alone would no longer distinguish "denied by default"
        # from "denied because it's a host address", so this targets the
        # host's own NON-loopback address specifically.
        own_lan_ip = Socket.ip_address_list.find { |addr| addr.ipv4? && !addr.ipv4_loopback? }&.ip_address
        skip 'no non-loopback IPv4 address on this host to target' unless own_lan_ip

        own_lan_server = TCPServer.new(own_lan_ip, 0)
        own_lan_port = own_lan_server.addr[1]
        own_lan_thread = Thread.new do
          client = own_lan_server.accept
          client.write('SHOULD-NOT-BE-REACHABLE')
          client.close
        rescue IOError, Errno::EBADF
          nil
        end

        other_loopback = TCPServer.new('127.0.0.1', 0)
        loopback_port = other_loopback.addr[1]

        # A REAL, already-running, non-host LAN service (this dev cell's
        # own upstream DNS forwarder) — discovered at runtime, never
        # hardcoded (deployment-local fact), from systemd-resolved's own
        # dynamic upstream config (NOT /etc/resolv.conf, which points at
        # the local 127.0.0.53 stub). Used so this test doesn't need to
        # spin up its own listener to prove "a non-host LAN address stays
        # reachable" — binding one would necessarily BE a host address,
        # which fix 4 now denies regardless.
        upstream_line = File.readlines('/run/systemd/resolve/resolv.conf')
                             .find { |l| l.start_with?('nameserver') }
        upstream_ip = upstream_line&.split&.last
        skip 'no upstream nameserver discoverable to use as a non-host reachable target' unless upstream_ip
        skip 'discovered upstream nameserver is this host itself' if upstream_ip == own_lan_ip

        script_path = write_probe_script(<<~PY)
          import socket, subprocess

          def try_connect(host, port, label, timeout=2):
              s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
              s.settimeout(timeout)
              try:
                  s.connect((host, port))
                  print(label + ': REACHED')
              except Exception as e:
                  print(label + ': BLOCKED ' + repr(e))

          try_connect(#{own_lan_ip.inspect}, #{own_lan_port}, 'FULL_DENY')
          try_connect(#{own_lan_ip.inspect}, #{own_lan_port}, 'HOST_OWN_ADDRESS')
          try_connect('127.0.0.1', #{loopback_port}, 'OTHER_LOOPBACK')
          try_connect(#{upstream_ip.inspect}, 53, 'NON_HOST_LAN')
          r = subprocess.run(['getent', 'hosts', 'example.com'], capture_output=True, text=True, timeout=3)
          print('DNS: ' + ('OK' if r.returncode == 0 else 'FAILED'))
        PY

        with_sandbox_mode('required') do
          command, env, args = described_class.validate_stdio_server!('command' => 'python3', 'args' => [ script_path ])

          # allow_network: false (the default) — full deny, unrelated to
          # this test's OWN address specifically.
          denied_stdout, = described_class.spawn_stdio(command, env, args, stdin_data: '', timeout: 15,
                                                                             allow_network: false)
          expect(denied_stdout).to include('FULL_DENY: BLOCKED')

          # allow_network: true — loopback, this host's OWN address, and
          # the metadata range are denied; a genuinely non-host LAN
          # address and DNS both keep working.
          allowed_stdout, = described_class.spawn_stdio(command, env, args, stdin_data: '', timeout: 15,
                                                                              allow_network: true)
          expect(allowed_stdout).to include('HOST_OWN_ADDRESS: BLOCKED')
          expect(allowed_stdout).to include('OTHER_LOOPBACK: BLOCKED')
          expect(allowed_stdout).to include('NON_HOST_LAN: REACHED')
          expect(allowed_stdout).to include('DNS: OK')
        end
      ensure
        own_lan_server&.close
        other_loopback&.close
        own_lan_thread&.join(2)
        File.delete(script_path) if script_path && File.exist?(script_path)
      end

      it 'gives the sandboxed child a writable $HOME (npx/uvx cache) despite ProtectHome' do
        script_path = write_probe_script(
          'require("fs").writeFileSync(require("path").join(process.env.HOME, "probe-write.txt"), "ok"); ' \
          'console.log("WROTE")'
        )

        with_sandbox_mode('required') do
          command, env, args = described_class.validate_stdio_server!('command' => 'node', 'args' => [ script_path ])
          stdout, stderr, status = described_class.spawn_stdio(command, env, args, stdin_data: '', timeout: 15)

          expect(status).to be_success, "node child failed: #{stderr}"
          expect(stdout).to include('WROTE')
        end
      ensure
        File.delete(script_path) if script_path && File.exist?(script_path)
        FileUtils.rm_f(File.join(sandbox_probe_dir, 'probe-write.txt'))
      end

      # IMP-bf72723ef161 — proves the whole deny-except-allowlist path end
      # to end against a REAL systemd-run sandbox: a hostname entry
      # resolves (Resolv is stubbed here, not systemd — resolution happens
      # in THIS worker process, before the spawn, not inside the sandbox)
      # to this host's own LAN-reachable address and stays reachable, a
      # DIFFERENT non-allowlisted address stays blocked, AF_UNIX is
      # blocked once RestrictAddressFamilies applies (the gap
      # PrivateNetwork=yes would otherwise close but can't be used here —
      # it isolates DNS entirely), and DNS itself keeps working (the
      # resolver stub is always implicitly allowed).
      it 'allows a resolved hostname entry, blocks a non-listed address, blocks AF_UNIX, and keeps DNS working' do
        require 'socket'

        lan_ip = Socket.ip_address_list.find { |addr| addr.ipv4? && !addr.ipv4_loopback? }&.ip_address
        skip 'no non-loopback IPv4 address on this host to use as an allowlisted stand-in destination' unless lan_ip

        allowed_server = TCPServer.new(lan_ip, 0)
        allowed_port = allowed_server.addr[1]
        allowed_thread = Thread.new do
          client = allowed_server.accept
          client.write('ALLOWED-OK')
          client.close
        rescue IOError, Errno::EBADF
          nil
        end

        denied_server = TCPServer.new('127.0.0.1', 0)
        denied_port = denied_server.addr[1]

        # Python, not Node, for this probe: synchronous socket calls make
        # the AF_UNIX check unambiguous (a raw socket.socket(AF_UNIX, ...)
        # either succeeds or raises immediately — no async error-event
        # plumbing to get wrong). python3 is on ALLOWED_COMMANDS the same
        # as node.
        script_path = write_probe_script(<<~PY)
          import socket, subprocess

          r = subprocess.run(['getent', 'hosts', 'example.com'], capture_output=True, text=True, timeout=3)
          print('DNS: ' + ('OK' if r.returncode == 0 else 'FAILED'))

          def try_connect(host, port, label):
              s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
              s.settimeout(2)
              try:
                  s.connect((host, port))
                  print(label + ': REACHED ' + s.recv(100).decode())
              except Exception as e:
                  print(label + ': BLOCKED ' + repr(e))

          try_connect(#{lan_ip.inspect}, #{allowed_port}, 'ALLOWED')
          try_connect('127.0.0.1', #{denied_port}, 'DENIED')

          try:
              socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
              print('AF_UNIX: REACHED')
          except OSError as e:
              print('AF_UNIX: BLOCKED ' + repr(e))
        PY

        allow(Resolv).to receive(:getaddresses).with('allowed.example.test').and_return([ lan_ip ])

        with_sandbox_mode('required') do
          command, env, args = described_class.validate_stdio_server!('command' => 'python3', 'args' => [ script_path ])
          stdout, stderr, status = described_class.spawn_stdio(
            command, env, args, stdin_data: '', timeout: 15,
                                 egress_allowlist: [ 'allowed.example.test' ]
          )

          expect(status).to be_success, "python3 child failed: #{stderr}"
          expect(stdout).to include('DNS: OK')
          expect(stdout).to include('ALLOWED: REACHED')
          expect(stdout).to include('DENIED: BLOCKED')
          expect(stdout).to include('AF_UNIX: BLOCKED')
        end
      ensure
        allowed_server&.close
        denied_server&.close
        allowed_thread&.join(2)
        File.delete(script_path) if script_path && File.exist?(script_path)
      end

      # IMP-a50680fd53d8 review blocker 2 — proves the double-quote +
      # backslash-escaping EnvironmentFile format (#format_sandbox_env_file_line)
      # actually round-trips through the REAL systemd EnvironmentFile
      # parser, not just this codebase's own escaping logic in isolation.
      it 'delivers a value containing a backslash and a double-quote byte-exact to the child' do
        tricky_value = 'a\\b"c' # a backslash and a double-quote, both in one value
        script_path = write_probe_script('process.stdout.write(process.env.MCP_TOKEN)')

        with_sandbox_mode('required') do
          command, env, args = described_class.validate_stdio_server!(
            'command' => 'node', 'args' => [ script_path ], 'env' => { 'MCP_TOKEN' => tricky_value }
          )
          stdout, stderr, status = described_class.spawn_stdio(command, env, args, stdin_data: '', timeout: 15)

          expect(status).to be_success, "node child failed: #{stderr}"
          expect(stdout).to eq(tricky_value)
        end
      ensure
        File.delete(script_path) if script_path && File.exist?(script_path)
      end

      it 'kills the sandboxed unit on deadline expiry, leaving no running process behind' do
        pidfile_path = File.join(sandbox_probe_dir, "probe-pid-#{SecureRandom.uuid}.txt")
        script_path = write_probe_script(<<~JS)
          require('fs').writeFileSync(#{pidfile_path.inspect}, String(process.pid));
          setTimeout(() => {}, 60000);
        JS

        with_sandbox_mode('required') do
          command, env, args = described_class.validate_stdio_server!('command' => 'node', 'args' => [ script_path ])

          expect do
            described_class.spawn_stdio(command, env, args, stdin_data: '', timeout: 3)
          end.to raise_error(described_class::StdioTimeoutError, /exceeded 3s/)

          sandboxed_pid = File.read(pidfile_path).to_i
          expect(sandboxed_pid).to be_positive
          # Root can signal(0) any pid regardless of the DynamicUser
          # owning it — ESRCH proves it's actually gone, not just that
          # OUR local client process was killed (see #spawn_stdio's own
          # comment on why killing the client alone doesn't do this).
          sleep 0.5
          expect { Process.kill(0, sandboxed_pid) }.to raise_error(Errno::ESRCH)
        end
      ensure
        File.delete(script_path) if script_path && File.exist?(script_path)
        FileUtils.rm_f(pidfile_path) if pidfile_path
      end
    end
  end

  describe '.validate_stdio_args!' do
    it 'accepts a normal node invocation' do
      expect { described_class.validate_stdio_args!('node', ['server.js', '--port', '3000']) }
        .not_to raise_error
    end

    it 'refuses node -e (the exact defect this task fixes)' do
      expect { described_class.validate_stdio_args!('node', ['-e', 'console.log(1)']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
    end

    it 'refuses node --eval' do
      expect { described_class.validate_stdio_args!('node', ['--eval', 'console.log(1)']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError)
    end

    it 'refuses node --eval=<code> (attached long-flag form)' do
      expect { described_class.validate_stdio_args!('node', ['--eval=console.log(1)']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError)
    end

    it 'refuses node -eCODE (attached short-flag form)' do
      expect { described_class.validate_stdio_args!('node', ['-econsole.log(1)']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError)
    end

    it 'refuses node -pe "code" (combined print+eval short flags)' do
      expect { described_class.validate_stdio_args!('node', ['-pe', '1+1']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError)
    end

    it 'refuses node -p/--print' do
      expect { described_class.validate_stdio_args!('node', ['-p', '1+1']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError)
      expect { described_class.validate_stdio_args!('node', ['--print', '1+1']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError)
    end

    it 'refuses node --import with a bare (non-path) loader name, allows a real path' do
      # IMP-97b6b1185748 item 6: --import gets the SAME path-exempt
      # treatment as -r/--require now — a real local loader file is fine;
      # a bare package/loader name ("tsx") is not.
      expect { described_class.validate_stdio_args!('node', ['--import', 'tsx', 'server.js']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError, /loads an arbitrary \(non-path\) module/)
      expect { described_class.validate_stdio_args!('node', ['--import', './register.mjs', 'server.js']) }
        .not_to raise_error
      expect { described_class.validate_stdio_args!('node', ['--import=data:text/javascript,1', 'server.js']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError)
    end

    it 'refuses node -r/--require with a bare (non-path) module name' do
      expect { described_class.validate_stdio_args!('node', ['-r', 'some-arbitrary-package', 'server.js']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError, /loads an arbitrary \(non-path\) module/)
      expect { described_class.validate_stdio_args!('node', ['--require', 'some-arbitrary-package', 'server.js']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError)
    end

    it 'allows node -r/--require with a value that looks like a file path' do
      expect { described_class.validate_stdio_args!('node', ['-r', './preload.js', 'server.js']) }
        .not_to raise_error
      expect { described_class.validate_stdio_args!('node', ['--require=/app/preload.js', 'server.js']) }
        .not_to raise_error
    end

    it 'applies the same node rules to bun' do
      expect { described_class.validate_stdio_args!('bun', ['-e', '1+1']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError)
      # A bare, non-path positional is refused for bun specifically (item 2
      # below) — a real path passes the same as it would for node/ruby/python.
      expect { described_class.validate_stdio_args!('bun', ['./server.js']) }.not_to raise_error
    end

    it 'refuses python/python3 -c' do
      expect { described_class.validate_stdio_args!('python', ['-c', 'import os; os.system("rm -rf /")']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError)
      expect { described_class.validate_stdio_args!('python3', ['-c', 'print(1)']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError)
      expect { described_class.validate_stdio_args!('python3', ['mcp_server.py']) }.not_to raise_error
    end

    it 'refuses ruby -e and combined -pe' do
      expect { described_class.validate_stdio_args!('ruby', ['-e', 'puts 1']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError)
      expect { described_class.validate_stdio_args!('ruby', ['-pe', 'puts 1']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError)
      expect { described_class.validate_stdio_args!('ruby', ['server.rb']) }.not_to raise_error
    end

    it 'refuses ruby -r with a bare gem name, allows it with a path' do
      expect { described_class.validate_stdio_args!('ruby', ['-r', 'some_gem', 'server.rb']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError)
      expect { described_class.validate_stdio_args!('ruby', ['-r', './lib/preload.rb', 'server.rb']) }
        .not_to raise_error
    end

    it 'refuses the deno eval and repl subcommands (IMP-97b6b1185748 item 4: only run/serve are allowed)' do
      expect { described_class.validate_stdio_args!('deno', ['eval', '1+1']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError, /Deno subcommand 'eval'/)
      expect { described_class.validate_stdio_args!('deno', ['repl']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError, /Deno subcommand 'repl'/)
    end

    it 'refuses deno task and any other non-run/serve subcommand' do
      expect { described_class.validate_stdio_args!('deno', ['task', 'x']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError, /Deno subcommand 'task'/)
    end

    it 'refuses deno with no subcommand at all (defaults to the REPL)' do
      expect { described_class.validate_stdio_args!('deno', []) }
        .to raise_error(McpSecurityService::CommandNotAllowedError, /none — deno defaults to its REPL/)
    end

    it "does not mistake a global value flag (-L/--log-level) for the subcommand" do
      expect { described_class.validate_stdio_args!('deno', ['-L', 'debug', 'eval', 'x']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError, /Deno subcommand 'eval'/)
      expect { described_class.validate_stdio_args!('deno', ['--log-level', 'debug', 'eval', 'x']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError, /Deno subcommand 'eval'/)
      expect { described_class.validate_stdio_args!('deno', ['-L', 'debug', 'run', 'server.ts']) }
        .not_to raise_error
    end

    it 'allows deno serve as well as deno run' do
      expect { described_class.validate_stdio_args!('deno', ['serve', 'server.ts']) }
        .not_to raise_error
    end

    # IMP-97b6b1185748 round 8 BLOCKER — deno's subcommand-finder had the
    # same "assume an unrecognized flag is boolean" bug class round 5
    # fixed for node/bun/ruby/python, never audited. Unlike those, on
    # ambiguity this REFUSES outright rather than falling back to a scan
    # — deno has no inline-code flag to scan for.
    describe "deno's subcommand-finder is fail-closed on any unrecognized flag (round 8)" do
      it 'refuses any unrecognized flag, long or short, before the subcommand' do
        expect { described_class.validate_stdio_args!('deno', ['--v8-flags', 'run', 'eval', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /unrecognized flag \("--v8-flags"\)/)
        expect { described_class.validate_stdio_args!('deno', ['--foo', 'run', 'x.ts']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /unrecognized flag \("--foo"\)/)
        expect { described_class.validate_stdio_args!('deno', ['-z', 'run', 'x.ts']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /unrecognized flag \("-z"\)/)
      end

      it 'allows the small explicit set of known global flags before the subcommand' do
        expect { described_class.validate_stdio_args!('deno', ['run', '-A', 'server.ts']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('deno', ['-q', 'run', 'server.ts']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('deno', ['--log-level=debug', 'run', 's.ts']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('deno', ['-L', 'debug', 'run', 's.ts']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('deno', ['--unstable-kv', 'run', 's.ts']) }.not_to raise_error
      end

      it 'allows any attached "--flag=value" form before the subcommand, even an unrecognized flag name' do
        expect { described_class.validate_stdio_args!('deno', ['--v8-flags=--max-old-space-size=100', 'run', 's.ts']) }
          .not_to raise_error
      end
    end

    it 'allows a normal deno run invocation' do
      expect { described_class.validate_stdio_args!('deno', ['run', '--allow-net', 'server.ts']) }
        .not_to raise_error
    end

    it 'applies no interpreter flag rules by itself for an unrecognized command (env is refused earlier, by validate_command!)' do
      # IMP-97b6b1185748 item 2 (DECISION): env is refused outright at the
      # COMMAND level (validate_command! / validate_stdio_server!), never
      # unwrapped here to peek at args[0] for a "real" interpreter. This
      # method alone has no opinion on "env" as a command name — see the
      # '.validate_stdio_server!' and '.validate_command!' examples for the
      # actual refusal.
      expect { described_class.validate_stdio_args!('/usr/bin/env', ['node', '-e', 'console.log(1)']) }
        .not_to raise_error
    end

    it 'refuses shell metacharacters in any arg, regardless of command' do
      %w[; & | ` $ < >].each do |char|
        expect { described_class.validate_stdio_args!('node', ["server.js#{char}rm -rf /"]) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /forbidden shell metacharacter/), "expected #{char.inspect} to be refused"
      end
    end

    it 'refuses a NUL byte in any arg' do
      expect { described_class.validate_stdio_args!('node', ["server.js\0.evil"]) }
        .to raise_error(McpSecurityService::CommandNotAllowedError, /NUL byte/)
    end

    it 'refuses npx -c/--call, which runs an arbitrary shell command directly (IMP-97b6b1185748 item 4)' do
      expect { described_class.validate_stdio_args!('npx', ['-c', 'id']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-c'/)
      expect { described_class.validate_stdio_args!('npx', ['--call', 'id']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '--call'/)
      expect { described_class.validate_stdio_args!('npx', ['--call=id']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError)
    end

    it 'still allows the ordinary npx launcher pattern (npx -y <package>) — running a named package is by design' do
      # See the class-level SCOPE comment: a launcher running an arbitrary
      # PACKAGE is not what this check exists to prevent.
      expect { described_class.validate_stdio_args!('npx', ['-y', '@modelcontextprotocol/server-filesystem', '/tmp']) }
        .not_to raise_error
    end

    it 'never blocks docker -e (environment variable flag, not code) even in extended mode' do
      # docker/podman are EXTENDED_COMMANDS and are deliberately not in
      # INLINE_CODE_FLAGS_BY_INTERPRETER — allow_extended_commands widens
      # the COMMAND whitelist only, never this argument check, and there
      # is nothing here for it to relax for docker in the first place.
      expect { described_class.validate_stdio_args!('docker', ['run', '-e', 'API_KEY=secret', 'image']) }
        .not_to raise_error
    end

    it 'gives the metacharacter error a hint to move URLs/secrets into env (IMP-97b6b1185748 item 10)' do
      expect { described_class.validate_stdio_args!('node', ['server.js;rm -rf /']) }
        .to raise_error(McpSecurityService::CommandNotAllowedError, /pass it via the environment instead/)
    end

    # IMP-97b6b1185748 item 3 BLOCKER — short-flag cluster scanning.
    # "A blocked letter anywhere is a hit; stop at the first letter that
    # takes a value." python's -W/-X/-Q take a value but are NOT
    # themselves code execution, so scanning must stop there (the
    # adversarial case is a blocked letter placed AFTER one of those,
    # which must NOT be reached because it's actually part of the
    # value-taking flag's inline value) while a blocked letter placed
    # BEFORE (or with nothing value-consuming before it) is still a hit.
    describe 'short-flag cluster scanning' do
      it 'refuses python -Ic (I is untracked/harmless, c is blocked)' do
        expect { described_class.validate_stdio_args!('python3', ['-Ic', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-c'/)
      end

      it 'refuses python -Bc (B is untracked/harmless, c is blocked)' do
        expect { described_class.validate_stdio_args!('python3', ['-Bc', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-c'/)
      end

      it 'refuses python -uc (u is untracked/harmless, c is blocked)' do
        expect { described_class.validate_stdio_args!('python3', ['-uc', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-c'/)
      end

      it 'refuses python -cprint(1) (attached value form of blocked -c)' do
        expect { described_class.validate_stdio_args!('python3', ['-cprint(1)']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-c'/)
      end

      it 'refuses ruby -we (w is untracked/harmless, e is blocked)' do
        expect { described_class.validate_stdio_args!('ruby', ['-we', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
      end

      it 'refuses ruby -ne (n is untracked/harmless, e is blocked)' do
        expect { described_class.validate_stdio_args!('ruby', ['-ne', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
      end

      it 'refuses ruby -Ce (C is blocked on its own, appearing first in the cluster)' do
        expect { described_class.validate_stdio_args!('ruby', ['-Ce', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-C'/)
      end

      it 'refuses node -ie (i and e both blocked; hit regardless of scan order)' do
        expect { described_class.validate_stdio_args!('node', ['-ie', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError)
      end

      it "stops scanning after a value-only flag, so its VALUE isn't misread as a further blocked letter" do
        # -W is python's warning-control flag (takes a value, not itself
        # code execution); "c" here is -W's value, not a separate -c.
        expect { described_class.validate_stdio_args!('python3', ['-Wc']) }.not_to raise_error
      end
    end

    # IMP-97b6b1185748 item 5 BLOCKER — loader / interactive / stdin forms.
    describe 'loader, interactive and stdin forms' do
      it 'refuses node/bun --loader and --experimental-loader, including the attached = form' do
        %w[node bun].each do |cmd|
          expect { described_class.validate_stdio_args!(cmd, ['--loader', 'evilpkg', 'server.js']) }
            .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '--loader'/)
          expect { described_class.validate_stdio_args!(cmd, ['--experimental-loader=data:text/javascript,1']) }
            .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '--experimental-loader'/)
        end
      end

      it 'refuses node/bun -i and --interactive (REPL entry)' do
        %w[node bun].each do |cmd|
          expect { described_class.validate_stdio_args!(cmd, ['-i']) }
            .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-i'/)
          expect { described_class.validate_stdio_args!(cmd, ['--interactive']) }
            .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '--interactive'/)
        end
      end

      it 'refuses python -i (REPL entry)' do
        expect { described_class.validate_stdio_args!('python3', ['-i']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-i'/)
      end

      it 'refuses python -m code and -m pdb (arbitrary module execution)' do
        expect { described_class.validate_stdio_args!('python3', ['-m', 'code']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /does not name an MCP server module/)
        expect { described_class.validate_stdio_args!('python3', ['-m', 'pdb', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /does not name an MCP server module/)
      end

      it 'refuses a bare "-" (read program from stdin) for node, bun, ruby, python, python3, deno' do
        %w[node bun ruby python python3].each do |cmd|
          expect { described_class.validate_stdio_args!(cmd, ['-']) }
            .to raise_error(McpSecurityService::CommandNotAllowedError, /reads its program from stdin|program from stdin/i),
                "expected #{cmd} '-' to be refused"
        end
        expect { described_class.validate_stdio_args!('deno', ['run', '-']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /program from stdin/i)
      end

      it 'does not refuse "-" as an ordinary attached value inside another arg' do
        # Only an EXACT "-" token is the stdin form; "foo-" or "-x" are not.
        expect { described_class.validate_stdio_args!('node', ['some-file.js']) }.not_to raise_error
      end
    end

    # IMP-97b6b1185748 item 6 SHOULD-FIX — tightened path test (drop the
    # extension heuristic: only a leading /, ./ or ../ counts as a path).
    describe 'tightened path test (no more extension heuristic)' do
      it 'refuses node -r with a bare filename that merely LOOKS like a script (no path prefix)' do
        expect { described_class.validate_stdio_args!('node', ['-r', 'highlight.js', 'server.js']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /loads an arbitrary \(non-path\) module/)
      end

      it 'refuses ruby -r with a bare filename that merely LOOKS like a script (no path prefix)' do
        expect { described_class.validate_stdio_args!('ruby', ['-rfoo.rb', 'server.rb']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /loads an arbitrary \(non-path\) module/)
      end

      it 'still allows a real path with a leading ./, ../ or /' do
        expect { described_class.validate_stdio_args!('node', ['-r', './highlight.js', 'server.js']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('node', ['-r', '../shared/preload.js', 'server.js']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('node', ['-r', '/app/preload.js', 'server.js']) }.not_to raise_error
      end

      it 'refuses ruby -I (load-path widening is refused outright, not path-exempt)' do
        expect { described_class.validate_stdio_args!('ruby', ['-I/tmp', '-revil.rb']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-I'/)
      end
    end

    # IMP-97b6b1185748 item 2 BLOCKER — python -m is refused UNLESS its
    # value looks like an MCP server module (a plain dotted identifier
    # whose name mentions "mcp").
    describe 'python -m is allowed only for MCP server modules' do
      it 'allows python -m <mcp module> in both the separate-arg and attached forms' do
        expect { described_class.validate_stdio_args!('python', ['-m', 'mcp_server_git', '--repository', '/r']) }
          .not_to raise_error
        expect { described_class.validate_stdio_args!('python3', ['-m', 'awslabs.foo_mcp_server']) }
          .not_to raise_error
        expect { described_class.validate_stdio_args!('python3', ['-mmcp_server_git']) }
          .not_to raise_error
      end

      it 'refuses python -m for non-MCP modules, including the attached form' do
        expect { described_class.validate_stdio_args!('python3', ['-m', 'code']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /does not name an MCP server module/)
        expect { described_class.validate_stdio_args!('python3', ['-m', 'pdb']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /does not name an MCP server module/)
        expect { described_class.validate_stdio_args!('python3', ['-m', 'pip']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /does not name an MCP server module/)
        expect { described_class.validate_stdio_args!('python3', ['-m', 'http.server']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /does not name an MCP server module/)
        expect { described_class.validate_stdio_args!('python3', ['-mcode']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /does not name an MCP server module/)
      end
    end

    # IMP-97b6b1185748 item 3 SHOULD-FIX — value-only short flags that were
    # missing, causing false positives (the attached value's letters were
    # misread as further short flags).
    describe 'value-only short flags that must not false-positive' do
      it 'allows ruby -W:no-deprecated (an ATTACHED value — see the optional_value_short specs below for the bare form)' do
        expect { described_class.validate_stdio_args!('ruby', ['-W:no-deprecated', 's.rb']) }.not_to raise_error
      end

      it 'allows ruby -Ke (an ATTACHED value — see the optional_value_short specs below for the bare form)' do
        expect { described_class.validate_stdio_args!('ruby', ['-Ke', 's.rb']) }.not_to raise_error
      end

      it 'allows node -Cdevelopment (C takes a value — --conditions)' do
        expect { described_class.validate_stdio_args!('node', ['-Cdevelopment', 's.js']) }.not_to raise_error
      end
    end

    # IMP-97b6b1185748 round 6 BLOCKER — ruby's -W and -K are
    # optional_value_short, NOT value_only_short: their value, if any,
    # MUST be attached to the same token; a bare occurrence is already a
    # complete flag and never reaches for a separate next arg.
    # Real-spawn-proven regression: `ruby -W -e 'puts 6*7'` and
    # `ruby -K -e 'puts 6*7'` both printed 42 under the round-5 code
    # (value_only_short's "no attached value → assume a separate one"
    # logic swallowed the "-e" that followed).
    describe 'ruby -W/-K take an OPTIONAL, ATTACHED-ONLY value — round 6' do
      it 'refuses a bare -W or -K followed by -e (the value_only_short-era bypass)' do
        expect { described_class.validate_stdio_args!('ruby', ['-W', '-e', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
        expect { described_class.validate_stdio_args!('ruby', ['-K', '-e', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
      end

      it 'still allows the attached forms (-W2, -W:no-deprecated, -Ke) with a following script path' do
        expect { described_class.validate_stdio_args!('ruby', ['-W2', './s.rb']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('ruby', ['-W:no-deprecated', './s.rb']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('ruby', ['-Ke', './s.rb']) }.not_to raise_error
      end
    end

    # IMP-97b6b1185748 round 7 BLOCKER — real-spawn-proven regression: the
    # ATTACHED cluster form still leaked. `ruby -We 'code'`, `ruby -W2e
    # 'code'`, `ruby -Kae 'code'` and `ruby -Kue 'code'` all RAN under the
    # round-6 code, because ruby only consumes PART of the attached text
    # (a ":category", or exactly one digit 0/1/2 for -W; exactly one
    # character for -K) and re-parses the rest of the token as further
    # flags — round 6's optional_value_short treated the WHOLE attached
    # remainder as inert, missing the buried "e". Every case below was
    # checked BY EXECUTION on this host first (see the rule-hash comments
    # for the exact spawn evidence) before being modeled.
    describe 'ruby -W/-K attached-cluster forms that bury a real flag — round 7' do
      it 'refuses -We and -W2e (W consumes at most a ":category" or a single 0/1/2 digit, never more)' do
        expect { described_class.validate_stdio_args!('ruby', ['-We', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
        expect { described_class.validate_stdio_args!('ruby', ['-W2e', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
      end

      it 'refuses -Kae and -Kue (K consumes exactly one character, whatever it is, never more)' do
        expect { described_class.validate_stdio_args!('ruby', ['-Kae', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
        expect { described_class.validate_stdio_args!('ruby', ['-Kue', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
      end

      it 'still refuses the bare forms followed by a separate -e (round 6, unaffected by round 7)' do
        expect { described_class.validate_stdio_args!('ruby', ['-W', '-e', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
        expect { described_class.validate_stdio_args!('ruby', ['-K', '-e', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
      end

      it 'still allows the genuinely inert attached/no-value forms' do
        expect { described_class.validate_stdio_args!('ruby', ['-W2', './s.rb']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('ruby', ['-W:no-deprecated', './s.rb']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('ruby', ['-Ke', './s.rb']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('ruby', ['-Ka', './s.rb']) }.not_to raise_error
      end
    end

    # IMP-97b6b1185748 round 7 tidy-up (verified by execution: python3
    # rejects -Q outright with "Unknown option: -Q") — dropped from
    # python3's value_only_short. 'python' (a real python2 could still
    # accept it) is untouched.
    describe "python3 no longer models -Q (python3 doesn't have it)" do
      it 'still refuses python3 -c regardless — dropping -Q does not weaken anything' do
        expect { described_class.validate_stdio_args!('python3', ['-Qold', '-c', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-c'/)
      end

      it "leaves 'python' (non-3) with -Q still modeled as a separate-value flag" do
        # If -Q were unrecognized, "old" would be mistaken for the first
        # positional and the scan would stop before ever reaching -c.
        expect { described_class.validate_stdio_args!('python', ['-Q', 'old', '-c', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-c'/)
      end
    end

    # IMP-97b6b1185748 round 6 sweep (verified by execution on this host,
    # `ruby -<X> -e 'puts :probe'` for each) — every OTHER ruby short flag
    # this scanner treats specially. All nine are blocked_short (raise
    # unconditionally BEFORE any value is examined), so none of them can
    # actually swallow a subsequent -e/-c the way -W/-K did regardless of
    # their true consumption shape — this just confirms none of them hide
    # the same mistake.
    describe 'ruby short-flag sweep (round 6) — the rest of blocked_short stay correctly blocked' do
      it 'refuses -I, -C and -E, which the sweep confirmed take a mandatory SEPARATE value' do
        expect { described_class.validate_stdio_args!('ruby', ['-I', '-e', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-I'/)
        expect { described_class.validate_stdio_args!('ruby', ['-C', '-e', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-C'/)
        expect { described_class.validate_stdio_args!('ruby', ['-E', '-e', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-E'/)
      end

      it 'refuses -x, -F, -l, -0, -T and -S, which the sweep confirmed take NO separate value' do
        %w[x F l 0 T S].each do |flag|
          expect { described_class.validate_stdio_args!('ruby', ["-#{flag}", '-e', 'x']) }
            .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-#{flag}'/),
                "expected -#{flag} to be refused before -e is ever reached"
        end
      end
    end

    # IMP-97b6b1185748 item 4 — deno subcommand is covered by its own
    # dedicated examples above (see "refuses the deno eval and repl
    # subcommands" and neighboring specs).

    # IMP-97b6b1185748 item 5 BLOCKER — --inspect* prefix, --env-file(-if-exists), --run.
    describe 'node/bun --inspect* and node --env-file/--run' do
      it 'refuses --inspect, --inspect-brk and --inspect-wait, with or without an attached host:port' do
        %w[node bun].each do |cmd|
          expect { described_class.validate_stdio_args!(cmd, ['--inspect', 's.js']) }
            .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '--inspect'/)
          expect { described_class.validate_stdio_args!(cmd, ['--inspect=0.0.0.0:9229', 's.js']) }
            .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '--inspect'/)
          expect { described_class.validate_stdio_args!(cmd, ['--inspect-brk', 's.js']) }
            .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '--inspect-brk'/)
          expect { described_class.validate_stdio_args!(cmd, ['--inspect-wait', 's.js']) }
            .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '--inspect-wait'/)
        end
      end

      it 'refuses node/bun --env-file and --env-file-if-exists' do
        %w[node bun].each do |cmd|
          expect { described_class.validate_stdio_args!(cmd, ['--env-file=/tmp/.env', 's.js']) }
            .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '--env-file'/)
          expect { described_class.validate_stdio_args!(cmd, ['--env-file-if-exists=/tmp/.env', 's.js']) }
            .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '--env-file-if-exists'/)
        end
      end

      it 'refuses node --run, but leaves bun (no --run rule) and node --test untouched' do
        expect { described_class.validate_stdio_args!('node', ['--run', 'build']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '--run'/)
        expect { described_class.validate_stdio_args!('node', ['--test']) }.not_to raise_error
      end
    end

    # IMP-97b6b1185748 item 6 — ruby -S added to blocked_short.
    describe 'ruby -S (search PATH for the script)' do
      it 'refuses ruby -S' do
        expect { described_class.validate_stdio_args!('ruby', ['-S', 'irb']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-S'/)
      end
    end

    # IMP-97b6b1185748 item 8 BLOCKER — stdin device paths, as a bare
    # positional AND as a -r/--import value (both separate-arg and
    # attached forms).
    describe 'stdin device paths (/dev/stdin, /proc/self/fd/0, /dev/fd/0)' do
      it 'refuses a stdin device path used as the script positional' do
        expect { described_class.validate_stdio_args!('python3', ['/dev/stdin']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /program from stdin/i)
        expect { described_class.validate_stdio_args!('node', ['/dev/stdin']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /program from stdin/i)
        expect { described_class.validate_stdio_args!('node', ['/proc/self/fd/0']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /program from stdin/i)
        expect { described_class.validate_stdio_args!('node', ['/dev/fd/0']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /program from stdin/i)
      end

      it 'refuses a stdin device path as the separate-arg value of -r/--import' do
        expect { described_class.validate_stdio_args!('node', ['-r', '/proc/self/fd/0']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError)
        expect { described_class.validate_stdio_args!('node', ['--import', '/dev/stdin']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError)
      end

      it 'refuses a stdin device path as the attached (=) value of --import' do
        expect { described_class.validate_stdio_args!('node', ['--import=/dev/stdin']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /loads an arbitrary \(non-path\) module/)
      end

      # IMP-97b6b1185748 item 3 (round 4): normalized spellings of the same
      # stdin device paths — lexical only (File.expand_path, never
      # File.realpath / touching the filesystem).
      it 'refuses normalized spellings of the same stdin device paths, as a positional' do
        %w[/dev/./stdin //dev/stdin /proc/self/fd//0 /proc/1/fd/0 /dev/fd/../fd/0].each do |value|
          expect { described_class.validate_stdio_args!('node', [value]) }
            .to raise_error(McpSecurityService::CommandNotAllowedError, /program from stdin/i),
                "expected #{value.inspect} to be refused as a stdin device path"
        end
      end

      it 'refuses normalized spellings as a -r separate-arg value' do
        %w[/dev/./stdin //dev/stdin /proc/self/fd//0 /proc/1/fd/0 /dev/fd/../fd/0].each do |value|
          expect { described_class.validate_stdio_args!('node', ['-r', value, 'server.js']) }
            .to raise_error(McpSecurityService::CommandNotAllowedError),
                "expected -r #{value.inspect} to be refused"
        end
      end

      it 'refuses normalized spellings as the attached (=) value of --import' do
        %w[/dev/./stdin //dev/stdin /proc/self/fd//0 /proc/1/fd/0 /dev/fd/../fd/0].each do |value|
          expect { described_class.validate_stdio_args!('node', ["--import=#{value}"]) }
            .to raise_error(McpSecurityService::CommandNotAllowedError, /loads an arbitrary \(non-path\) module/),
                "expected --import=#{value} to be refused"
        end
      end
    end

    # IMP-97b6b1185748 item 1 (round 4): flags only get checked BEFORE the
    # interpreter's own first positional (script/module target) — anything
    # after belongs to the target program, e.g. a real MCP server's own
    # `-p 3000`/`--repository foo`/`-e` (a hypothetical server flag, not
    # node's eval flag) must not be misread as an inline-code flag.
    describe 'flags stop being checked once the first positional is reached' do
      it 'allows ordinary program flags that appear AFTER the script path' do
        expect { described_class.validate_stdio_args!('node', ['s.js', '-e', 'foo']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('node', ['dist/index.js', '-p', '3000']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('ruby', ['server.rb', '-e', 'x']) }.not_to raise_error
      end

      it 'still refuses the same flags when they appear BEFORE the script path' do
        expect { described_class.validate_stdio_args!('node', ['-e', 'x', 's.js']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
      end

      it "treats python's -m target as ending option parsing, same as real python does" do
        expect { described_class.validate_stdio_args!('python', ['-m', 'mcp_x', '-c', 'conf.yaml']) }
          .not_to raise_error
      end

      it 'still refuses -c appearing BEFORE -m (real python option parsing has not ended yet)' do
        expect { described_class.validate_stdio_args!('python3', ['-c', 'x', '-m', 'mcp_x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-c'/)
      end

      it 'leaves npx scanning every arg regardless of position (conservative, unchanged)' do
        expect { described_class.validate_stdio_args!('npx', ['some-pkg', '-c', 'id']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-c'/)
      end
    end

    # IMP-97b6b1185748 item 1 (round 5 BLOCKER — real-spawn-proven
    # regression from round 4): an unrecognized bare long flag (no "=")
    # was silently assumed to be boolean, so its SEPARATE next-arg value
    # was wrongly treated as "the first positional" — stopping the scan
    # one token early and hiding a real inline-code flag right after it.
    # Proven with real spawns: `node --title x -e 'console.log(6*7)'`
    # printed 42 under the round-4 code. Fail-closed fix: any such flag
    # makes the WHOLE scan ambiguous, and ambiguous means scan every
    # remaining token, exactly like round 3, never "guess it's boolean".
    describe 'an unrecognized bare long flag disables early-stop (fail-closed, round 5)' do
      it 'refuses every separate-value long-flag bypass vector (probe97d)' do
        cases = {
          'node' => [
            %w[--title foo -e x],
            %w[--conditions c -e x],
            %w[--input-type module -e x],
            %w[--unhandled-rejections strict -e x],
            %w[--dns-result-order ipv4first -e x]
          ],
          'ruby' => [
            %w[--encoding utf-8 -e x],
            %w[--backtrace-limit 3 -e x],
            %w[--enable frozen-string-literal -e x]
          ]
        }
        cases.each do |cmd, arg_sets|
          arg_sets.each do |args|
            expect { described_class.validate_stdio_args!(cmd, args) }
              .to raise_error(McpSecurityService::CommandNotAllowedError),
                  "expected #{cmd} #{args.inspect} to be refused"
          end
        end

        expect { described_class.validate_stdio_args!('python3', %w[--check-hash-based-pycs always -c x]) }
          .to raise_error(McpSecurityService::CommandNotAllowedError)
      end

      it 'refuses regardless of whether the swallowed value looks like a path or a script name' do
        expect { described_class.validate_stdio_args!('node', ['--title', '/a', '-e', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
        expect { described_class.validate_stdio_args!('node', ['--title', 'x.js', '-e', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
      end

      it 'does not affect KNOWN value-taking flags, which stay fully understood' do
        expect { described_class.validate_stdio_args!('node', ['--require', './a.js', '-e', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
        expect { described_class.validate_stdio_args!('node', ['-r', './a.js', '-e', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
        expect { described_class.validate_stdio_args!('node', ['-C', 'x', '-e', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
        expect { described_class.validate_stdio_args!('ruby', ['-Ke', '-e', 'x']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-e'/)
      end

      it 'an attached "--flag=value" form is self-contained and never ambiguous' do
        expect { described_class.validate_stdio_args!('node', ['dist/index.js', '-p', '3000']) }
          .not_to raise_error
      end

      it "an explicit '--' unconditionally ends interpreter option parsing (POSIX convention)" do
        expect { described_class.validate_stdio_args!('node', ['--', '-e', 'x']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('node', ['--', 's.js', '-e']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('python3', ['--', '-c', 'x']) }.not_to raise_error
      end

      it 'still allows legitimate MCP server invocations unaffected by any ambiguous flag' do
        expect { described_class.validate_stdio_args!('node', ['dist/index.js', '-e', 'foo']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('node', ['./server.js', '--port', '3000']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('node', ['s.js', '-p', '3000']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('python', ['-m', 'mcp_x', '-c', 'conf.yaml']) }
          .not_to raise_error
        expect { described_class.validate_stdio_args!('ruby', ['server.rb', '-e', 'x']) }.not_to raise_error
      end

      it 'refuses an unmodeled boolean-looking long flag rather than assume it is safe (acceptable over-blocking)' do
        # --enable-source-maps is a real, harmless node boolean flag we
        # deliberately do NOT add to node's (currently empty) boolean_long
        # list — keeping that list minimal means this legitimate-but-
        # unmodeled case is refused rather than risk under-modeling a
        # value-taking flag as boolean again.
        expect { described_class.validate_stdio_args!('node', ['--enable-source-maps', 'dist/index.js', '-p', '3000']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /Inline-code flag '-p'/)
      end
    end

    # IMP-97b6b1185748 item 2 (round 4): `bun run <x>` / bare `bun <x>`
    # look up a package.json script by name and run it through the shell
    # when `x` isn't a real file.
    describe 'bun run / bare bun refuses a non-path target (package.json script lookup)' do
      it 'refuses bun run <name> and bare bun <name> when the target is not a path' do
        expect { described_class.validate_stdio_args!('bun', ['run', 'build']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /package\.json script/)
        expect { described_class.validate_stdio_args!('bun', ['build']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /package\.json script/)
      end

      it 'allows bun run <path> and bare bun <path>' do
        expect { described_class.validate_stdio_args!('bun', ['run', './server.js']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('bun', ['./server.js']) }.not_to raise_error
        expect { described_class.validate_stdio_args!('bun', ['run', '/app/server.js']) }.not_to raise_error
      end

      it 'still allows bun x <pkg> (the package runner, launcher-by-design)' do
        expect { described_class.validate_stdio_args!('bun', ['x', 'some-package']) }.not_to raise_error
      end

      # IMP-97b6b1185748 item 2 follow-up (round 5): an unrecognized flag
      # ahead of the real subcommand must not let its VALUE ("x", here)
      # coincidentally match bun's launcher-exempt "x" subcommand token.
      it "refuses when an unrecognized flag precedes the target, rather than trust a coincidental 'x' match" do
        expect { described_class.validate_stdio_args!('bun', ['--cwd', 'x', 'run', 'build']) }
          .to raise_error(McpSecurityService::CommandNotAllowedError, /cannot be confirmed/)
      end
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
