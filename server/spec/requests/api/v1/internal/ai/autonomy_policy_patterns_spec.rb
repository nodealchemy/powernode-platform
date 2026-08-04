# frozen_string_literal: true

require "rails_helper"

# Policy tuning turns each Ai::FeedbackLoopService suggestion into a persisted
# Ai::ImprovementRecommendation. Every attribute it writes must exist on
# ai_improvement_recommendations — the enclosing `rescue StandardError` used to
# swallow ActiveRecord::UnknownAttributeError (ai_agent_id/title/priority/
# description are not columns), so this path never persisted a single row.
RSpec.describe "Api::V1::Internal::Ai::Autonomy#analyze_policy_patterns", type: :request do
  let(:account)       { create(:account) }
  let(:system_worker) { create(:worker, :system_worker, account: account) }
  let(:worker_headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{system_worker.node_instance_id}")) }
  end
  let(:agent) { create(:ai_agent, account: account, status: "active") }

  # analyze_patterns needs >= 10 proposals in the last 30 days before it emits
  # anything, and derives its suggestion from the approved/total ratio.
  def seed_proposals(total:, approved:)
    total.times do |i|
      account.ai_agent_proposals.create!(
        ai_agent_id: agent.id,
        title: "Proposal #{i}",
        proposal_type: "process_improvement",
        priority: "medium",
        status: i < approved ? "approved" : "rejected"
      )
    end
  end

  def analyze
    post "/api/v1/internal/ai/intervention_policies/analyze_patterns", headers: worker_headers, as: :json
    response
  end

  it "requires worker mTLS authentication" do
    post "/api/v1/internal/ai/intervention_policies/analyze_patterns"
    expect(response).to have_http_status(:unauthorized)
  end

  context "with a low approval rate (quality_concern)" do
    before { seed_proposals(total: 12, approved: 2) }

    it "persists an improvement recommendation" do
      expect { analyze }.to change { Ai::ImprovementRecommendation.count }.by(1)
    end

    it "reports the suggestion in the response" do
      body = JSON.parse(analyze.body)["data"]
      expect(body["suggestions_count"]).to eq(1)
    end

    it "maps the suggestion onto real columns and the evidence jsonb" do
      analyze
      rec = Ai::ImprovementRecommendation.last

      expect(rec.account_id).to eq(account.id)
      expect(rec.recommendation_type).to eq("agent_reliability")
      expect(rec.target_type).to eq("Ai::Agent")
      expect(rec.target_id).to eq(agent.id)
      expect(rec.status).to eq("pending")

      expect(rec.evidence["title"]).to include("approval rate")
      expect(rec.evidence["description"]).to include("12 proposals")
      expect(rec.evidence["priority"]).to eq("high")
      expect(rec.evidence["suggestion_type"]).to eq("quality_concern")
      expect(rec.evidence["total_proposals"]).to eq(12)
    end

    it "scores confidence from how consistently the rate points at a concern" do
      analyze
      # 2/12 approved -> 0.8333 confidence that quality is the problem.
      expect(Ai::ImprovementRecommendation.last.confidence_score.to_f).to be_within(0.001).of(1.0 - (2.0 / 12))
    end

    # This runs on a schedule against a rolling 30-day window, so without a
    # dedupe it accrues one more pending row per agent every single run.
    it "updates its own pending suggestion in place rather than duplicating" do
      analyze
      expect { analyze }.not_to(change { Ai::ImprovementRecommendation.count })
    end

    it "refreshes the evidence and confidence of the row it updates" do
      analyze
      rec = Ai::ImprovementRecommendation.last

      # One more rejected proposal moves the rate, so the row must follow it.
      seed_proposals(total: 1, approved: 0)
      analyze

      expect(Ai::ImprovementRecommendation.count).to eq(1)
      expect(rec.reload.evidence["total_proposals"]).to eq(13)
      expect(rec.confidence_score.to_f).to be_within(0.001).of(1.0 - (2.0 / 13))
    end
  end

  context "with a very high approval rate (auto_approve_suggestion)" do
    before { seed_proposals(total: 12, approved: 12) }

    it "persists a medium-priority recommendation carrying the suggestion type" do
      expect { analyze }.to change { Ai::ImprovementRecommendation.count }.by(1)

      rec = Ai::ImprovementRecommendation.last
      expect(rec.recommendation_type).to eq("agent_reliability")
      expect(rec.evidence["suggestion_type"]).to eq("auto_approve_suggestion")
      expect(rec.evidence["priority"]).to eq("medium")
      expect(rec.confidence_score.to_f).to be_within(0.001).of(1.0)
    end
  end

  context "below the analysis threshold" do
    before { seed_proposals(total: 5, approved: 1) }

    it "creates nothing" do
      expect { analyze }.not_to(change { Ai::ImprovementRecommendation.count })
      expect(JSON.parse(response.body)["data"]["suggestions_count"]).to eq(0)
    end
  end
end
