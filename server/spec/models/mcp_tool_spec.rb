# frozen_string_literal: true

require 'rails_helper'

RSpec.describe McpTool, type: :model do
  describe 'associations' do
    it { should belong_to(:mcp_server) }
    it { should have_many(:mcp_tool_executions).dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:mcp_tool) }

    it { should validate_presence_of(:name) }
    it 'defaults input_schema to empty hash' do
      tool = build(:mcp_tool, input_schema: nil)
      tool.valid?
      expect(tool.input_schema).to eq({})
    end

    context 'name uniqueness' do
      let(:server) { create(:mcp_server) }
      let!(:existing_tool) { create(:mcp_tool, name: 'read_file', mcp_server: server) }

      it 'validates uniqueness of name within server scope' do
        duplicate_tool = build(:mcp_tool, name: 'read_file', mcp_server: server)
        expect(duplicate_tool).not_to be_valid
        expect(duplicate_tool.errors[:name]).to include('has already been taken')
      end

      it 'allows same name for different servers' do
        different_server = create(:mcp_server)
        tool = build(:mcp_tool, name: 'read_file', mcp_server: different_server)
        expect(tool).to be_valid
      end
    end

    context 'input_schema format validation' do
      it 'validates input_schema is a hash' do
        tool = build(:mcp_tool, input_schema: 'invalid')
        expect(tool).not_to be_valid
        expect(tool.errors[:input_schema]).to include('must be a hash')
      end

      it 'accepts valid input_schema hash' do
        tool = build(:mcp_tool, input_schema: { type: 'object', properties: {} })
        expect(tool).to be_valid
      end
    end
  end

  describe 'scopes' do
    let(:server1) { create(:mcp_server) }
    let(:server2) { create(:mcp_server) }
    let!(:tool1) { create(:mcp_tool, mcp_server: server1) }
    let!(:tool2) { create(:mcp_tool, mcp_server: server2) }

    describe '.for_server' do
      it 'filters tools by server' do
        expect(McpTool.for_server(server1.id)).to include(tool1)
        expect(McpTool.for_server(server1.id)).not_to include(tool2)
      end
    end

    describe '.recently_used' do
      let!(:used_tool) { create(:mcp_tool, :recently_used, mcp_server: server1) }
      let!(:unused_tool) { create(:mcp_tool, mcp_server: server1) }

      it 'returns tools used in the last 24 hours' do
        expect(McpTool.recently_used).to include(used_tool)
        expect(McpTool.recently_used).not_to include(unused_tool)
      end
    end

    describe '.by_name' do
      let!(:read_tool) { create(:mcp_tool, :read_file, mcp_server: server1) }
      let!(:write_tool) { create(:mcp_tool, :write_file, mcp_server: server1) }

      it 'filters tools by name' do
        expect(McpTool.by_name('read_file')).to include(read_tool)
        expect(McpTool.by_name('read_file')).not_to include(write_tool)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'sets default values on create' do
        tool = McpTool.new(mcp_server: create(:mcp_server), name: 'test_tool')
        tool.valid?

        expect(tool.input_schema).to eq({})
      end
    end
  end

  describe '#execute' do
    let(:account) { create(:account) }
    let(:tool) { create(:mcp_tool, mcp_server: create(:mcp_server, account: account)) }
    let(:user) { create(:user, account: account) }
    let(:parameters) { { path: '/test/file.txt' } }

    before do
      allow(Mcp::PermissionValidator).to receive(:new).and_return(
        instance_double(Mcp::PermissionValidator, authorized?: true)
      )
      allow(WorkerJobService).to receive(:enqueue_mcp_tool_execution).and_return(true)
    end

    it 'creates an execution record' do
      expect { tool.execute(user: user, account: account, parameters: parameters) }
        .to change { tool.mcp_tool_executions.count }.by(1)
    end

    it 'sets execution status to pending' do
      execution = tool.execute(user: user, account: account, parameters: parameters)
      expect(execution.status).to eq('pending')
    end

    it 'stores parameters' do
      execution = tool.execute(user: user, account: account, parameters: parameters)
      expect(execution.parameters).to eq(parameters.stringify_keys)
    end

    it 'returns the execution record' do
      execution = tool.execute(user: user, account: account, parameters: parameters)
      expect(execution).to be_a(McpToolExecution)
      expect(execution).to be_persisted
    end
  end

  describe '#validate_parameters' do
    let(:tool) { create(:mcp_tool, :read_file) }

    context 'with valid parameters' do
      it 'validates required parameters are present' do
        result = tool.validate_parameters('path' => '/test/file.txt')
        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
      end

      it 'validates parameters with symbol keys' do
        result = tool.validate_parameters(path: '/test/file.txt')
        expect(result[:valid]).to be true
      end
    end

    context 'with invalid parameters' do
      it 'detects missing required parameters' do
        result = tool.validate_parameters({})
        expect(result[:valid]).to be false
        expect(result[:errors]).to include('Missing required parameter: path')
      end
    end

    context 'with empty schema' do
      let(:tool) { build(:mcp_tool) }

      before do
        # Manually set blank input_schema after build to test validate_parameters behavior
        tool.input_schema = {}
      end

      it 'returns valid for any parameters' do
        result = tool.validate_parameters({ anything: 'goes' })
        expect(result[:valid]).to be true
      end
    end
  end

  describe '#metadata' do
    let(:tool) { create(:mcp_tool, :read_file, :with_executions) }

    it 'returns tool metadata' do
      metadata = tool.metadata

      expect(metadata).to include(:name, :description, :server, :input_schema)
      expect(metadata[:execution_count]).to eq(tool.mcp_tool_executions.count)
      expect(metadata[:recent_executions]).to be_an(Array)
    end
  end

  describe '#execution_stats' do
    let(:tool) { create(:mcp_tool) }
    let(:user) { create(:user) }

    before do
      create(:mcp_tool_execution, :completed, mcp_tool: tool, user: user, execution_time_ms: 100)
      create(:mcp_tool_execution, :completed, mcp_tool: tool, user: user, execution_time_ms: 200)
      create(:mcp_tool_execution, :failed, mcp_tool: tool, user: user)
    end

    it 'calculates execution statistics' do
      stats = tool.execution_stats

      expect(stats[:total_executions]).to eq(3)
      expect(stats[:successful]).to eq(2)
      expect(stats[:failed]).to eq(1)
      expect(stats[:success_rate]).to eq(66.67)
      expect(stats[:avg_execution_time]).to eq(150)
    end

    it 'returns zero statistics for no executions' do
      new_tool = create(:mcp_tool)
      stats = new_tool.execution_stats

      expect(stats[:total_executions]).to eq(0)
      expect(stats[:success_rate]).to eq(0.0)
    end
  end
end
