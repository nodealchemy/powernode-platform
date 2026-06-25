# frozen_string_literal: true

require 'rails_helper'

# Direct-inference AI jobs must honor the kill switch (AiSuspensionCheckConcern):
# emergency_halt / per-account suspension has to stop them BEFORE they reach a
# provider. These four call an LLM/provider directly (or delegate straight into a
# job that does), so a missing concern means the kill switch silently does nothing.
# Regression spec for IMP-48099cb357f8.
RSpec.describe 'Direct-inference AI job kill-switch compliance' do
  let(:account_id) { 'account-101' }

  before do
    mock_powernode_worker_config
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
  end

  describe AiChatResponseJob do
    it 'includes AiSuspensionCheckConcern' do
      expect(described_class.include?(AiSuspensionCheckConcern)).to be true
    end

    it 'bails before any backend/provider work when AI is suspended' do
      job = described_class.new
      allow(job).to receive(:ai_suspended?).with(account_id).and_return(true)
      expect(job).not_to receive(:backend_api_get)
      expect(job).not_to receive(:call_provider_streaming)

      job.execute('conv-1', 'msg-1', 'agent-1', account_id)
    end
  end

  describe AiWorkspaceResponseJob do
    it 'includes AiSuspensionCheckConcern' do
      expect(described_class.include?(AiSuspensionCheckConcern)).to be true
    end

    it 'bails before any backend/provider work when AI is suspended' do
      job = described_class.new
      allow(job).to receive(:ai_suspended?).with(account_id).and_return(true)
      expect(job).not_to receive(:backend_api_get)
      expect(job).not_to receive(:call_provider_streaming)

      job.execute('conv-1', 'msg-1', 'agent-1', account_id)
    end
  end

  describe AiConversationResponseJob do
    it 'includes AiSuspensionCheckConcern' do
      expect(described_class.include?(AiSuspensionCheckConcern)).to be true
    end

    it 'bails before delegating to AiChatResponseJob when AI is suspended' do
      job = described_class.new
      api = instance_double('BackendApiClient')
      allow(job).to receive(:api_client).and_return(api)
      allow(api).to receive(:get).with(a_string_matching(%r{/api/v1/ai/conversations/})).and_return(
        'success' => true,
        'data' => { 'conversation' => { 'agent_id' => 'agent-1', 'account_id' => account_id } }
      )
      allow(job).to receive(:ai_suspended?).with(account_id).and_return(true)
      expect(AiChatResponseJob).not_to receive(:new)

      job.execute('conv-1', 'msg-1', 'user-1')
    end
  end

  describe AiCodeFactoryPrdJob do
    it 'includes AiSuspensionCheckConcern' do
      expect(described_class.include?(AiSuspensionCheckConcern)).to be true
    end

    it 'bails before generating the PRD when AI is suspended' do
      job = described_class.new
      allow(job).to receive(:ai_suspended?).with(account_id).and_return(true)
      expect(job).not_to receive(:backend_api_get)
      expect(job).not_to receive(:call_ai_provider)

      job.execute('ralph_loop_id' => 'loop-1', 'account_id' => account_id)
    end
  end
end
