# frozen_string_literal: true

require 'rails_helper'

# IMP-2c760325c102 (MCP isolation Phase 1 T4) — package-launcher pinning.
# A stdio MCP server whose command is a package LAUNCHER (npx, bun x, uvx /
# uv tool run, uv run --with, pipx run, deno npm:/jsr: specifiers) resolves
# "whatever the registry serves right now" at spawn time unless the package
# is pinned to an EXACT version. This spec is the grammar: what counts as
# pinned, what is refused, and that the refusal reaches both the spawn-time
# gate (#validate_stdio_server!) and the save-time gate this app's McpServer model
# uses (#package_pin_violation). The worker's McpSecurityService runs the
# IDENTICAL table in worker/spec/services/mcp_security_service_package_pinning_spec.rb
# and the parity spec pins the two implementations together.
RSpec.describe Mcp::SecurityService, 'package-launcher pinning' do
  PIN_EXT = { 'allow_extended_commands' => true }.freeze

  # [name, command, args, capabilities]
  PIN_ACCEPTED = [
    [ 'npx -y name@exact', 'npx', %w[-y pkg@1.2.3], {} ],
    [ 'npx -y scoped@exact with package args', 'npx', %w[-y @modelcontextprotocol/server-filesystem@2026.8.31 /tmp --verbose], {} ],
    [ 'npx -y -- scoped@exact (end of options)', 'npx', %w[-y -- @scope/pkg@1.2.3], {} ],
    [ 'npx prerelease+build is still exact', 'npx', %w[--yes --quiet pkg@1.2.3-beta.1+build.5], {} ],
    [ 'npx -p pinned selector then a bin name', 'npx', %w[-p pkg@1.2.3 some-bin --arg], {} ],
    [ 'npx --package= pinned selector', 'npx', %w[--package=@scope/pkg@1.2.3 some-bin], {} ],
    [ 'npx flags after the positional belong to the package', 'npx', %w[pkg@1.2.3 -p other --registry x], {} ],
    [ 'npx in the command string', 'npx -y pkg@1.2.3', [], {} ],
    [ 'bun x name@exact', 'bun', %w[x pkg@1.2.3], {} ],
    [ 'bun x --bun scoped@exact', 'bun', %w[x --bun @scope/pkg@1.2.3 arg], {} ],
    [ 'bun x -b name@exact', 'bun', %w[x -b pkg@1.2.3], {} ],
    [ 'uvx name==exact', 'uvx', %w[mcp-server-fetch==2026.8.18], PIN_EXT ],
    [ 'uvx name@exact (uv shorthand)', 'uvx', %w[mcp-server-fetch@2026.8.18 --arg], PIN_EXT ],
    [ 'uvx --from pinned then a command', 'uvx', %w[--from mcp-server-git==2026.8.18 mcp-server-git --repository /r], PIN_EXT ],
    [ 'uvx --with pinned plus pinned positional', 'uvx', %w[--with requests==2.32.3 pkg==1.0.0], PIN_EXT ],
    [ 'uvx --with comma list all pinned', 'uvx', %w[--with a==1.0.0,b==2.0.0 pkg==1.0], PIN_EXT ],
    [ 'uvx boolean and value options before the package', 'uvx', %w[-q --python 3.12 --no-cache pkg==1.0.0], PIN_EXT ],
    [ 'uvx --python= attached value', 'uvx', %w[--python=3.12 pkg==1.0.0], PIN_EXT ],
    [ 'uvx extras keep the pin', 'uvx', %w[pkg[extra]==1.0.0], PIN_EXT ],
    [ 'uvx PEP 440 pre/post/dev/epoch exact forms', 'uvx', %w[pkg==1!2.0rc1.post1.dev2], PIN_EXT ],
    [ 'uv tool run name==exact', 'uv', %w[tool run pkg==1.0.0], PIN_EXT ],
    [ 'uv run --with pinned', 'uv', %w[run --with pkg==1.0.0 ./server.py], PIN_EXT ],
    [ 'uv run args after the script belong to the script', 'uv', %w[run ./server.py --with foo], PIN_EXT ],
    [ 'uv run -m module (no package)', 'uv', %w[run -m mcp_server_git], PIN_EXT ],
    [ 'uv run --no-project script', 'uv', %w[run --no-project ./server.py], PIN_EXT ],
    [ 'uv non-launcher subcommand is not this rule\'s concern', 'uv', %w[pip install x], PIN_EXT ],
    [ 'pipx run name==exact', 'pipx', %w[run pkg==1.0.0 --arg], PIN_EXT ],
    [ 'pipx run --spec pinned then an app name', 'pipx', %w[run --spec pkg==1.0.0 app], PIN_EXT ],
    [ 'pipx run --preinstall pinned', 'pipx', %w[run --preinstall other==2.0.0 pkg==1.0.0], PIN_EXT ],
    [ 'pipx non-run subcommand is not this rule\'s concern', 'pipx', %w[list], PIN_EXT ],
    [ 'deno run npm: scoped@exact', 'deno', %w[run -A npm:@scope/pkg@1.2.3], {} ],
    [ 'deno run npm:name@exact/subpath', 'deno', %w[run npm:pkg@1.2.3/cli.js], {} ],
    [ 'deno run jsr:@scope/name@exact', 'deno', %w[run jsr:@scope/pkg@1.2.3], {} ],
    [ 'deno run a local script', 'deno', %w[run -A server.ts], {} ],
    [ 'node is not a launcher', 'node', %w[dist/index.js], {} ],
    [ 'python -m is not a launcher', 'python', %w[-m mcp_server_git], {} ],
[ 'uv run path-like script', 'uv', %w[run ./server.py], PIN_EXT ],
[ 'uvx --python version only', 'uvx', %w[--python=3.12.1 pkg==1.0.0], PIN_EXT ],
[ 'pipx run -p version only', 'pipx', %w[run -p 3.12 pkg==1.0.0], PIN_EXT ],
[ 'npx selector with a bin name after --', 'npx', %w[-p pkg@1.2.3 -- some-bin], {} ],
[ 'deno run --preload= pinned npm specifier', 'deno', %w[run --preload=npm:pkg@1.2.3 ./s.ts], {} ],
    [ 'deno run a remote URL script - out of this rule, documented', 'deno', %w[run https://deno.land/x/pkg/mod.ts], {} ],
[ 'node a real script path', 'node', %w[./dist/index.js], {} ],
[ 'node an absolute script path', 'node', %w[/opt/app/server.js --port 3000], {} ],
[ 'ruby a real script', 'ruby', %w[./mcp_server.rb], {} ]
  ].freeze

  # [name, command, args, capabilities, message fragment]
  PIN_REFUSED = [
    [ 'npx -y bare name', 'npx', %w[-y pkg], {}, /not pinned to an exact version/ ],
    [ 'npx -y bare scoped name', 'npx', %w[-y @modelcontextprotocol/server-filesystem /tmp], {}, /not pinned/ ],
    [ 'npx @latest dist-tag', 'npx', %w[-y pkg@latest], {}, /not pinned/ ],
    [ 'npx @next dist-tag', 'npx', %w[-y pkg@next], {}, /not pinned/ ],
    [ 'npx caret range', 'npx', %w[-y pkg@^1.2.3], {}, /not pinned/ ],
    [ 'npx tilde range', 'npx', %w[-y pkg@~1.2], {}, /not pinned/ ],
    # ">" is a shell metacharacter, refused by the earlier argv rule before pinning is even consulted.
    [ %q(npx >= range), %q(npx), %w[-y pkg@>=1], {}, nil ],
    [ 'npx x-range', 'npx', %w[-y pkg@1.2.x], {}, /not pinned/ ],
    [ 'npx star', 'npx', %w[-y pkg@*], {}, /not pinned/ ],
    [ 'npx incomplete version', 'npx', %w[-y pkg@1.2], {}, /not pinned/ ],
    [ 'npx v-prefixed version', 'npx', %w[-y pkg@v1.2.3], {}, /not pinned/ ],
    [ 'npx =-prefixed version', 'npx', %w[-y pkg@=1.2.3], {}, /not pinned/ ],
    [ 'npx leading-zero component', 'npx', %w[-y pkg@01.2.3], {}, /not pinned/ ],
    [ 'npx github: spec', 'npx', %w[-y github:user/repo], {}, /not pinned/ ],
    [ 'npx user/repo shorthand', 'npx', %w[-y user/repo], {}, /not pinned/ ],
    [ 'npx git+https spec', 'npx', %w[-y git+https://github.com/u/r.git], {}, /not pinned/ ],
    [ 'npx tarball URL', 'npx', %w[-y https://example.com/pkg.tgz], {}, /not pinned/ ],
    [ 'npx file: spec', 'npx', %w[-y file:../pkg], {}, /not pinned/ ],
    [ 'npx relative path', 'npx', %w[-y ./pkg], {}, /not pinned/ ],
    [ 'npx absolute path', 'npx', %w[-y /opt/pkg], {}, /not pinned/ ],
    [ 'npx npm: alias', 'npx', %w[-y npm:alias@1.2.3], {}, /not pinned/ ],
    [ 'npx smuggled second @', 'npx', %w[-y pkg@1.2.3@latest], {}, /not pinned/ ],
    [ 'npx uppercase name', 'npx', %w[-y PKG@1.2.3], {}, /not pinned/ ],
    [ 'npx -p unpinned selector', 'npx', %w[-p pkg cmd], {}, /not pinned/ ],
    [ 'npx second -p unpinned', 'npx', %w[-p pkg@1.2.3 -p other cmd], {}, /not pinned/ ],
    [ 'npx --package without a value', 'npx', %w[-y --package], {}, /needs a package spec/ ],
    [ 'npx --registry before the package (registry steering)', 'npx', %w[--registry=https://evil.example pkg@1.2.3], {}, /option "--registry=https:\/\/evil.example" is not allowed/ ],
    [ 'npx unknown option before the package', 'npx', %w[--userconfig /tmp/npmrc pkg@1.2.3], {}, /is not allowed before the package/ ],
    [ 'npx short cluster', 'npx', %w[-yp pkg@1.2.3], {}, /is not allowed before the package/ ],
    [ 'npx with no package at all', 'npx', [], {}, /no package was given/ ],
    [ 'npx -y with no package', 'npx', %w[-y], {}, /no package was given/ ],
    [ 'npx unpinned in the command string', 'npx -y pkg', [], {}, /not pinned/ ],
    [ 'bun x bare name', 'bun', %w[x pkg], {}, /not pinned/ ],
    [ 'bun x @latest', 'bun', %w[x pkg@latest], {}, /not pinned/ ],
    [ 'bun x unknown option', 'bun', %w[x --unknown pkg@1.2.3], {}, /is not allowed before the package/ ],
    [ 'bun x with no package', 'bun', %w[x], {}, /no package was given/ ],
    [ 'uvx bare name', 'uvx', %w[mcp-server-fetch], PIN_EXT, /not pinned to an exact version/ ],
    [ %q(uvx >= range), %q(uvx), %w[pkg>=1], PIN_EXT, nil ],
    [ 'uvx compatible-release range', 'uvx', %w[pkg~=1.0], PIN_EXT, /not pinned/ ],
    [ 'uvx wildcard', 'uvx', %w[pkg==1.*], PIN_EXT, /not pinned/ ],
    [ 'uvx arbitrary equality', 'uvx', %w[pkg===1.0.0], PIN_EXT, /not pinned/ ],
    [ 'uvx --from unpinned', 'uvx', %w[--from pkg cmd], PIN_EXT, /not pinned/ ],
    [ 'uvx --with unpinned', 'uvx', %w[--with pkg x==1.0.0], PIN_EXT, /not pinned/ ],
    [ 'uvx --with comma list with one unpinned', 'uvx', %w[--with a==1.0.0,b x==1.0], PIN_EXT, /not pinned/ ],
    [ 'uvx --index-url (index steering)', 'uvx', %w[--index-url https://evil.example pkg==1.0.0], PIN_EXT, /is not allowed before the package/ ],
    [ 'uvx -i (index steering)', 'uvx', %w[-i https://evil.example pkg==1.0.0], PIN_EXT, /is not allowed before the package/ ],
    [ 'uvx --with-requirements (unverifiable file)', 'uvx', %w[--with-requirements r.txt pkg==1.0.0], PIN_EXT, /is not allowed before the package/ ],
    [ 'uvx git+ spec', 'uvx', %w[git+https://github.com/u/r.git], PIN_EXT, /not pinned/ ],
    [ 'uvx local path', 'uvx', %w[./pkg], PIN_EXT, /not pinned/ ],
    [ 'uvx wheel URL', 'uvx', %w[https://example.com/pkg.whl], PIN_EXT, /not pinned/ ],
    [ 'uv tool run bare name', 'uv', %w[tool run pkg], PIN_EXT, /not pinned/ ],
    [ 'uv run --with unpinned', 'uv', %w[run --with pkg ./server.py], PIN_EXT, /not pinned/ ],
    [ 'uv run --with-requirements', 'uv', %w[run --with-requirements r.txt ./server.py], PIN_EXT, /is not allowed before the (script|package)/ ],
    [ 'uv run --index-url', 'uv', %w[run --index-url https://evil.example ./server.py], PIN_EXT, /is not allowed before the (script|package)/ ],
    [ 'uv run unknown option', 'uv', %w[run --unknown-opt ./server.py], PIN_EXT, /is not allowed before the (script|package)/ ],
    [ 'pipx run bare name', 'pipx', %w[run pkg], PIN_EXT, /not pinned/ ],
    [ 'pipx run --spec unpinned', 'pipx', %w[run --spec pkg app], PIN_EXT, /not pinned/ ],
    [ 'pipx run --pip-args (index steering)', 'pipx', %w[run --pip-args=--index-url=https://evil.example pkg==1.0.0], PIN_EXT, /is not allowed before the package/ ],
    [ 'pipx run --path', 'pipx', %w[run --path ./x], PIN_EXT, /is not allowed before the package/ ],
    [ 'pipx run --editable', 'pipx', %w[run -e ./x], PIN_EXT, /is not allowed before the package/ ],
    [ 'pipx run --index-url', 'pipx', %w[run --index-url https://evil.example pkg==1.0.0], PIN_EXT, /is not allowed before the package/ ],
    [ 'pipx run --preinstall unpinned', 'pipx', %w[run --preinstall other pkg==1.0.0], PIN_EXT, /not pinned/ ],
    [ 'deno run npm: bare name', 'deno', %w[run -A npm:pkg], {}, /not pinned/ ],
    [ 'deno run npm:@latest', 'deno', %w[run npm:pkg@latest], {}, /not pinned/ ],
    [ 'deno run jsr: bare name', 'deno', %w[run jsr:@scope/pkg], {}, /not pinned/ ],
    [ 'deno npm: specifier anywhere in argv', 'deno', %w[run --config c.json npm:pkg], {}, /not pinned/ ],
    [ 'deno serve npm: bare name', 'deno', %w[serve npm:pkg], {}, /not pinned/ ],
# Interpreter-script bypass (round 1 blocker 1': a package manager run THROUGH its interpreter.
[ 'node npx-cli.js', 'node', %w[/usr/local/lib/node_modules/npm/bin/npx-cli.js -y evil-pkg], {}, /package manager entry point/ ],
[ 'node npm-cli.js exec', 'node', %w[./npm-cli.js exec --yes -- evil-pkg], {}, /package manager entry point/ ],
[ 'node bare npm', 'node', %w[npm exec evil-pkg], {}, /package manager entry point/ ],
[ 'node yarn under node_modules', 'node', %w[/opt/x/node_modules/yarn/bin/yarn.js dlx evil], {}, /package manager entry point/ ],
[ 'node -r npm-cli.js preload', 'node', %w[-r /usr/lib/node_modules/npm/bin/npm-cli.js ./server.js], {}, /package manager entry point/ ],
[ 'node ambiguous flags then npx-cli.js', 'node', %w[--title x /opt/npx-cli.js], {}, /package manager entry point/ ],
[ 'ruby gem install', 'ruby', %w[/usr/local/bin/gem install evil-gem], {}, /package manager entry point/ ],
[ 'ruby bundle', 'ruby', %w[/usr/bin/bundle exec evil], {}, /package manager entry point/ ],
[ 'python pip script', 'python3', %w[/usr/bin/pip install evil], {}, /package manager entry point/ ],
[ 'python uv script', 'python3', %w[./uv tool run evil], {}, /package manager entry point/ ],
[ 'deno run npm-cli.js', 'deno', %w[run -A /usr/lib/node_modules/npm/bin/npm-cli.js exec evil], {}, /package manager entry point/ ],
[ 'bun run npx-cli.js', 'bun', %w[run /usr/lib/node_modules/npm/bin/npx-cli.js evil], {}, /package manager entry point/ ],
# Global option before the subcommand (round 1 blocker 2'.
[ 'uv -q tool run', 'uv', %w[-q tool run pkg==1.0.0], PIN_EXT, /global option/ ],
[ 'uv --quiet run --with', 'uv', %w[--quiet run --with pkg==1.0.0 ./s.py], PIN_EXT, /global option/ ],
[ 'pipx --quiet run', 'pipx', %w[--quiet run pkg==1.0.0], PIN_EXT, /global option/ ],
# Dropped pre-package value options and the python version rule (round 1 item 5'.
[ 'uvx --config-file', 'uvx', %w[--config-file /tmp/uv.toml pkg==1.0.0], PIN_EXT, /is not allowed before the package/ ],
[ 'uvx --project', 'uvx', %w[--project /tmp/p pkg==1.0.0], PIN_EXT, /is not allowed before the package/ ],
[ 'uvx --directory', 'uvx', %w[--directory /tmp pkg==1.0.0], PIN_EXT, /is not allowed before the package/ ],
[ 'uvx --cache-dir', 'uvx', %w[--cache-dir /tmp/c pkg==1.0.0], PIN_EXT, /is not allowed before the package/ ],
[ 'uv run --cache-dir', 'uv', %w[run --cache-dir /tmp/c ./s.py], PIN_EXT, /is not allowed before the script/ ],
[ 'uvx --python path', 'uvx', %w[--python /tmp/evil-python pkg==1.0.0], PIN_EXT, /python version/ ],
[ 'uvx -p name', 'uvx', %w[-p pypy3 pkg==1.0.0], PIN_EXT, /python version/ ],
[ 'pipx run --python path', 'pipx', %w[run --python /usr/bin/python3 pkg==1.0.0], PIN_EXT, /python version/ ],
# uv run positional must be a local path (round 1 item 5'.
[ 'uv run bare script name', 'uv', %w[run server.py], PIN_EXT, /local path/ ],
[ 'uv run URL', 'uv', %w[run https://example.com/s.py], PIN_EXT, /local path/ ],
[ 'uv run bare interpreter', 'uv', %w[run python ./s.py], PIN_EXT, /local path/ ],
# deno attached flag values (round 1 item 6'.
[ 'deno --preload= unpinned npm', 'deno', %w[run --preload=npm:pkg ./s.ts], {}, /not pinned/ ],
[ 'deno --import-map= remote URL', 'deno', %w[run --import-map=https://evil.example/map.json ./s.ts], {}, /remote URL/ ],
[ 'deno --config= remote URL', 'deno', %w[run --config=http://evil.example/deno.json ./s.ts], {}, /remote URL/ ],
[ 'deno --import-map= data: URL', 'deno', %w[run --import-map=data:application/json,{} ./s.ts], {}, /data: URL/ ],
# npx selector positional must be a bin name (round 1 item 7'.
[ 'npx selector then a path', 'npx', %w[-p pkg@1.2.3 ./x], {}, /bin name/ ],
[ 'npx selector then uppercase', 'npx', %w[-p pkg@1.2.3 Bin], {}, /bin name/ ]
  ].freeze

  def self.server_hash(command, args, capabilities)
    { 'command' => command, 'args' => args, 'env' => {}, 'capabilities' => capabilities }
  end

  describe '.validate_stdio_server! (spawn-time gate)' do
    PIN_ACCEPTED.each do |name, command, args, capabilities|
      it "accepts: #{name}" do
        expect { described_class.validate_stdio_server!(self.class.server_hash(command, args, capabilities)) }
          .not_to raise_error
      end
    end

    PIN_REFUSED.each do |name, command, args, capabilities, fragment|
      it "refuses: #{name}" do
        matcher = fragment ? [ described_class::CommandNotAllowedError, fragment ] : [ described_class::CommandNotAllowedError ]
        expect { described_class.validate_stdio_server!(self.class.server_hash(command, args, capabilities)) }
          .to raise_error(*matcher)
      end
    end

    it 'the refusal names the launcher, the offending spec and the exact-version shape to use' do
      expect { described_class.validate_stdio_server!(self.class.server_hash('npx', %w[-y @scope/pkg], {})) }
        .to raise_error(described_class::CommandNotAllowedError,
                        /npx: package "@scope\/pkg" is not pinned to an exact version.*@scope\/pkg@<major>\.<minor>\.<patch>/)
    end

    it 'is independent of the native-execution hatch — an approved native server with an unpinned package is still refused' do
      server = self.class.server_hash('npx', %w[-y pkg], { 'native_execution_approved' => true })
      expect { described_class.validate_stdio_server!(server) }
        .to raise_error(described_class::CommandNotAllowedError, /not pinned/)
    end

    it 'runs AFTER the inline-code rules, so npx -c is still refused as inline code, not as an unpinned package' do
      expect { described_class.validate_stdio_server!(self.class.server_hash('npx', %w[-c id], {})) }
        .to raise_error(described_class::CommandNotAllowedError, /not allowed/) { |e| expect(e.message).not_to match(/pinned/) }
    end
  end

  # The server-side refusal audit (#record_spawn_refusal_audit): a real
  # AuditLog row, written directly, for a hash that carries the server's
  # id and owning account — exactly what Mcp::PromptService/ResourceService/
  # SyncExecutionService now build. Every other example in this file runs
  # with no id/account and must leave the audit log untouched.
  describe 'refusal audit (server side)' do
    let(:account) { create(:account) }
    let(:mcp_server) { create(:mcp_server, account: account, command: 'node', args: [ 'server.js' ]) }

    def attributed_server(args)
      { 'id' => mcp_server.id, 'account_id' => account.id, 'command' => 'npx', 'args' => args, 'env' => {}, 'capabilities' => {} }
    end

    it 'writes an mcp.servers.spawn_refused row with the launcher, arg count, offending index and rule — never argv or the message' do
      expect {
        expect { described_class.validate_stdio_server!(attributed_server(%w[-y pkg --token=super-secret-arg])) }
          .to raise_error(described_class::CommandNotAllowedError, /not pinned/)
      }.to change { AuditLog.where(action: 'mcp.servers.spawn_refused', resource_id: mcp_server.id).count }.by(1)

      row = AuditLog.where(action: 'mcp.servers.spawn_refused', resource_id: mcp_server.id).last
      expect(row.account_id).to eq(account.id)
      expect(row.resource_type).to eq('McpServer')
      expect(row.user_id).to be_nil
      expect(row.severity).to eq('medium')
      expect(row.metadata).to include(
        'launcher' => 'npx', 'arg_count' => 3, 'arg_index' => 1, 'rule' => 'package_pin',
        'error_class' => 'CommandNotAllowedError', 'stage' => 'server_validation'
      )
      expect(row.metadata.keys).not_to include('message', 'command', 'args')
      expect(row.metadata.to_json).not_to include('super-secret')
    end

    it 'writes a row for an environment refusal too, naming the forbidden KEY only' do
      server = attributed_server(%w[-y pkg@1.2.3]).merge('env' => { 'LD_PRELOAD' => '/tmp/evil.so' })

      expect {
        expect { described_class.validate_stdio_server!(server) }.to raise_error(described_class::EnvironmentViolationError)
      }.to change { AuditLog.where(action: 'mcp.servers.spawn_refused', resource_id: mcp_server.id).count }.by(1)

      expect(AuditLog.where(action: 'mcp.servers.spawn_refused').last.metadata['error_class']).to eq('EnvironmentViolationError')
    end

    it 'writes nothing for an accepted server' do
      expect { described_class.validate_stdio_server!(attributed_server(%w[-y pkg@1.2.3])) }
        .not_to change(AuditLog, :count)
    end

    it 'skips the row (and still refuses) when the hash carries no account to attach it to' do
      expect {
        expect { described_class.validate_stdio_server!(attributed_server(%w[-y pkg]).except('account_id')) }
          .to raise_error(described_class::CommandNotAllowedError, /not pinned/)
      }.not_to change(AuditLog, :count)
    end
  end


  describe 'structured refusals (what the audit log stores instead of argv)' do
    it 'an unpinned package carries rule and the offending argv index' do
      expect { described_class.validate_stdio_server!(self.class.server_hash('npx', %w[-y pkg], {})) }
        .to raise_error(described_class::CommandNotAllowedError) { |e|
          expect(e.rule).to eq('package_pin')
          expect(e.arg_index).to eq(1)
        }
    end

    it 'an index counts command-string tokens too, since they are part of the resolved argv' do
      expect { described_class.validate_stdio_server!(self.class.server_hash('npx -y', %w[--with x pkg], {})) }
        .to raise_error(described_class::CommandNotAllowedError) { |e|
          expect(e.rule).to eq('launcher_option')
          expect(e.arg_index).to eq(1)
        }
    end

    it 'a package manager entry point names its rule and index' do
      expect { described_class.validate_stdio_server!(self.class.server_hash('ruby', %w[/usr/local/bin/gem install x], {})) }
        .to raise_error(described_class::CommandNotAllowedError) { |e|
          expect(e.rule).to eq('package_manager_entry')
          expect(e.arg_index).to eq(0)
        }
    end

    it 'a refusal from the pre-existing rules has no rule name, only its class' do
      expect { described_class.validate_stdio_server!(self.class.server_hash('node', %w[-e x], {})) }
        .to raise_error(described_class::CommandNotAllowedError) { |e| expect(e.rule).to be_nil }
    end
  end

  describe 'forbidden configuration-steering env for launchers' do
    it 'does not also list XDG_CONFIG_HOME as allowed (round 2 item 6)' do
      expect(described_class::ALLOWED_ENV_VARS).not_to include('XDG_CONFIG_HOME')
    end

    it 'refuses UV_CONFIG_FILE and XDG_CONFIG_HOME, naming the KEY only' do
      %w[UV_CONFIG_FILE XDG_CONFIG_HOME].each do |key|
        server = self.class.server_hash('uvx', %w[pkg==1.0.0], PIN_EXT).merge('env' => { key => '/tmp/secret-config' })
        expect { described_class.validate_stdio_server!(server) }
          .to raise_error(described_class::EnvironmentViolationError, /#{key}/) { |e| expect(e.message).not_to include('secret-config') }
      end
    end
  end

  describe '.package_pin_violation also refuses a package manager entry point (save-time parity with spawn time)' do
    it 'returns the refusal for node running npx-cli.js' do
      expect(described_class.package_pin_violation('node', %w[/usr/local/lib/node_modules/npm/bin/npx-cli.js -y evil]))
        .to match(/package manager entry point/)
    end

    it 'returns nil for a real script' do
      expect(described_class.package_pin_violation('node', %w[./dist/index.js])).to be_nil
    end

    it 'leaves the inline-code rule to spawn time (an -e script is not a save-time violation)' do
      expect(described_class.package_pin_violation('node', %w[-e console.log(1)])).to be_nil
    end

    it 'still checks every non-option token when an inline-code flag makes the positional ambiguous' do
      expect(described_class.package_pin_violation('node', %w[-e x /usr/local/lib/node_modules/npm/bin/npm-cli.js]))
        .to match(/package manager entry point/)
    end
  end

  describe '.package_pin_violation (save-time gate used by the server model)' do
    it 'returns nil for a pinned launcher invocation' do
      expect(described_class.package_pin_violation('npx', %w[-y pkg@1.2.3])).to be_nil
    end

    it 'returns nil for a non-launcher command' do
      expect(described_class.package_pin_violation('node', %w[server.js])).to be_nil
    end

    it 'returns the refusal message for an unpinned launcher invocation' do
      expect(described_class.package_pin_violation('npx', %w[-y pkg])).to match(/not pinned to an exact version/)
    end

    it 'applies to launcher tokens inside the command string too' do
      expect(described_class.package_pin_violation('npx -y pkg', [])).to match(/not pinned/)
      expect(described_class.package_pin_violation('npx -y pkg@1.2.3', [])).to be_nil
    end

    it 'surfaces an unparseable command string as a violation instead of raising' do
      expect(described_class.package_pin_violation("npx -y 'pkg", [])).to match(/unparseable/)
    end

    it 'treats a blank command as no violation (presence is validated elsewhere)' do
      expect(described_class.package_pin_violation(nil, [])).to be_nil
      expect(described_class.package_pin_violation('', [])).to be_nil
    end

    it 'does not require allow_extended_commands to evaluate an extended launcher' do
      expect(described_class.package_pin_violation('uvx', %w[pkg])).to match(/not pinned/)
    end
  end

  # Round 2 — the package-manager-entry denylist as a TABLE of (executable
  # argv position) x (entry-point shape), asserted on BOTH faces in one
  # example so save and spawn can never again disagree on a position. The
  # positions are generated from the rule tables (every path-taking flag of
  # every stop-at-first-positional interpreter, separate and attached, the
  # first positional, the token after "--"); the launcher positions (deno,
  # bun run, uv run) are hand-listed because their grammars are not
  # table-driven. A benign script in every position is the control.
  ENTRY_POINTS = [
    [ 'npx-cli.js under npm/', '/usr/local/lib/node_modules/npm/bin/npx-cli.js' ],
    [ 'npx by basename', '/usr/local/bin/npx' ],
    [ 'gem by basename', '/usr/local/bin/gem' ],
    [ 'pip by basename', '/usr/bin/pip' ],
    [ 'pip __main__ under dist-packages', '/usr/lib/python3/dist-packages/pip/__main__.py' ],
    [ 'pipx __main__ under site-packages', '/usr/local/lib/python3.12/site-packages/pipx/__main__.py' ],
    [ 'uv __main__ under a venv', '/home/x/.venv/lib/python3.12/site-packages/uv/__main__.py' ],
    [ 'setuptools __main__', '/usr/lib/python3/dist-packages/setuptools/__main__.py' ],
    [ 'renamed script under bundler exe/', '/usr/local/lib/ruby/gems/3.2.0/gems/bundler-2.7.1/exe/b' ]
  ].freeze
  BENIGN_SCRIPT = '/opt/app/server.js'

  # [name, command, args, capabilities] for every argv position the
  # interpreter would EXECUTE, filled with `path`.
  def self.executable_positions(path)
    rows = []
    described_class::STOP_AT_FIRST_POSITIONAL_INTERPRETERS.each do |interpreter|
      rules = described_class::INLINE_CODE_RULES_BY_INTERPRETER.fetch(interpreter)
      rows << [ "#{interpreter} first positional", interpreter, [ path, 'x' ], {} ]
      rows << [ "#{interpreter} after --", interpreter, [ '--', path, 'x' ], {} ]
      Array(rules[:path_exempt_short]).each do |flag|
        rows << [ "#{interpreter} -#{flag} separate", interpreter, [ "-#{flag}", path, './s.js' ], {} ]
        rows << [ "#{interpreter} -#{flag} attached", interpreter, [ "-#{flag}#{path}", './s.js' ], {} ]
      end
      Array(rules[:path_exempt_long]).each do |flag|
        rows << [ "#{interpreter} --#{flag} separate", interpreter, [ "--#{flag}", path, './s.js' ], {} ]
        rows << [ "#{interpreter} --#{flag}= attached", interpreter, [ "--#{flag}=#{path}", './s.js' ], {} ]
      end
    end
    rows << [ 'deno run script', 'deno', [ 'run', '-A', path ], {} ]
    rows << [ 'deno serve script', 'deno', [ 'serve', path ], {} ]
    rows << [ 'deno run after --', 'deno', [ 'run', '--', path ], {} ]
    rows << [ 'bun run script', 'bun', [ 'run', path ], {} ]
    rows << [ 'uv run script', 'uv', [ 'run', path ], PIN_EXT ]
    rows
  end

  describe 'package manager entry points: every executable argv position x every entry shape, both faces' do
    ENTRY_POINTS.each do |entry_name, entry_path|
      executable_positions(entry_path).each do |name, command, args, capabilities|
        it "refuses at spawn and at save: #{name} <- #{entry_name}" do
          expect { described_class.validate_stdio_server!(self.class.server_hash(command, args, capabilities)) }
            .to raise_error(described_class::CommandNotAllowedError, /package manager entry point/) { |e|
              expect(e.rule).to eq('package_manager_entry')
            }
          expect(described_class.package_pin_violation(command, args)).to match(/package manager entry point/)
        end
      end
    end

    executable_positions(BENIGN_SCRIPT).each do |name, command, args, capabilities|
      it "does not fire for a real script: #{name}" do
        begin
          described_class.validate_stdio_server!(self.class.server_hash(command, args, capabilities))
        rescue described_class::CommandNotAllowedError => e
          expect(e.message).not_to match(/package manager entry point/)
        end
        expect(described_class.package_pin_violation(command, args).to_s).not_to match(/package manager entry point/)
      end
    end
  end
end
