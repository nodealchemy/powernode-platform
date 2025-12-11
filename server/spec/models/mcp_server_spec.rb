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
        server = build(:mcp_server, args: ['--port', '3000'])
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
end
