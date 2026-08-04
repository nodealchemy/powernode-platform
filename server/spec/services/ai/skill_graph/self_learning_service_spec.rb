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

    # F4: usage recording is no longer limited to agent.skills.active — a
    # skill dynamically resolved for this execution (e.g. via skill-graph
    # context enrichment) but never attached to any agent must still accrue
    # usage/last_used_at, or orphaned and global-baseline skills can never
    # recover from a cold start.
    context "with resolved_skill_ids (skills surfaced but not attached)" do
      let(:orphan_skill) { create(:ai_skill, account: account) }

      it "records usage for a resolved skill that isn't attached to the agent" do
        count = service.record_skill_outcomes(
          execution: execution, agent: agent, outcome: "success", resolved_skill_ids: [orphan_skill.id]
        )

        expect(count).to eq(2) # attached skill + resolved orphan
        expect(orphan_skill.usage_records.count).to eq(1)
        expect(orphan_skill.reload.last_used_at).to be_present
      end

      it "records for the resolved skill alone when the agent has no attached skills" do
        agent_without_skills = create(:ai_agent, account: account)

        count = service.record_skill_outcomes(
          execution: execution, agent: agent_without_skills, outcome: "success", resolved_skill_ids: [orphan_skill.id]
        )

        expect(count).to eq(1)
        expect(orphan_skill.reload.usage_count).to eq(1)
      end

      it "does not double-record a skill that is both attached and passed as resolved" do
        count = service.record_skill_outcomes(
          execution: execution, agent: agent, outcome: "success", resolved_skill_ids: [skill.id]
        )

        expect(count).to eq(1)
        expect(skill.reload.usage_count).to eq(1)
      end

      it "ignores a resolved skill id the account can't see" do
        other_account = create(:account)
        other_skill = create(:ai_skill, account: other_account)

        count = service.record_skill_outcomes(
          execution: execution, agent: agent, outcome: "success", resolved_skill_ids: [other_skill.id]
        )

        expect(count).to eq(1) # only the attached skill
        expect(other_skill.reload.usage_count).to eq(0)
      end
    end

    # F4: this path previously never called recalculate_effectiveness! at all
    # (Skill#record_usage! is the only method that did), so effectiveness sat
    # frozen at its seed value no matter how much real usage flowed through
    # agent executions.
    it "recalculates effectiveness after a single real usage (lowered gate)" do
      expect(skill.effectiveness_score).to eq(0.5) # factory default / neutral baseline

      service.record_skill_outcomes(execution: execution, agent: agent, outcome: "success")

      expect(skill.reload.effectiveness_score).not_to eq(0.5)
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

    # title/description/metadata are not columns on ai_improvement_recommendations;
    # the enclosing rescue swallowed the UnknownAttributeError, so no proposal was
    # ever persisted even when the nearest-neighbour search found matches.
    context "when a skill has close compound learnings" do
      let(:vector) { Array.new(1536, 0.1) }
      let!(:skill) { create(:ai_skill, account: account) }
      let!(:learning) do
        create(:ai_compound_learning, account: account, status: "active",
                                      content: "Always re-verify the finding on HEAD before offering it", embedding: vector)
      end

      before do
        create(:ai_knowledge_graph_node, account: account, entity_type: "skill",
                                         ai_skill_id: skill.id, status: "active", embedding: vector)
      end

      it "persists a prompt_refinement recommendation for the skill" do
        expect { service.propose_prompt_refinements }
          .to change { Ai::ImprovementRecommendation.count }.by(1)

        rec = Ai::ImprovementRecommendation.last
        expect(rec.recommendation_type).to eq("prompt_refinement")
        expect(rec.target_type).to eq("Ai::Skill")
        expect(rec.target_id).to eq(skill.id)
        expect(rec.status).to eq("pending")
        expect(rec.confidence_score).to be_present
      end

      it "carries title, description and learning provenance in evidence" do
        service.propose_prompt_refinements
        evidence = Ai::ImprovementRecommendation.last.evidence

        expect(evidence["title"]).to include(skill.name)
        expect(evidence["description"]).to include(learning.content.truncate(100))
        expect(evidence["learning_ids"]).to include(learning.id)
        expect(evidence).to have_key("skill_effectiveness")
      end

      it "returns the skill id and does not re-propose while one is pending" do
        expect(service.propose_prompt_refinements).to eq([skill.id])
        expect { service.propose_prompt_refinements }
          .not_to(change { Ai::ImprovementRecommendation.count })
      end
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

    # Same phantom-column defect as propose_prompt_refinements, plus a dedupe
    # check that filtered on a `metadata` jsonb column that does not exist.
    context "when >= 3 high-importance learnings cluster with no matching skill" do
      let!(:learnings) do
        Array.new(3) do |i|
          create(:ai_compound_learning, account: account, status: "active", category: "performance_insight",
                                        importance_score: 0.9, content: "Deployment learning #{i}",
                                        embedding: Array.new(1536, 0.1))
        end
      end

      it "persists a skill_creation recommendation targeted at the account" do
        expect { service.detect_capability_gaps }
          .to change { Ai::ImprovementRecommendation.count }.by(1)

        rec = Ai::ImprovementRecommendation.last
        expect(rec.recommendation_type).to eq("skill_creation")
        expect(rec.target_type).to eq("Account")
        expect(rec.target_id).to eq(account.id)
        expect(rec.confidence_score.to_f).to be_within(0.001).of(0.9)
      end

      it "carries the gap cluster in evidence" do
        service.detect_capability_gaps
        evidence = Ai::ImprovementRecommendation.last.evidence

        expect(evidence["title"]).to include("performance_insight")
        expect(evidence["description"]).to include("high-importance learnings")
        expect(evidence["gap_category"]).to eq("performance_insight")
        expect(evidence["gap_count"]).to eq(3)
        expect(evidence["learning_ids"]).to match_array(learnings.map(&:id))
      end

      it "reports the gaps and proposed categories" do
        result = service.detect_capability_gaps

        expect(result[:gaps].size).to eq(3)
        expect(result[:proposed_categories]).to eq(["performance_insight"])
      end

      it "does not re-propose the same category while one is pending" do
        service.detect_capability_gaps

        expect { service.detect_capability_gaps }
          .not_to(change { Ai::ImprovementRecommendation.count })
      end
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
