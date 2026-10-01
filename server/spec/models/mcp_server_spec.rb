# frozen_string_literal: true

require 'rails_helper'

RSpec.describe McpServer, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should have_many(:mcp_tools).dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:mcp_server) }

    it { should validate_presence_of(:name) }
    # Note: status has a default value set in before_validation, so presence validation would never fail
    it { should validate_inclusion_of(:status).in_array(%w[connected disconnected connecting error]).with_message('must be a valid status') }
    it { should validate_presence_of(:connection_type) }
    it { should validate_inclusion_of(:connection_type).in_array(%w[stdio websocket http]).with_message('must be stdio, websocket, or http') }

    context 'connection-target preservation (http/websocket)' do
      let(:account) { create(:account) }

      it 'rejects clearing a previously-set command/URL on an http server (edit-form data-loss guard)' do
        server = create(:mcp_server, account: account, connection_type: 'http', command: 'https://example.com/mcp')
        server.command = ''
        expect(server).not_to be_valid
        expect(server.errors[:command]).to be_present
      end

      it 'rejects clearing the URL on a websocket server' do
        server = create(:mcp_server, account: account, connection_type: 'websocket', command: 'wss://example.com/mcp')
        server.command = ''
        expect(server).not_to be_valid
      end

      it 'allows creating an http server with a blank command (create stays lenient)' do
        server = build(:mcp_server, account: account, connection_type: 'http', command: '')
        expect(server).to be_valid
      end

      it 'does not flag an http server whose command is unchanged (status-only update)' do
        server = create(:mcp_server, account: account, connection_type: 'http', command: 'https://example.com/mcp')
        server.status = 'connected'
        expect(server).to be_valid
      end
    end

    context 'name uniqueness' do
      let(:account) { create(:account) }
      let!(:existing_server) { create(:mcp_server, name: 'Test Server', account: account) }

      it 'validates uniqueness of name within account scope' do
        duplicate_server = build(:mcp_server, name: 'Test Server', account: account)
        expect(duplicate_server).not_to be_valid
        expect(duplicate_server.errors[:name]).to include('has already been taken')
      end

      it 'allows same name for different accounts' do
        different_account = create(:account)
        server = build(:mcp_server, name: 'Test Server', account: different_account)
        expect(server).to be_valid
      end
    end

    context 'connection configuration validation' do
      it 'requires command for stdio connection' do
        server = build(:mcp_server, :stdio_connection, command: nil)
        expect(server).not_to be_valid
        expect(server.errors[:command]).to include('is required for stdio connection')
      end

      it 'allows nil command for websocket connection' do
        server = build(:mcp_server, :websocket_connection, command: nil)
        expect(server).to be_valid
      end
    end

    context 'args format validation' do
      it 'validates args is an array' do
        server = build(:mcp_server, args: 'invalid')
        expect(server).not_to be_valid
        expect(server.errors[:args]).to include('must be an array')
      end

      it 'accepts valid args array' do
        server = build(:mcp_server, args: [ '--port', '3000' ])
        expect(server).to be_valid
      end
    end

    context 'env format validation' do
      it 'validates env is a hash' do
        server = build(:mcp_server, env: 'invalid')
        expect(server).not_to be_valid
        expect(server.errors[:env]).to include('must be a hash')
      end

      it 'accepts valid env hash' do
        server = build(:mcp_server, env: { 'NODE_ENV' => 'production' })
        expect(server).to be_valid
      end
    end

    # IMP-bf72723ef161
    context 'egress_allowlist validation' do
      it 'accepts a mix of valid IPs, CIDRs and hostnames' do
        server = build(:mcp_server, capabilities: {
                         'egress_allowlist' => [ '93.184.216.34', '10.0.0.0/8', 'api.example.com' ]
                       })
        expect(server).to be_valid
      end

      it 'rejects a non-array value' do
        server = build(:mcp_server, capabilities: { 'egress_allowlist' => 'not-an-array' })
        expect(server).not_to be_valid
        expect(server.errors[:capabilities]).to include('egress_allowlist must be an array')
      end

      it "rejects more than #{McpServer::MAX_EGRESS_ALLOWLIST_ENTRIES} entries" do
        too_many = Array.new(McpServer::MAX_EGRESS_ALLOWLIST_ENTRIES + 1) { |i| "host-#{i}.example.com" }
        server = build(:mcp_server, capabilities: { 'egress_allowlist' => too_many })
        expect(server).not_to be_valid
        expect(server.errors[:capabilities])
          .to include("egress_allowlist may have at most #{McpServer::MAX_EGRESS_ALLOWLIST_ENTRIES} entries")
      end

      it 'rejects an entry that is not a valid IP, CIDR, or hostname' do
        server = build(:mcp_server, capabilities: { 'egress_allowlist' => [ 'not a hostname!' ] })
        expect(server).not_to be_valid
        expect(server.errors[:capabilities].join).to include('is not a valid IP, CIDR, or hostname')
      end

      it 'rejects 0.0.0.0/0 and ::/0 as full-open-equivalent entries' do
        server = build(:mcp_server, capabilities: { 'egress_allowlist' => [ '0.0.0.0/0' ] })
        expect(server).not_to be_valid
        expect(server.errors[:capabilities].join).to include('full-open range')

        server6 = build(:mcp_server, capabilities: { 'egress_allowlist' => [ '::/0' ] })
        expect(server6).not_to be_valid
        expect(server6.errors[:capabilities].join).to include('full-open range')
      end

      it 'rejects loopback, link-local and the cloud metadata address' do
        %w[127.0.0.1 127.0.0.0/8 169.254.1.1 169.254.169.254 ::1 fe80::1].each do |entry|
          server = build(:mcp_server, capabilities: { 'egress_allowlist' => [ entry ] })
          expect(server).not_to be_valid, "expected #{entry.inspect} to be rejected"
          expect(server.errors[:capabilities].join).to include('forbidden range')
        end
      end

      it 'rejects a broad CIDR that swallows a forbidden range whole' do
        server = build(:mcp_server, capabilities: { 'egress_allowlist' => [ '100.0.0.0/1' ] })
        expect(server).not_to be_valid
        expect(server.errors[:capabilities].join).to include('forbidden range')
      end

      # IMP-bf72723ef161 review round 2 fix 2 — an IPv4-mapped IPv6
      # literal is a real, working way to NAME an IPv4 address; without
      # normalizing to its native form first, these never match the
      # plain IPv4 CIDRs in FORBIDDEN_EGRESS_RANGES.
      it 'rejects an IPv4-mapped IPv6 loopback or metadata address' do
        %w[::ffff:127.0.0.1 ::ffff:169.254.169.254].each do |entry|
          server = build(:mcp_server, capabilities: { 'egress_allowlist' => [ entry ] })
          expect(server).not_to be_valid, "expected #{entry.inspect} to be rejected"
          expect(server.errors[:capabilities].join).to include('forbidden range')
        end
      end

      it 'accepts an IPv4-mapped IPv6 form of an ordinary public IP' do
        server = build(:mcp_server, capabilities: { 'egress_allowlist' => [ '::ffff:93.184.216.34' ] })
        expect(server).to be_valid
      end

      # IMP-bf72723ef161 review round 2 fix 3 — numeric/octal/hex
      # "pseudo-IP" forms IPAddr itself refuses to parse strictly, but a
      # vulnerable getaddrinfo/URL-parsing implementation downstream may
      # still accept and resolve as a real IP (a well-known SSRF bypass) —
      # these must never be accepted as "just a hostname" merely because
      # they happen to be alphanumeric-plus-dots.
      it 'rejects numeric/octal/hex pseudo-IP forms' do
        %w[2130706433 127.1 0177.0.0.1 0x7f.0.0.1 0x7f000001].each do |entry|
          server = build(:mcp_server, capabilities: { 'egress_allowlist' => [ entry ] })
          expect(server).not_to be_valid, "expected #{entry.inspect} to be rejected"
          expect(server.errors[:capabilities].join).to include('pseudo-IP')
        end
      end

      it 'still accepts a hostname with a leading numeric label (e.g. NTP pool style)' do
        server = build(:mcp_server, capabilities: { 'egress_allowlist' => [ '1.pool.example.com' ] })
        expect(server).to be_valid
      end
    end

    # IMP-bf72723ef161
    context 'allow_network / egress_allowlist mutual exclusion' do
      it 'rejects allow_network=true together with a non-empty egress_allowlist' do
        server = build(:mcp_server, capabilities: {
                         'allow_network' => true, 'egress_allowlist' => [ '10.0.0.0/8' ]
                       })
        expect(server).not_to be_valid
        expect(server.errors[:capabilities].join).to include('cannot both be set')
      end

      it 'allows allow_network=true with no egress_allowlist' do
        server = build(:mcp_server, capabilities: { 'allow_network' => true })
        expect(server).to be_valid
      end

      it 'allows allow_network=false with an egress_allowlist' do
        server = build(:mcp_server, capabilities: {
                         'allow_network' => false, 'egress_allowlist' => [ '10.0.0.0/8' ]
                       })
        expect(server).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:connected_server) { create(:mcp_server, :connected) }
    let!(:disconnected_server) { create(:mcp_server, :disconnected) }
    let!(:connecting_server) { create(:mcp_server, :connecting) }
    let!(:error_server) { create(:mcp_server, :error) }

    describe '.connected' do
      it 'returns only connected servers' do
        expect(McpServer.connected).to include(connected_server)
        expect(McpServer.connected).not_to include(disconnected_server, error_server)
      end
    end

    describe '.disconnected' do
      it 'returns only disconnected servers' do
        expect(McpServer.disconnected).to include(disconnected_server)
        expect(McpServer.disconnected).not_to include(connected_server)
      end
    end

    describe '.active' do
      it 'returns connected servers' do
        expect(McpServer.active).to include(connected_server)
        expect(McpServer.active).not_to include(disconnected_server, error_server)
      end
    end

    describe '.inactive' do
      it 'returns disconnected and error servers' do
        expect(McpServer.inactive).to include(disconnected_server, error_server)
        expect(McpServer.inactive).not_to include(connected_server)
      end
    end

    describe '.by_connection_type' do
      let!(:stdio_server) { create(:mcp_server, :stdio_connection) }
      let!(:websocket_server) { create(:mcp_server, :websocket_connection) }

      it 'filters by connection type' do
        expect(McpServer.by_connection_type('stdio')).to include(stdio_server)
        expect(McpServer.by_connection_type('stdio')).not_to include(websocket_server)
      end
    end

    describe '.recently_checked' do
      let!(:recently_checked) { create(:mcp_server, :recently_checked) }
      let!(:not_recently_checked) { create(:mcp_server, :needs_health_check) }

      it 'returns servers checked within last 5 minutes' do
        expect(McpServer.recently_checked).to include(recently_checked)
        expect(McpServer.recently_checked).not_to include(not_recently_checked)
      end
    end

    describe '.needs_health_check' do
      let!(:needs_check) { create(:mcp_server, :needs_health_check) }
      let!(:recently_checked) { create(:mcp_server, :recently_checked) }

      it 'returns servers needing health check' do
        expect(McpServer.needs_health_check).to include(needs_check)
        expect(McpServer.needs_health_check).not_to include(recently_checked)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'sets default values on create' do
        server = McpServer.new(account: create(:account), name: 'Test', connection_type: 'stdio', command: 'test')
        server.valid?

        expect(server.status).to eq('disconnected')
        expect(server.args).to eq([])
        expect(server.env).to eq({})
        expect(server.capabilities).to eq({})
      end
    end
  end

  describe 'status check methods' do
    describe '#connected?' do
      it 'returns true when status is connected' do
        server = build(:mcp_server, :connected)
        expect(server.connected?).to be true
      end

      it 'returns false when status is not connected' do
        server = build(:mcp_server, :disconnected)
        expect(server.connected?).to be false
      end
    end

    describe '#disconnected?' do
      it 'returns true when status is disconnected' do
        server = build(:mcp_server, :disconnected)
        expect(server.disconnected?).to be true
      end
    end

    describe '#connecting?' do
      it 'returns true when status is connecting' do
        server = build(:mcp_server, :connecting)
        expect(server.connecting?).to be true
      end
    end

    describe '#error?' do
      it 'returns true when status is error' do
        server = build(:mcp_server, :error)
        expect(server.error?).to be true
      end
    end
  end

  describe '#connect!' do
    let(:server) { create(:mcp_server, :disconnected) }

    before do
      allow(WorkerJobService).to receive(:enqueue_mcp_server_connection).and_return(true)
    end

    it 'changes status to connecting' do
      server.connect!
      expect(server.reload.status).to eq('connecting')
    end

    it 'queues a connection job' do
      expect(WorkerJobService).to receive(:enqueue_mcp_server_connection).with(server.id, action: 'connect')
      server.connect!
    end

    it 'sets error status when worker service fails' do
      allow(WorkerJobService).to receive(:enqueue_mcp_server_connection).and_raise(
        WorkerJobService::WorkerServiceError.new('Connection failed')
      )
      server.connect!
      expect(server.reload.status).to eq('error')
    end
  end

  describe '#disconnect!' do
    let(:server) { create(:mcp_server, :connected) }

    before do
      allow(WorkerJobService).to receive(:enqueue_mcp_server_connection).and_return(true)
    end

    it 'changes status to disconnected' do
      server.disconnect!
      expect(server.reload.status).to eq('disconnected')
    end

    it 'updates last_health_check' do
      server.disconnect!
      expect(server.reload.last_health_check).to be_within(1.second).of(Time.current)
    end
  end

  describe '#health_check!' do
    let(:server) { create(:mcp_server, :connected) }

    before do
      allow(WorkerJobService).to receive(:enqueue_mcp_health_check).and_return(true)
    end

    it 'returns true for connected server' do
      expect(server.health_check!).to be true
    end

    it 'queues a health check job' do
      expect(WorkerJobService).to receive(:enqueue_mcp_health_check).with(server.id)
      server.health_check!
    end

    it 'returns false for disconnected server' do
      server.update!(status: 'disconnected')
      expect(server.health_check!).to be false
    end
  end

  describe '#discover_tools' do
    let(:server) { create(:mcp_server, :connected) }

    before do
      allow(WorkerJobService).to receive(:enqueue_mcp_tool_discovery).and_return(true)
    end

    it 'queues tool discovery job for connected server' do
      expect(WorkerJobService).to receive(:enqueue_mcp_tool_discovery).with(server.id)
      server.discover_tools
    end

    it 'returns empty array for disconnected server' do
      server.update!(status: 'disconnected')
      expect(server.discover_tools).to eq([])
    end
  end

  describe '#server_info' do
    let(:server) { create(:mcp_server, :connected, :with_tools) }

    it 'returns server information' do
      info = server.server_info

      expect(info).to include(:id, :name, :status, :connection_type, :tool_count, :capabilities)
      expect(info[:tool_count]).to eq(server.mcp_tools.count)
    end
  end

  describe '#connection_env' do
    let(:server) { create(:mcp_server, env: { 'CUSTOM_VAR' => 'value' }) }

    it 'merges server env with connection metadata' do
      env = server.connection_env

      expect(env['CUSTOM_VAR']).to eq('value')
      expect(env['MCP_SERVER_NAME']).to eq(server.name)
      expect(env['MCP_SERVER_ID']).to eq(server.id)
    end
  end

  # IMP-2c760325c102 (MCP isolation Phase 1 T4) — package-launcher pinning
  # at SAVE time. The full grammar lives in
  # spec/services/mcp/security_service_package_pinning_spec.rb; this block
  # only proves the model consults it, and WHEN.
  describe 'package-launcher pinning at save time' do
    let(:account) { create(:account) }

    it 'refuses to create a stdio server whose npx package is not pinned to an exact version' do
      server = build(:mcp_server, account: account, command: 'npx', args: [ '-y', '@modelcontextprotocol/server-filesystem', '/tmp' ])

      expect(server).not_to be_valid
      expect(server.errors[:command].join).to match(/not pinned to an exact version/)
    end

    it 'accepts a stdio server whose package is pinned' do
      server = build(:mcp_server, account: account, command: 'npx', args: [ '-y', '@modelcontextprotocol/server-filesystem@2026.8.31', '/tmp' ])

      expect(server).to be_valid
    end

    it 'checks launcher tokens in the command string, not only args' do
      server = build(:mcp_server, account: account, command: 'npx -y pkg', args: [])

      expect(server).not_to be_valid
      expect(server.errors[:command].join).to match(/not pinned/)
    end

    it 'does not apply to http/websocket servers' do
      server = build(:mcp_server, account: account, connection_type: 'http', command: 'https://example.com/mcp', args: [])

      expect(server).to be_valid
    end

    it 'refuses editing the command/args of an existing row into an unpinned launcher' do
      server = create(:mcp_server, account: account, command: 'node', args: [ 'server.js' ])
      server.command = 'npx'
      server.args = [ '-y', 'pkg' ]

      expect(server).not_to be_valid
      expect(server.errors[:command].join).to match(/not pinned/)
    end

    # The worker reports a spawn refusal by PATCHing status/last_error onto
    # the SAME row; if every save re-ran this validation, that report would
    # itself be refused and the operator would see nothing. Pre-existing
    # unpinned rows therefore stay saveable until their command/args change.
    it 'lets a pre-existing unpinned row save status/last_error updates unchanged (the spawn refusal must be reportable)' do
      server = create(:mcp_server, account: account, command: 'node', args: [ 'server.js' ])
      server.update_columns(command: 'npx', args: [ '-y', 'pkg' ])
      server.reload

      expect(server.update(status: 'error', last_error: 'Security error: npx: package "pkg" is not pinned')).to be true
      expect(server.reload.last_error).to match(/not pinned/)
    end
  end

  # IMP-2c760325c102 — the native (unsandboxed) execution hatch, core mode
  # only, operator-approved per server, cleared whenever the command changes.
  describe 'native execution approval' do
    let(:account) { create(:account) }
    let(:approver) { create(:user, :owner, account: account) }
    let(:server) { create(:mcp_server, account: account, command: 'node', args: [ 'server.js' ]) }

    def stub_business_layer(present)
      allow(Shared::FeatureGateService).to receive(:capability_present?).and_call_original
      McpServer::NATIVE_EXECUTION_BLOCKING_CAPABILITIES.each do |cap|
        allow(Shared::FeatureGateService).to receive(:capability_present?).with(cap).and_return(present)
      end
    end

    describe '.native_execution_available?' do
      it 'is true when no business-layer capability is present (core mode)' do
        stub_business_layer(false)
        expect(described_class.native_execution_available?).to be true
      end

      it 'is false when the business layer is present' do
        stub_business_layer(false)
        allow(Shared::FeatureGateService).to receive(:capability_present?).with(:subscriptions).and_return(true)
        expect(described_class.native_execution_available?).to be false
      end
    end

    it 'is not approved by default' do
      expect(server.native_execution_approved?).to be false
      expect(server.native_execution_effective?).to be false
    end

    it '#approve_native_execution! records who approved and when, in capabilities' do
      stub_business_layer(false)
      server.approve_native_execution!(approver)
      server.reload

      expect(server.native_execution_approved?).to be true
      expect(server.native_execution_approval['approved_by_id']).to eq(approver.id)
      expect(server.native_execution_approval['approved_at']).to be_present
      expect(server.native_execution_effective?).to be true
    end

    it '#revoke_native_execution! clears it' do
      stub_business_layer(false)
      server.approve_native_execution!(approver)
      server.revoke_native_execution!
      server.reload

      expect(server.native_execution_approved?).to be false
      expect(server.capabilities).not_to have_key(McpServer::NATIVE_EXECUTION_KEY)
    end

    it 'an approval goes dormant (not effective) while the business layer is present, without being erased' do
      stub_business_layer(false)
      server.approve_native_execution!(approver)
      stub_business_layer(true)

      expect(server.reload.native_execution_approved?).to be true
      expect(server.native_execution_effective?).to be false
    end

    it 'is cleared automatically when the command changes' do
      stub_business_layer(false)
      server.approve_native_execution!(approver)
      server.update!(command: 'python3', args: [ 'server.py' ])

      expect(server.reload.native_execution_approved?).to be false
      expect(server.native_execution_cleared_by_change?).to be true
    end

    it 'is cleared automatically when the args change' do
      stub_business_layer(false)
      server.approve_native_execution!(approver)
      server.update!(args: [ 'server.js', '--other' ])

      expect(server.reload.native_execution_approved?).to be false
    end

    it 'survives an unrelated edit (description, status)' do
      stub_business_layer(false)
      server.approve_native_execution!(approver)
      server.update!(description: 'renamed', status: 'error')

      expect(server.reload.native_execution_approved?).to be true
    end

    it 'is only ever effective for stdio servers' do
      stub_business_layer(false)
      http_server = create(:mcp_server, account: account, connection_type: 'http', command: 'https://example.com/mcp', args: [])
      http_server.approve_native_execution!(approver)

      expect(http_server.native_execution_effective?).to be false
    end

    describe '#worker_capabilities (what the worker is told)' do
      it 'carries only the spawn-policy keys plus the computed native_execution_approved flag' do
        stub_business_layer(false)
        server.update!(capabilities: server.capabilities.merge(
          'allow_network' => true, 'config' => { 'api_key' => 'secret' }, 'last_error' => 'x', 'tools' => true
        ))
        server.approve_native_execution!(approver)

        expect(server.worker_capabilities).to eq('allow_network' => true, 'native_execution_approved' => true)
      end

      it 'omits native_execution_approved while the business layer is present, even if approved' do
        stub_business_layer(false)
        server.approve_native_execution!(approver)
        stub_business_layer(true)

        expect(server.worker_capabilities).not_to have_key('native_execution_approved')
      end

      it 'omits native_execution_approved for an unapproved server (the worker tests for an exact true)' do
        stub_business_layer(false)

        expect(server.worker_capabilities).to eq({})
      end
    end
  end
end
