# frozen_string_literal: true

require 'rails_helper'

# The model_downgrade remediation, executed for real. The sibling
# predictive_monitor_service_spec stubs the dispatcher's RETURN value, so the
# body of execute_model_downgrade was never run by any example — a synthetic
# proof of a capability that raised NoMethodError on `agent.model_id` the moment
# it reached a live agent (IMP-929aadc88e19). Every example here uses a real
# Ai::Agent and no dispatcher stub, and asserts the PIN actually moved rather
# than merely that nothing raised.
RSpec.describe Ai::SelfHealing::RemediationDispatcher, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, :anthropic, account: account) }
  let(:pinned_model) { 'claude-opus-4-8' }
  let(:economy_model) { 'claude-haiku-4-5' }

  let!(:agent) do
    create(
      :ai_agent,
      account: account,
      provider: provider,
      status: 'active',
      mcp_metadata: { 'model_config' => { 'model' => pinned_model } }
    )
  end

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
    allow(Shared::FeatureFlagService).to receive(:enabled?).with(:self_healing_remediation).and_return(true)
    allow(Ai::RemediationLog).to receive(:hourly_count).with(account.id).and_return(0)
    Ai::ModelTiers.reset_price_cache!
  end

  describe 'execute_model_downgrade' do
    subject(:result) { described_class.send(:execute_model_downgrade, account, { source_id: provider.id }) }

    it 'reports success without raising' do
      expect(result).to include(status: 'success')
    end

    it 'moves the agent pin to a cheaper model on the same provider' do
      expect { result }
        .to change { agent.reload.mcp_metadata.dig('model_config', 'model') }
        .from(pinned_model).to(economy_model)
    end

    it 'resolves the downgraded agent to the economy model' do
      result

      expect(agent.reload.resolved_model).to eq(economy_model)
    end

    it 'keeps the agent on its own provider' do
      expect { result }.not_to change { agent.reload.ai_provider_id }
    end

    it 'records the pre-downgrade model so the original is recoverable' do
      result

      recorded = agent.reload.metadata.dig('self_healing', 'original_model')
      expect(recorded).to eq(pinned_model)

      agent.update!(
        mcp_metadata: agent.mcp_metadata.deep_merge('model_config' => { 'model' => recorded })
      )
      expect(agent.reload.resolved_model).to eq(pinned_model)
    end

    it 'skips an agent whose provider lists nothing cheaper' do
      agent.update!(mcp_metadata: { 'model_config' => { 'model' => economy_model } })

      expect(result).to include(status: 'success', message: 'Downgraded 0 agents to economy models')
      expect(agent.reload.mcp_metadata.dig('model_config', 'model')).to eq(economy_model)
    end

    it 'skips when no provider is specified' do
      expect(described_class.send(:execute_model_downgrade, account, {}))
        .to include(status: 'skipped', message: 'No provider specified')
    end

    it 'skips when the provider has no active agents' do
      agent.update!(status: 'inactive')

      expect(result).to include(status: 'skipped', message: 'No agents to downgrade')
    end

    it 'leaves agents on other providers alone' do
      other_provider = create(
        :ai_provider, :anthropic, account: account, name: 'Anthropic Secondary', slug: 'anthropic-other'
      )
      other_agent = create(
        :ai_agent,
        account: account,
        provider: other_provider,
        status: 'active',
        mcp_metadata: { 'model_config' => { 'model' => pinned_model } }
      )

      result

      expect(other_agent.reload.mcp_metadata.dig('model_config', 'model')).to eq(pinned_model)
    end
  end

  describe '.dispatch with an execution_degradation trigger' do
    subject(:dispatch) do
      described_class.dispatch(
        account: account,
        trigger_source: 'agent_execution',
        trigger_event: 'execution_degradation',
        context: { source_id: provider.id }
      )
    end

    it 'downgrades the agent end to end' do
      expect { dispatch }
        .to change { agent.reload.mcp_metadata.dig('model_config', 'model') }
        .from(pinned_model).to(economy_model)
    end

    # KNOWN GAP, deliberately pinned: Ai::RemediationLog::ACTION_TYPES lists only
    # provider_failover / workflow_retry / alert_escalation, so the log write for
    # a model_downgrade (and a context_trim) fails its inclusion validation and is
    # swallowed by log_remediation's rescue — the remediation happens but is never
    # audited. Fixing that means editing app/models/ai/remediation_log.rb, which is
    # outside this task's file scope; this example makes the gap visible and will
    # red the moment the action type is admitted.
    it 'does not yet audit the downgrade (model_downgrade missing from RemediationLog::ACTION_TYPES)' do
      expect(Ai::RemediationLog::ACTION_TYPES).not_to include('model_downgrade')
      expect { dispatch }.not_to change(Ai::RemediationLog, :count)
    end
  end
end
