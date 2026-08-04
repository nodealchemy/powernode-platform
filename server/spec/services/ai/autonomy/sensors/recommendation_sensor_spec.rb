# frozen_string_literal: true

require "rails_helper"

# The sensor read ai_agent_id/title/priority/description off
# Ai::ImprovementRecommendation, none of which are columns. Its bare
# `rescue StandardError; []` turned the resulting StatementInvalid /
# UnknownAttributeError into "no recommendations", silently and permanently.
RSpec.describe Ai::Autonomy::Sensors::RecommendationSensor, type: :service do
  let(:account) { create(:account) }
  let(:agent)   { create(:ai_agent, account: account) }

  subject(:sensor) { described_class.new(account: account, agent: agent) }

  def recommendation(target_type:, target_id:, evidence: {}, status: "pending")
    create(
      :ai_improvement_recommendation,
      account: account,
      recommendation_type: "agent_reliability",
      target_type: target_type,
      target_id: target_id,
      status: status,
      evidence: evidence
    )
  end

  it "surfaces an agent-targeted recommendation as an observation" do
    recommendation(
      target_type: "Ai::Agent",
      target_id: agent.id,
      evidence: {
        "title" => "Only 16.7% approval rate",
        "description" => "Based on 12 proposals",
        "priority" => "high"
      }
    )

    obs = sensor.collect.find { |o| o[:observation_type] == "recommendation" }

    expect(obs).to be_present
    expect(obs[:title]).to eq("Recommendation: Only 16.7% approval rate")
    expect(obs[:severity]).to eq("warning")
    expect(obs[:data][:priority]).to eq("high")
    expect(obs[:data][:description]).to eq("Based on 12 proposals")
    expect(obs[:requires_action]).to be(true)
  end

  it "treats a non-high priority as informational" do
    recommendation(
      target_type: "Ai::Agent",
      target_id: agent.id,
      evidence: { "title" => "Consider auto-approve", "priority" => "medium" }
    )

    expect(sensor.collect.first[:severity]).to eq("info")
  end

  it "includes recommendations that target something other than an agent" do
    recommendation(target_type: "Account", target_id: account.id, evidence: { "title" => "Fleet-wide gap" })

    expect(sensor.collect.map { |o| o[:title] }).to include("Recommendation: Fleet-wide gap")
  end

  it "excludes recommendations targeted at a different agent" do
    other = create(:ai_agent, account: account)
    recommendation(target_type: "Ai::Agent", target_id: other.id, evidence: { "title" => "Not mine" })

    expect(sensor.collect).to be_empty
  end

  it "excludes recommendations that are no longer pending" do
    recommendation(
      target_type: "Ai::Agent", target_id: agent.id, status: "dismissed",
      evidence: { "title" => "Already handled" }
    )

    expect(sensor.collect).to be_empty
  end

  it "falls back to the recommendation type when evidence carries no title" do
    recommendation(target_type: "Ai::Agent", target_id: agent.id, evidence: {})

    expect(sensor.collect.first[:title]).to eq("Recommendation: agent_reliability improvement")
  end

  # Code-quality offers are the /improve loop's own backlog: they are drained by
  # Ai::DevLoop::ImprovementPromotionService as Ralph tasks, not by an agent
  # reading its observation feed. Surfacing them here injects another
  # repository's lint findings into every agent's prompt as its own action item
  # and burns the per-hour observation budget that other sensors need.
  describe "code-quality offer exclusion" do
    it "excludes a repository-targeted code_lint offer" do
      create(
        :ai_improvement_recommendation,
        account: account, recommendation_type: "code_lint",
        target_type: "Devops::GitRepository", target_id: SecureRandom.uuid,
        status: "pending", evidence: { "title" => "Lint finding in an unrelated repo" }
      )

      expect(sensor.collect).to be_empty
    end

    it "excludes every code-quality type even when not repository-targeted" do
      Ai::ImprovementRecommendation::CODE_QUALITY_TYPES.each do |type|
        create(
          :ai_improvement_recommendation,
          account: account, recommendation_type: type,
          target_type: "Account", target_id: account.id,
          status: "pending", evidence: { "title" => "Offer #{type}" }
        )
      end

      expect(sensor.collect).to be_empty
    end

    it "still surfaces a non-code-quality recommendation alongside them" do
      create(
        :ai_improvement_recommendation,
        account: account, recommendation_type: "code_lint",
        target_type: "Devops::GitRepository", target_id: SecureRandom.uuid,
        status: "pending", evidence: { "title" => "Lint finding" }
      )
      recommendation(target_type: "Ai::Agent", target_id: agent.id, evidence: { "title" => "Mine" })

      expect(sensor.collect.map { |o| o[:title] }).to eq(["Recommendation: Mine"])
    end
  end

  # limit(5) with no ORDER BY is arbitrary: an agent's own freshly-written
  # recommendations can be crowded out permanently by older rows.
  it "returns the newest recommendations first" do
    6.times do |i|
      recommendation(
        target_type: "Ai::Agent", target_id: agent.id,
        evidence: { "title" => "Rec #{i + 1}" }
      ).update_column(:created_at, (10 - i).minutes.ago)
    end

    titles = sensor.collect.map { |o| o[:title] }

    expect(titles.size).to eq(5)
    expect(titles.first).to eq("Recommendation: Rec 6")
    expect(titles).not_to include("Recommendation: Rec 1")
  end
end
