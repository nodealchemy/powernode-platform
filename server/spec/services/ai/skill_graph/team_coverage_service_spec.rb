# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::SkillGraph::TeamCoverageService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  let(:team) { create(:ai_agent_team, account: account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:skill_a) { create(:ai_skill, account: account, name: "Skill A", category: "productivity") }
  let(:skill_b) { create(:ai_skill, account: account, name: "Skill B", category: "sales") }
  let(:skill_c) { create(:ai_skill, account: account, name: "Skill C", category: "finance") }

  let!(:agent_skill_a) { create(:ai_agent_skill, agent: agent, skill: skill_a) }
  let!(:agent_skill_b) { create(:ai_agent_skill, agent: agent, skill: skill_b) }

  before do
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))

    bridge = Ai::SkillGraph::BridgeService.new(account)
    [skill_a, skill_b, skill_c].each { |s| bridge.sync_skill(s) }

    create(:ai_agent_team_member, team: team, agent: agent)
  end

  describe "#analyze_coverage" do
    it "returns coverage metrics" do
      result = service.analyze_coverage(team)

      expect(result[:team_id]).to eq(team.id)
      expect(result[:total_skills]).to eq(3)
      expect(result[:covered_skills]).to eq(2)
      expect(result[:coverage_ratio]).to be_between(0.6, 0.7)
      expect(result[:uncovered_skills].size).to eq(1)
      expect(result[:uncovered_skills].first[:name]).to eq("Skill C")
    end

    it "returns category breakdown" do
      result = service.analyze_coverage(team)

      productivity = result[:category_breakdown].find { |c| c[:category] == "productivity" }
      expect(productivity[:total]).to eq(1)
      expect(productivity[:covered]).to eq(1)
    end

    it "returns agent skill map" do
      result = service.analyze_coverage(team)
      expect(result[:agent_skill_map]).to have_key(agent.name)
    end
  end

  describe "#find_task_gaps" do
    it "identifies gaps between needed and team skills" do
      allow_any_instance_of(Ai::SkillGraph::TraversalService).to receive(:traverse).and_return(
        discovered_skills: [
          { skill_id: skill_a.id, name: "Skill A", category: "productivity", score: 0.9 },
          { skill_id: skill_c.id, name: "Skill C", category: "finance", score: 0.8 }
        ],
        paths: [], seed_count: 2, token_estimate: 100
      )

      result = service.find_task_gaps(team, task_context: "financial review")

      expect(result[:needed_skills]).to eq(2)
      expect(result[:covered_count]).to eq(1)
      expect(result[:gap_count]).to eq(1)
      expect(result[:gaps].first[:name]).to eq("Skill C")
    end
  end

  describe "#compose_team_suggestion" do
    it "returns empty when no skills needed" do
      allow_any_instance_of(Ai::SkillGraph::TraversalService).to receive(:traverse).and_return(
        discovered_skills: [], paths: [], seed_count: 0, token_estimate: 0
      )

      result = service.compose_team_suggestion(task_context: "nothing")
      expect(result[:members]).to eq([])
    end

    it "selects agents via greedy set-cover" do
      allow_any_instance_of(Ai::SkillGraph::TraversalService).to receive(:traverse).and_return(
        discovered_skills: [
          { skill_id: skill_a.id, name: "Skill A", category: "productivity", score: 0.9 }
        ],
        paths: [], seed_count: 1, token_estimate: 50
      )

      result = service.compose_team_suggestion(task_context: "productivity work")

      expect(result[:members].size).to be >= 1
      expect(result[:total_needed]).to eq(1)
      expect(result[:total_covered]).to eq(1)
    end
  end
end
