# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::ManagementService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:agent) { create(:ai_agent, account: account, status: "active") }

  subject(:service) { described_class.new(agent: agent, user: user) }

  describe '#execute' do
    context 'when agent is not MCP available' do
      before do
        allow(agent).to receive(:mcp_available?).and_return(false)
      end

      it 'returns failure result' do
        result = service.execute(input_parameters: {})

        expect(result.success?).to be false
        expect(result.error).to include("cannot be executed")
      end
    end

    context 'when agent is MCP available' do
      let(:execution) { double('execution', id: SecureRandom.uuid) }

      before do
        allow(agent).to receive(:mcp_available?).and_return(true)
        allow(agent).to receive(:execute).and_return(execution)
        allow(agent).to receive(:reload).and_return(agent)
      end

      it 'executes the agent and returns success' do
        result = service.execute(input_parameters: { "input" => "test" })

        expect(result.success?).to be true
        expect(result.data[:execution]).to eq(execution)
      end

      it 'resolves provider when provider_id is given' do
        provider = create(:ai_provider, account: account)
        allow(agent).to receive(:execute).and_return(execution)

        result = service.execute(input_parameters: {}, provider_id: provider.id)

        expect(result.success?).to be true
      end

      it 'returns error when provider_id is invalid' do
        result = service.execute(input_parameters: {}, provider_id: SecureRandom.uuid)

        expect(result.success?).to be false
        expect(result.error).to include("AI provider not found")
      end
    end

    context 'when execution raises ArgumentError' do
      before do
        allow(agent).to receive(:mcp_available?).and_return(true)
        allow(agent).to receive(:execute).and_raise(ArgumentError.new("Invalid input"))
      end

      it 'returns failure result with error message' do
        result = service.execute(input_parameters: {})

        expect(result.success?).to be false
        expect(result.error).to eq("Invalid input")
      end
    end
  end

  describe '#clone' do
    it 'clones the agent successfully' do
      cloned = double('cloned_agent', id: SecureRandom.uuid)
      allow(agent).to receive(:clone_for_account).with(account, user).and_return(cloned)

      result = service.clone

      expect(result.success?).to be true
      expect(result.data[:agent]).to eq(cloned)
      expect(result.data[:original_agent_id]).to eq(agent.id)
    end

    it 'returns error when cloning fails' do
      allow(agent).to receive(:clone_for_account).and_raise(StandardError.new("Clone error"))

      result = service.clone

      expect(result.success?).to be false
      expect(result.error).to include("Failed to clone agent")
    end
  end

  describe '#test' do
    it 'returns test result on success' do
      test_result = { success: true, output: "test output" }
      allow(agent).to receive(:test_execution).and_return(test_result)

      result = service.test(test_input: { "input" => "test" })

      expect(result.success?).to be true
      expect(result.data[:test_result]).to eq(test_result)
    end

    it 'returns error when test fails' do
      allow(agent).to receive(:test_execution).and_raise(StandardError.new("Test failed"))

      result = service.test(test_input: {})

      expect(result.success?).to be false
      expect(result.error).to include("Test execution failed")
    end
  end

  describe '#validate' do
    it 'returns validation result' do
      validation = { valid: true, errors: [], warnings: ["Minor issue"] }
      allow(agent).to receive(:validate_configuration).and_return(validation)

      result = service.validate

      expect(result.success?).to be true
      expect(result.data[:valid]).to be true
      expect(result.data[:warnings]).to eq(["Minor issue"])
    end
  end

  describe '#pause' do
    it 'pauses an active agent' do
      result = service.pause

      expect(result.success?).to be true
      expect(agent.reload.status).to eq("paused")
    end

    it 'returns error if agent is not active' do
      agent.update!(status: "paused")
      result = service.pause

      expect(result.success?).to be false
      expect(result.error).to include("must be active")
    end
  end

  describe '#resume' do
    it 'resumes a paused agent' do
      agent.update!(status: "paused")
      result = service.resume

      expect(result.success?).to be true
      expect(agent.reload.status).to eq("active")
    end

    it 'returns error if agent is not paused' do
      result = service.resume

      expect(result.success?).to be false
      expect(result.error).to include("must be paused")
    end
  end

  describe '#archive' do
    it 'archives the agent' do
      result = service.archive

      expect(result.success?).to be true
      expect(agent.reload.status).to eq("archived")
    end
  end

  describe '#stats' do
    let!(:completed_exec) do
      create(:ai_agent_execution, :completed, agent: agent, account: account)
    end
    let!(:failed_exec) do
      create(:ai_agent_execution, :failed, agent: agent, account: account)
    end

    it 'returns execution statistics' do
      stats = service.stats

      expect(stats[:total_executions]).to eq(2)
      expect(stats[:successful_executions]).to eq(1)
      expect(stats[:failed_executions]).to eq(1)
      expect(stats[:success_rate]).to eq(50.0)
    end
  end

  describe '#account_statistics' do
    let!(:agent2) { create(:ai_agent, account: account, status: "paused") }

    it 'returns account-wide statistics' do
      stats = service.account_statistics

      expect(stats[:total_agents]).to be >= 2
      expect(stats[:active_agents]).to be >= 1
      expect(stats[:paused_agents]).to be >= 1
    end
  end
end
