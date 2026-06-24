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
      # With no trust scores and no reviews, the only non-zero contributor would be
      # the trust_coupling term. Treating absent scores as 0 makes trust_a == trust_b == 0,
      # so coupling becomes 1.0 (max) and spuriously inflates the score by 0.3.
      # Absent scores must drop the trust term (coupling -> 0.0) rather than default to 0.
      it 'does not inflate the collusion score via the absent-trust term' do
        score = service.send(:collusion_score, agent_a.id, agent_b.id)

        expect(score).to eq(0.0)
      end

      # Regression: collusion_score previously queried Ai::AgentReview (the marketplace
      # template-review model) with reviewer_id/reviewed_agent_id/outcome columns that do
      # not exist. The query raised PG::UndefinedColumn (silently rescued to 0) AND left the
      # surrounding Postgres transaction in an aborted state, so the very next query failed
      # with PG::InFailedSqlTransaction. This example runs the real query path (no stubs)
      # and then issues a trivial query to prove the transaction is still usable.
      it 'does not poison the surrounding transaction' do
        service.send(:collusion_score, agent_a.id, agent_b.id)

        expect { Ai::Agent.count }.not_to raise_error
      end
    end
  end
end
