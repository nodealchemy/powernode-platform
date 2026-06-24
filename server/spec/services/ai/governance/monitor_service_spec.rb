# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Governance::MonitorService, type: :service do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe '#collusion_score trust coupling' do
    let(:agent_a) { create(:ai_agent, account: account, status: 'active') }
    let(:agent_b) { create(:ai_agent, account: account, status: 'active') }

    context 'when neither agent has an AgentTrustScore and there are no reviews' do
      before do
        # No peer reviews exist; the review-count relation queries return 0.
        # (Stubbed to keep the transaction clean and isolate the trust term.)
        rel = instance_double(ActiveRecord::Relation, where: nil, count: 0)
        allow(rel).to receive(:where).and_return(rel)
        allow(Ai::AgentReview).to receive(:where).and_return(rel)
      end

      # With no trust scores and no reviews, the only non-zero contributor would be
      # the trust_coupling term. Treating absent scores as 0 makes trust_a == trust_b == 0,
      # so coupling becomes 1.0 (max) and spuriously inflates the score by 0.3.
      # Absent scores must drop the trust term (coupling -> 0.0) rather than default to 0.
      it 'does not inflate the collusion score via the absent-trust term' do
        score = service.send(:collusion_score, agent_a.id, agent_b.id)

        expect(score).to eq(0.0)
      end
    end
  end
end
