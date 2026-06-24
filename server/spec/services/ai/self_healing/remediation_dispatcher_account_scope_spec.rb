# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::SelfHealing::RemediationDispatcher, type: :service do
  describe 'provider failover backup query account scoping' do
    let(:account_a) { create(:account) }
    let(:account_b) { create(:account) }

    # account_a owns the degraded primary provider and an active agent on it.
    let!(:primary) { create(:ai_provider, :openai, account: account_a) }
    let!(:agent) { create(:ai_agent, account: account_a, ai_provider_id: primary.id, status: 'active') }

    # account_b owns the ONLY other openai provider. It must never be selected as
    # a backup for account_a's failover.
    let!(:other_account_provider) { create(:ai_provider, :openai, account: account_b) }

    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)
      allow(Rails.logger).to receive(:error)
      allow(ActionCable.server).to receive(:broadcast)
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:self_healing_remediation).and_return(true)
      allow(Ai::RemediationLog).to receive(:hourly_count).and_return(0)
    end

    it 'does not select another account\'s provider as the failover backup' do
      expect(Ai::RemediationLog).to receive(:create!).with(
        hash_including(result: 'skipped', result_message: 'No backup provider available')
      )

      described_class.dispatch(
        account: account_a,
        trigger_source: 'predictive_monitor',
        trigger_event: 'provider_degradation',
        context: { provider_id: primary.id }
      )
    end
  end
end
