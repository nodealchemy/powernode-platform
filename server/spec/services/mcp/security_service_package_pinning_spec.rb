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
    [ 'uv run --with pinned', 'uv', %w[run --with pkg==1.0.0 server.py], PIN_EXT ],
    [ 'uv run args after the script belong to the script', 'uv', %w[run server.py --with foo], PIN_EXT ],
    [ 'uv run -m module (no package)', 'uv', %w[run -m mcp_server_git], PIN_EXT ],
    [ 'uv run --no-project script', 'uv', %w[run --no-project server.py], PIN_EXT ],
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
    [ 'python -m is not a launcher', 'python', %w[-m mcp_server_git], {} ]
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
    [ 'uv run --with unpinned', 'uv', %w[run --with pkg server.py], PIN_EXT, /not pinned/ ],
    [ 'uv run --with-requirements', 'uv', %w[run --with-requirements r.txt server.py], PIN_EXT, /is not allowed before the (script|package)/ ],
    [ 'uv run --index-url', 'uv', %w[run --index-url https://evil.example server.py], PIN_EXT, /is not allowed before the (script|package)/ ],
    [ 'uv run unknown option', 'uv', %w[run --unknown-opt server.py], PIN_EXT, /is not allowed before the (script|package)/ ],
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
    [ 'deno serve npm: bare name', 'deno', %w[serve npm:pkg], {}, /not pinned/ ]
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
end
