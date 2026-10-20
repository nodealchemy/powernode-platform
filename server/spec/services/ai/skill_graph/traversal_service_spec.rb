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

        # Keyword-fallback seeds are plain nodes with no neighbor_distance; expanding
        # one through a graph edge must not raise (it did, when the embedding
        # provider was down and a seed had a linked neighbour).
        it "expands a keyword-fallback seed through its edges without a vector distance" do
          allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
          other = create(:ai_skill, account: account, name: "Lint Helper", category: "productivity", system_prompt: "You lint")
          other_node = create(:ai_knowledge_graph_node, account: account, name: "Lint Helper", entity_type: "skill", node_type: "entity", ai_skill_id: other.id)
          Ai::KnowledgeGraphEdge.create!(account: account, source_node: node, target_node: other_node, relation_type: "requires")

          result = nil
          expect { result = service.traverse(task_context: "code review task", mode: :auto) }.not_to raise_error
          expect(result[:discovered_skills].map { |s| s[:name] }).to include("Code Review")
        end

        it "excludes skills already attached to the given agent, since those are already fully injected into the agent's system prompt" do
          allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)

          agent = create(:ai_agent, account: account)
          create(:ai_agent_skill, agent: agent, skill: skill)

          result = service.traverse(task_context: "code review task", agent: agent, mode: :auto)

          expect(result[:discovered_skills].map { |s| s[:name] }).not_to include("Code Review")
        end

        it "still discovers the skill for :auto mode when no agent is given" do
          allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)

          result = service.traverse(task_context: "code review task", agent: nil, mode: :auto)

          expect(result[:discovered_skills].map { |s| s[:name] }).to include("Code Review")
        end

        # IMP-702d27f2d384 — discover_skills previously dropped the slug
        # entirely (no natural-key way to follow up with get_skill) and
        # carried no inputs/requires_approval at all, so a third-party MCP
        # client could not tell what a discovered skill accepts.
        it "carries slug, inputs and requires_approval, derived live off the skill's executor" do
          allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
          allow_any_instance_of(Ai::Skill).to receive(:executor_input_contract).and_return(
            [ { "name" => "target_path", "type" => "string", "required" => true, "description" => "" } ]
          )
          allow_any_instance_of(Ai::Skill).to receive(:executor_requires_approval?).and_return(true)

          result = service.traverse(task_context: "code review task", mode: :auto)
          entry = result[:discovered_skills].find { |s| s[:name] == "Code Review" }

          expect(entry[:slug]).to eq(skill.slug)
          expect(entry[:inputs]).to eq([ { "name" => "target_path", "type" => "string", "required" => true, "description" => "" } ])
          expect(entry[:requires_approval]).to be true
        end

        # A KG node outlives its skill's eligibility until the next prune.
        it "skips a skill that is disabled or no longer active" do
          allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil)
          skill.update_columns(is_enabled: false)

          result = service.traverse(task_context: "code review task", mode: :auto)
          expect(result[:discovered_skills].map { |s| s[:name] }).not_to include("Code Review")
        end
      end

      context "with capability facets" do
        before { allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(nil) }

        def capability_skill(name, domain:, applies_to:)
          metadata = { "capability" => name.parameterize, "domain" => domain, "triggers" => { "applies_to" => applies_to } }
          skill = create(:ai_skill, account: account, name: name, category: "productivity")
          skill.update_columns(metadata: metadata)
          create(:ai_knowledge_graph_node, account: account, name: name, entity_type: "skill", node_type: "entity", ai_skill_id: skill.id)
          skill
        end

        let!(:repo_skill) { capability_skill("Release Repo", domain: "powernode-platform-dev", applies_to: %w[powernode-platform]) }
        let!(:generic_skill) { capability_skill("Release Generic", domain: "software-engineering", applies_to: %w[any]) }

        it "filters by project kind, keeping skills that apply to it or to any" do
          names = service.traverse(task_context: "release work", mode: :auto, project_kind: "website")[:discovered_skills].map { |s| s[:name] }
          expect(names).to include("Release Generic")
          expect(names).not_to include("Release Repo")
        end

        # Neighbours are walked both ways: a generic parent seed must not pull
        # in a repository-specific child through the child's `refines` edge.
        context "with a refining child linked to a generic parent" do
          let!(:child) do
            capability_skill("Release Repo Child", domain: "powernode-platform-dev", applies_to: %w[powernode-platform]).tap do |s|
              s.update_columns(metadata: s.metadata.merge("relations" => { "refines" => [ generic_skill.slug ] }))
            end
          end

          before do
            parent_node = Ai::KnowledgeGraphNode.find_by(ai_skill_id: generic_skill.id)
            child_node = Ai::KnowledgeGraphNode.find_by(ai_skill_id: child.id)
            Ai::KnowledgeGraphEdge.create!(account: account, source_node: child_node, target_node: parent_node, relation_type: "refines")
            allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
            parent_node.define_singleton_method(:neighbor_distance) { 0.2 }
            allow(service).to receive(:find_seed_nodes).and_return([ parent_node ])
          end

          it "does not pull the child through the graph when no project kind is given" do
            names = service.traverse(task_context: "release work", mode: :auto)[:discovered_skills].map { |s| s[:name] }
            expect(names).to include("Release Generic")
            expect(names).not_to include("Release Repo Child")
          end

          it "pulls the child when the caller names the child's project kind" do
            names = service.traverse(task_context: "release work", mode: :auto, project_kind: "powernode-platform")[:discovered_skills].map { |s| s[:name] }
            expect(names).to include("Release Repo Child")
          end
        end

        it "filters by domain ceiling" do
          names = service.traverse(task_context: "release work", mode: :auto, domains: %w[powernode-platform-dev])[:discovered_skills].map { |s| s[:name] }
          expect(names).to eq([ "Release Repo" ])
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
