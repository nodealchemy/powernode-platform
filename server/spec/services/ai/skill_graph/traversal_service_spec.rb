# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::SkillGraph::TraversalService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  # Prevent after_commit callback from auto-creating KG nodes
  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Agent).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
  end

  describe "#traverse" do
    context "with mode :auto" do
      it "returns empty result when no task context given" do
        result = service.traverse(task_context: nil, mode: :auto)

        expect(result[:discovered_skills]).to eq([])
        expect(result[:seed_count]).to eq(0)
        expect(result[:message]).to eq("No task context provided")
      end

      it "returns empty result when no skill nodes exist" do
        allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
        result = service.traverse(task_context: "review my code", mode: :auto)

        expect(result[:discovered_skills]).to eq([])
        expect(result[:message]).to eq("No relevant skills found")
      end

      context "with skill nodes" do
        let!(:skill) { create(:ai_skill, account: account, name: "Code Review", category: "productivity", system_prompt: "You review code") }
        let!(:node) do
          create(:ai_knowledge_graph_node,
            account: account,
            name: "Code Review",
            entity_type: "skill",
            node_type: "entity",
            ai_skill_id: skill.id
          )
        end

        it "falls back to keyword search when embedding unavailable" do
          allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)

          result = service.traverse(task_context: "code review task", mode: :auto)
          expect(result[:discovered_skills].map { |s| s[:name] }).to include("Code Review")
        end
      end
    end

    context "with mode :manifest" do
      it "returns empty result when no agent given" do
        result = service.traverse(agent: nil, mode: :manifest)

        expect(result[:navigation_map]).to eq({})
        expect(result[:message]).to eq("No agent provided")
      end

      it "returns empty result when agent has no active skills" do
        agent = create(:ai_agent, account: account)
        result = service.traverse(agent: agent, mode: :manifest)

        expect(result[:navigation_map]).to eq({})
        expect(result[:message]).to eq("Agent has no active skills")
      end

      context "with agent skills and KG nodes" do
        let(:agent) { create(:ai_agent, account: account) }
        let(:skill) { create(:ai_skill, account: account, name: "Testing", category: "productivity") }
        let!(:agent_skill) { create(:ai_agent_skill, agent: agent, skill: skill) }
        let!(:node) do
          create(:ai_knowledge_graph_node,
            account: account,
            name: "Testing",
            entity_type: "skill",
            node_type: "entity",
            ai_skill_id: skill.id,
            status: "active"
          )
        end

        it "returns navigation map for agent skills" do
          result = service.traverse(agent: agent, mode: :manifest)

          expect(result[:navigation_map]).to have_key("Testing")
          expect(result[:navigation_map]["Testing"][:skill_id]).to eq(skill.id)
          expect(result[:total_skill_nodes]).to eq(1)
        end
      end
    end

    it "raises ArgumentError for invalid mode" do
      expect {
        service.traverse(mode: :invalid)
      }.to raise_error(ArgumentError, /Unknown traversal mode/)
    end
  end
end
