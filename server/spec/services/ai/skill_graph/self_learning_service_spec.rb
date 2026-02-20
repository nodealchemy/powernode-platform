# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::SkillGraph::SelfLearningService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Agent).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
  end

  describe "#record_skill_outcomes" do
    let(:agent) { create(:ai_agent, account: account) }
    let(:skill) { create(:ai_skill, account: account) }
    let(:execution) { double("execution", id: SecureRandom.uuid, class: OpenStruct.new(name: "Ai::AgentExecution"), duration_ms: 1500, task_description: "Run tests") }

    before do
      create(:ai_agent_skill, agent: agent, skill: skill)
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_self_learning, account).and_return(true)
    end

    it "creates usage records for each active agent skill" do
      count = service.record_skill_outcomes(execution: execution, agent: agent, outcome: "success")

      expect(count).to eq(1)
      expect(skill.usage_records.count).to eq(1)
      record = skill.usage_records.last
      expect(record.outcome).to eq("success")
      expect(record.ai_agent_id).to eq(agent.id)
    end

    it "increments positive_usage_count on success" do
      service.record_skill_outcomes(execution: execution, agent: agent, outcome: "success")

      skill.reload
      expect(skill.positive_usage_count).to eq(1)
    end

    it "increments negative_usage_count on failure" do
      service.record_skill_outcomes(execution: execution, agent: agent, outcome: "failure")

      skill.reload
      expect(skill.negative_usage_count).to eq(1)
    end

    it "updates last_used_at timestamp" do
      freeze_time do
        service.record_skill_outcomes(execution: execution, agent: agent, outcome: "success")

        skill.reload
        expect(skill.last_used_at).to be_within(1.second).of(Time.current)
      end
    end

    context "when feature flag is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_self_learning, account).and_return(false)
      end

      it "returns nil without recording" do
        result = service.record_skill_outcomes(execution: execution, agent: agent, outcome: "success")

        expect(result).to be_nil
        expect(skill.usage_records.count).to eq(0)
      end
    end

    it "returns 0 when agent has no skills" do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_self_learning, account).and_return(true)
      agent_without_skills = create(:ai_agent, account: account)

      result = service.record_skill_outcomes(execution: execution, agent: agent_without_skills, outcome: "success")

      expect(result).to be_nil
    end

    it "handles nil agent gracefully" do
      result = service.record_skill_outcomes(execution: execution, agent: nil, outcome: "success")
      expect(result).to be_nil
    end
  end

  describe "#optimize_dependencies" do
    let(:agent) { create(:ai_agent, account: account) }
    let(:skill_a) { create(:ai_skill, account: account) }
    let(:skill_b) { create(:ai_skill, account: account) }
    let(:execution) { double("execution", id: SecureRandom.uuid) }

    before do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_self_learning, account).and_return(true)
      create(:ai_agent_skill, agent: agent, skill: skill_a)
      create(:ai_agent_skill, agent: agent, skill: skill_b)
    end

    it "strengthens edge weights on successful outcomes" do
      node_a = Ai::KnowledgeGraphNode.create!(
        account: account, name: "A", entity_type: "skill",
        node_type: "entity", status: "active", confidence: 1.0,
        ai_skill_id: skill_a.id
      )
      node_b = Ai::KnowledgeGraphNode.create!(
        account: account, name: "B", entity_type: "skill",
        node_type: "entity", status: "active", confidence: 1.0,
        ai_skill_id: skill_b.id
      )
      edge = Ai::KnowledgeGraphEdge.create!(
        account: account, source_node: node_a, target_node: node_b,
        relation_type: "requires", status: "active",
        weight: 0.5, confidence: 0.8
      )

      service.optimize_dependencies(execution: execution, agent: agent, outcome: "success")

      edge.reload
      expect(edge.weight).to eq(0.55)
    end

    it "weakens edge weights on failure outcomes" do
      node_a = Ai::KnowledgeGraphNode.create!(
        account: account, name: "A", entity_type: "skill",
        node_type: "entity", status: "active", confidence: 1.0,
        ai_skill_id: skill_a.id
      )
      node_b = Ai::KnowledgeGraphNode.create!(
        account: account, name: "B", entity_type: "skill",
        node_type: "entity", status: "active", confidence: 1.0,
        ai_skill_id: skill_b.id
      )
      edge = Ai::KnowledgeGraphEdge.create!(
        account: account, source_node: node_a, target_node: node_b,
        relation_type: "requires", status: "active",
        weight: 0.5, confidence: 0.8
      )

      service.optimize_dependencies(execution: execution, agent: agent, outcome: "failure")

      edge.reload
      expect(edge.weight).to eq(0.45)
    end

    it "clamps weight to minimum 0.1" do
      node_a = Ai::KnowledgeGraphNode.create!(
        account: account, name: "A", entity_type: "skill",
        node_type: "entity", status: "active", confidence: 1.0,
        ai_skill_id: skill_a.id
      )
      node_b = Ai::KnowledgeGraphNode.create!(
        account: account, name: "B", entity_type: "skill",
        node_type: "entity", status: "active", confidence: 1.0,
        ai_skill_id: skill_b.id
      )
      edge = Ai::KnowledgeGraphEdge.create!(
        account: account, source_node: node_a, target_node: node_b,
        relation_type: "requires", status: "active",
        weight: 0.1, confidence: 0.8
      )

      service.optimize_dependencies(execution: execution, agent: agent, outcome: "failure")

      edge.reload
      expect(edge.weight).to eq(0.1)
    end

    context "when feature flag is disabled" do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_self_learning, account).and_return(false)
      end

      it "does nothing" do
        expect { service.optimize_dependencies(execution: execution, agent: agent, outcome: "success") }
          .not_to change { Ai::KnowledgeGraphEdge.count }
      end
    end
  end

  describe "#propose_prompt_refinements" do
    before do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_self_learning, account).and_return(true)
    end

    it "returns empty when feature flag is disabled" do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_self_learning, account).and_return(false)

      result = service.propose_prompt_refinements

      expect(result).to eq([])
    end

    it "returns empty when no skills have KG nodes with embeddings" do
      create(:ai_skill, account: account)

      result = service.propose_prompt_refinements

      expect(result).to eq([])
    end
  end

  describe "#detect_capability_gaps" do
    before do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_self_learning, account).and_return(true)
    end

    it "returns empty gaps when feature flag is disabled" do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:skill_self_learning, account).and_return(false)

      result = service.detect_capability_gaps

      expect(result[:gaps]).to eq([])
      expect(result[:proposed_categories]).to eq([])
    end

    it "returns empty when no high-importance learnings exist" do
      result = service.detect_capability_gaps

      expect(result[:gaps]).to eq([])
    end
  end

  describe "#recalculate_all_effectiveness" do
    it "recalculates effectiveness for all active skills" do
      create(:ai_skill, account: account, status: "active", positive_usage_count: 8, negative_usage_count: 2)
      create(:ai_skill, account: account, status: "active", positive_usage_count: 3, negative_usage_count: 7)
      create(:ai_skill, account: account, status: "inactive")

      result = service.recalculate_all_effectiveness

      expect(result).to eq(2) # Only active skills
    end

    it "returns 0 when no active skills exist" do
      result = service.recalculate_all_effectiveness

      expect(result).to eq(0)
    end

    it "handles errors gracefully" do
      allow(Ai::Skill).to receive_message_chain(:for_account, :active, :find_each).and_raise(StandardError, "db error")

      result = service.recalculate_all_effectiveness

      expect(result).to eq(0)
    end
  end
end
