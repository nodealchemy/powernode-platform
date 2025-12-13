# frozen_string_literal: true

require 'rails_helper'

RSpec.describe McpToolExecution, type: :model do
  describe 'associations' do
    it { should belong_to(:mcp_tool) }
    it { should belong_to(:user) }
  end

  describe 'validations' do
    # Note: Status presence is enforced by database NOT NULL constraint + before_validation callback
    # Shoulda-matcher presence test conflicts with callback that sets default value

    it 'validates status must be a valid value' do
      execution = build(:mcp_tool_execution)
      execution.status = 'invalid'
      expect(execution).not_to be_valid
      expect(execution.errors[:status]).to include('must be a valid status')
    end

    it 'accepts valid status values' do
      %w[pending running completed failed cancelled].each do |status|
        execution = build(:mcp_tool_execution, status: status)
        expect(execution).to be_valid
      end
    end

    context 'parameters format validation' do
      it 'validates parameters is a hash' do
        execution = build(:mcp_tool_execution, parameters: 'invalid')
        expect(execution).not_to be_valid
        expect(execution.errors[:parameters]).to include('must be a hash')
      end

      it 'accepts valid parameters hash' do
        execution = build(:mcp_tool_execution, parameters: { key: 'value' })
        expect(execution).to be_valid
      end
    end

    context 'result format validation' do
      it 'validates result is a hash' do
        execution = build(:mcp_tool_execution, result: 'invalid')
        expect(execution).not_to be_valid
        expect(execution.errors[:result]).to include('must be a hash')
      end

      it 'accepts valid result hash' do
        execution = build(:mcp_tool_execution, result: { success: true })
        expect(execution).to be_valid
      end
    end
  end

  describe 'scopes' do
    let(:tool) { create(:mcp_tool) }
    let(:user) { create(:user) }
    let!(:pending_execution) { create(:mcp_tool_execution, :pending, mcp_tool: tool, user: user) }
    let!(:running_execution) { create(:mcp_tool_execution, :running, mcp_tool: tool, user: user) }
    let!(:completed_execution) { create(:mcp_tool_execution, :completed, mcp_tool: tool, user: user) }
    let!(:failed_execution) { create(:mcp_tool_execution, :failed, mcp_tool: tool, user: user) }

    describe '.pending' do
      it 'returns only pending executions' do
        expect(McpToolExecution.pending).to include(pending_execution)
        expect(McpToolExecution.pending).not_to include(completed_execution, failed_execution)
      end
    end

    describe '.running' do
      it 'returns only running executions' do
        expect(McpToolExecution.running).to include(running_execution)
        expect(McpToolExecution.running).not_to include(pending_execution, completed_execution)
      end
    end

    describe '.completed' do
      it 'returns only completed executions' do
        expect(McpToolExecution.completed).to include(completed_execution)
        expect(McpToolExecution.completed).not_to include(pending_execution, failed_execution)
      end
    end

    describe '.failed' do
      it 'returns only failed executions' do
        expect(McpToolExecution.failed).to include(failed_execution)
        expect(McpToolExecution.failed).not_to include(completed_execution)
      end
    end

    describe '.for_tool' do
      let(:other_tool) { create(:mcp_tool) }
      let!(:other_execution) { create(:mcp_tool_execution, mcp_tool: other_tool, user: user) }

      it 'filters executions by tool' do
        expect(McpToolExecution.for_tool(tool.id)).to include(pending_execution)
        expect(McpToolExecution.for_tool(tool.id)).not_to include(other_execution)
      end
    end

    describe '.for_user' do
      let(:other_user) { create(:user) }
      let!(:other_execution) { create(:mcp_tool_execution, mcp_tool: tool, user: other_user) }

      it 'filters executions by user' do
        expect(McpToolExecution.for_user(user.id)).to include(pending_execution)
        expect(McpToolExecution.for_user(user.id)).not_to include(other_execution)
      end
    end

    describe '.recent' do
      let!(:old_execution) { create(:mcp_tool_execution, mcp_tool: tool, user: user, created_at: 2.days.ago) }
      let!(:recent_execution) { create(:mcp_tool_execution, mcp_tool: tool, user: user, created_at: 1.hour.ago) }

      it 'returns executions from specified time period' do
        results = McpToolExecution.recent(24.hours)
        expect(results).to include(recent_execution)
        expect(results).not_to include(old_execution)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'sets default values on create' do
        execution = McpToolExecution.new(
          mcp_tool: create(:mcp_tool),
          user: create(:user)
        )
        execution.valid?

        expect(execution.status).to eq('pending')
        expect(execution.parameters).to eq({})
        expect(execution.result).to eq({})
      end
    end
  end

  describe 'status check methods' do
    describe '#pending?' do
      it 'returns true when status is pending' do
        execution = build(:mcp_tool_execution, :pending)
        expect(execution.pending?).to be true
      end

      it 'returns false when status is not pending' do
        execution = build(:mcp_tool_execution, :running)
        expect(execution.pending?).to be false
      end
    end

    describe '#running?' do
      it 'returns true when status is running' do
        execution = build(:mcp_tool_execution, :running)
        expect(execution.running?).to be true
      end
    end

    describe '#completed?' do
      it 'returns true when status is completed' do
        execution = build(:mcp_tool_execution, :completed)
        expect(execution.completed?).to be true
      end
    end

    describe '#failed?' do
      it 'returns true when status is failed' do
        execution = build(:mcp_tool_execution, :failed)
        expect(execution.failed?).to be true
      end
    end

    describe '#cancelled?' do
      it 'returns true when status is cancelled' do
        execution = build(:mcp_tool_execution, :cancelled)
        expect(execution.cancelled?).to be true
      end
    end
  end

  describe 'state transitions' do
    let(:execution) { create(:mcp_tool_execution, :pending) }

    describe '#start!' do
      it 'transitions to running status' do
        execution.start!
        expect(execution.reload.status).to eq('running')
      end
    end

    describe '#complete!' do
      it 'transitions to completed status' do
        result_data = { success: true, data: 'result' }
        execution.complete!(result_data)

        expect(execution.reload.status).to eq('completed')
        expect(execution.result).to eq(result_data.stringify_keys)
      end
    end

    describe '#fail!' do
      it 'transitions to failed status' do
        execution.fail!('Error message')

        expect(execution.reload.status).to eq('failed')
        expect(execution.error_message).to eq('Error message')
      end
    end

    describe '#cancel!' do
      it 'transitions to cancelled status' do
        execution.cancel!

        expect(execution.reload.status).to eq('cancelled')
        expect(execution.error_message).to eq('Execution cancelled by user')
      end
    end
  end

  describe '#summary' do
    let(:execution) { create(:mcp_tool_execution, :completed) }

    it 'returns execution summary' do
      summary = execution.summary

      expect(summary).to include(:id, :tool, :server, :status, :parameters, :result)
      expect(summary[:tool]).to eq(execution.mcp_tool.name)
      expect(summary[:server]).to eq(execution.mcp_tool.mcp_server.name)
    end
  end

  describe 'execution time calculation' do
    it 'calculates execution time on completion' do
      execution = create(:mcp_tool_execution, :pending, created_at: 5.seconds.ago)
      execution.complete!({ success: true })

      expect(execution.reload.execution_time_ms).to be_within(1000).of(5000)
    end

    it 'calculates execution time on failure' do
      execution = create(:mcp_tool_execution, :pending, created_at: 3.seconds.ago)
      execution.fail!('Error occurred')

      expect(execution.reload.execution_time_ms).to be_within(1000).of(3000)
    end

    it 'calculates execution time on cancellation' do
      execution = create(:mcp_tool_execution, :pending, created_at: 2.seconds.ago)
      execution.cancel!

      expect(execution.reload.execution_time_ms).to be_within(1000).of(2000)
    end
  end
end
