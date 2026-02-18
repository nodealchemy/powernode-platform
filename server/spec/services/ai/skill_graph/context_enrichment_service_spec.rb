# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::SkillGraph::ContextEnrichmentService, type: :service do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  subject(:service) { described_class.new(account) }

  describe "#enrich" do
    context "with auto mode" do
      it "returns empty context when no skills discovered" do
        allow_any_instance_of(Ai::SkillGraph::TraversalService).to receive(:traverse).and_return(
          discovered_skills: [], paths: [], seed_count: 0, token_estimate: 0
        )

        result = service.enrich(agent: agent, input_text: "test task", mode: :auto)

        expect(result[:context_block]).to eq("")
        expect(result[:metadata][:reason]).to eq("no_skills_found")
      end

      it "formats discovered skills as context block" do
        allow_any_instance_of(Ai::SkillGraph::TraversalService).to receive(:traverse).and_return(
          discovered_skills: [
            { name: "Code Review", category: "productivity", score: 0.85, system_prompt: "You review code" },
            { name: "Testing", category: "productivity", score: 0.72, system_prompt: nil }
          ],
          paths: [],
          seed_count: 2,
          token_estimate: 100
        )

        result = service.enrich(agent: agent, input_text: "review code", mode: :auto)

        expect(result[:context_block]).to include("=== RELEVANT SKILL CONTEXT ===")
        expect(result[:context_block]).to include("[Skill: Code Review]")
        expect(result[:context_block]).to include("You review code")
        expect(result[:context_block]).to include("[Skill: Testing]")
        expect(result[:metadata][:mode]).to eq(:auto)
        expect(result[:metadata][:skill_count]).to eq(2)
      end
    end

    context "with manifest mode" do
      it "returns empty context when no navigation map" do
        allow_any_instance_of(Ai::SkillGraph::TraversalService).to receive(:traverse).and_return(
          navigation_map: {}, recommendations: [], total_skill_nodes: 0
        )

        result = service.enrich(agent: agent, input_text: "", mode: :manifest)

        expect(result[:context_block]).to eq("")
        expect(result[:metadata][:reason]).to eq("no_skills_found")
      end

      it "formats navigation map as context block" do
        allow_any_instance_of(Ai::SkillGraph::TraversalService).to receive(:traverse).and_return(
          navigation_map: {
            "Code Review" => { skill_id: "1", node_id: "n1", category: "productivity", adjacent_skills: [{ name: "Testing" }] },
            "Deployment" => { skill_id: "2", node_id: "n2", category: "productivity", adjacent_skills: [] }
          },
          recommendations: [{ message: "Deployment has no skill graph connections" }],
          total_skill_nodes: 2
        )

        result = service.enrich(agent: agent, input_text: "", mode: :manifest)

        expect(result[:context_block]).to include("=== SKILL NAVIGATION MAP ===")
        expect(result[:context_block]).to include("Code Review -> [Testing]")
        expect(result[:context_block]).to include("Deployment (no connected skills)")
        expect(result[:context_block]).to include("Recommendations:")
        expect(result[:metadata][:mode]).to eq(:manifest)
        expect(result[:metadata][:skill_count]).to eq(2)
      end
    end

    it "returns empty context on service error" do
      allow_any_instance_of(Ai::SkillGraph::TraversalService).to receive(:traverse).and_raise(StandardError, "service down")

      result = service.enrich(agent: agent, input_text: "test", mode: :auto)

      expect(result[:context_block]).to eq("")
      expect(result[:metadata][:error]).to eq("service down")
    end
  end
end
