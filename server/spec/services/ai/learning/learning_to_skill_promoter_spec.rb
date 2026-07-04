# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Learning::LearningToSkillPromoter, type: :service do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  let(:base_vector) { Array.new(1536, 0.1) }
  let(:orthogonal_vector) { Array.new(1536) { |i| i.even? ? 0.1 : -0.1 } }

  before do
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
  end

  def sample_cluster(member_ids:, seed_id: nil, aggregate: {})
    {
      cluster_id: 0,
      label: "Worktree Lock / Concurrency",
      category: "pattern",
      tags: %w[worktree_lock concurrency],
      member_ids: member_ids,
      member_count: member_ids.size,
      seed_id: seed_id || member_ids.first,
      representative_summary: "Always flock the shared worktree resource before mutating it",
      aggregate: {
        total_positive_outcome_count: 0,
        total_negative_outcome_count: 0,
        total_injection_count: 0,
        mean_confidence_score: 0.8,
        mean_effectiveness_score: nil,
        mean_importance_score: 0.75,
        mean_effective_importance: 0.75
      }.merge(aggregate)
    }
  end

  describe "#propose_from_cluster" do
    let(:learning_a) do
      create(:ai_compound_learning, account: account, embedding: base_vector,
                                     content: "Always flock the shared resource", importance_score: 0.8)
    end
    let(:learning_b) do
      create(:ai_compound_learning, account: account, embedding: base_vector,
                                     content: "Stagger concurrent DB preps", importance_score: 0.7)
    end
    let(:cluster) { sample_cluster(member_ids: [learning_a.id, learning_b.id]) }

    it "drafts a SkillProposal in proposed status referencing the cluster" do
      result = service.propose_from_cluster(cluster)

      proposal = result[:proposal]
      expect(proposal).to be_a(Ai::SkillProposal)
      expect(proposal.status).to eq("proposed")
      expect(proposal.metadata["source"]).to eq("learning_cluster_promotion")
      expect(proposal.metadata["source_learning_ids"]).to match_array([learning_a.id, learning_b.id])
      expect(proposal.metadata["cluster_seed_learning_id"]).to eq(cluster[:seed_id])
    end

    it "never creates or activates an Ai::Skill" do
      expect { service.propose_from_cluster(cluster) }.not_to change(Ai::Skill, :count)
    end

    it "cannot auto-approve — trust_tier_at_proposal is left unset" do
      result = service.propose_from_cluster(cluster)
      expect(result[:proposal].trust_tier_at_proposal).to be_nil
      expect(result[:proposal].can_auto_approve?).to be false
    end

    it "files a pending skill_creation recommendation pointing at the proposal" do
      result = service.propose_from_cluster(cluster)

      rec = result[:recommendation]
      expect(rec.recommendation_type).to eq("skill_creation")
      expect(rec.status).to eq("pending")
      expect(rec.target_type).to eq("Ai::SkillProposal")
      expect(rec.target_id).to eq(result[:proposal].id)
      expect(rec.recommended_config["skill_proposal_id"]).to eq(result[:proposal].id)
    end

    it "is idempotent per cluster seed learning — does not file a duplicate proposal or recommendation" do
      first = service.propose_from_cluster(cluster)
      second = nil

      expect {
        second = service.propose_from_cluster(cluster)
      }.to change(Ai::SkillProposal, :count).by(0)
      expect(Ai::ImprovementRecommendation.count).to eq(1)

      expect(second[:proposal].id).to eq(first[:proposal].id)
      expect(second[:reused]).to be true
    end

    it "falls back to a valid Ai::Skill category when the cluster's tags don't map to one" do
      result = service.propose_from_cluster(cluster)
      expect(result[:proposal].category).to eq("productivity")
    end

    it "maps a cluster tag onto the category when it is itself a valid skill category" do
      tagged_cluster = cluster.merge(tags: %w[devops concurrency])
      result = service.propose_from_cluster(tagged_cluster)
      expect(result[:proposal].category).to eq("devops")
    end
  end

  describe "#apply_approved_proposal!" do
    let(:learning_a) do
      create(:ai_compound_learning, account: account, embedding: base_vector,
                                     content: "Always flock the shared worktree resource", importance_score: 0.8)
    end
    let(:learning_b) do
      create(:ai_compound_learning, account: account, embedding: base_vector,
                                     content: "Stagger concurrent DB preps", importance_score: 0.7)
    end
    let(:cluster) { sample_cluster(member_ids: [learning_a.id, learning_b.id]) }

    def approve!(proposal)
      user = create(:user, account: account)
      Ai::SkillGraph::LifecycleService.new(account).approve_proposal(proposal_id: proposal.id, reviewer: user)
    end

    context "raising if the proposal isn't approved yet" do
      it "raises for a proposed (not yet approved) proposal" do
        result = service.propose_from_cluster(cluster)

        expect { service.apply_approved_proposal!(result[:proposal].id) }.to raise_error(ArgumentError, /must be approved/)
      end
    end

    context "no existing skill matches the cluster" do
      let!(:proposal) do
        result = service.propose_from_cluster(cluster)
        approve!(result[:proposal])
        result[:proposal].reload
      end

      it "creates a new Ai::Skill and marks the proposal created" do
        expect { service.apply_approved_proposal!(proposal.id) }.to change(Ai::Skill, :count).by(1)

        proposal.reload
        expect(proposal.status).to eq("created")
        expect(proposal.created_skill).to be_present
      end

      it "does not treat it as a match against an existing skill" do
        result = service.apply_approved_proposal!(proposal.id)
        expect(result[:matched_existing]).to be false
      end

      it "creates a KG 'composes' edge from the skill to each source learning" do
        result = service.apply_approved_proposal!(proposal.id)
        skill = result[:skill]

        edges = Ai::KnowledgeGraphEdge.where(account: account, source_node: skill.reload.knowledge_graph_node, relation_type: "composes")
        expect(edges.count).to eq(2)

        learning_node_ids = edges.map { |e| e.target_node.properties["source_learning_id"] }
        expect(learning_node_ids).to match_array([learning_a.id, learning_b.id])
      end

      it "does not duplicate provenance edges on a second apply-equivalent call" do
        result = service.apply_approved_proposal!(proposal.id)
        skill = result[:skill]

        # Re-run edge creation directly (simulates a retried apply) — idempotent.
        service.send(:create_provenance_edges!, skill, proposal.reload)

        edges = Ai::KnowledgeGraphEdge.where(account: account, source_node: skill.reload.knowledge_graph_node, relation_type: "composes")
        expect(edges.count).to eq(2)
      end

      it "is never the bare 0.5 schema seed default when the cluster carries a distinct signal" do
        applied = service.apply_approved_proposal!(proposal.id)
        expect(applied[:skill].effectiveness_score.to_f).to eq(0.75) # mean_effective_importance from sample_cluster
        expect(applied[:skill].effectiveness_score.to_f).not_to eq(0.5)
      end

      it "does not supersede the source learnings before apply — approval alone leaves them active" do
        expect(learning_a.reload.status).to eq("active")
        expect(learning_b.reload.status).to eq("active")
      end

      it "supersedes the source learnings on apply so the corpus stops resurfacing them" do
        result = service.apply_approved_proposal!(proposal.id)

        learning_a.reload
        learning_b.reload
        expect(learning_a.status).to eq("superseded")
        expect(learning_a.metadata["superseded_by_skill_id"]).to eq(result[:skill].id)
        expect(learning_b.status).to eq("superseded")
        expect(learning_b.metadata["superseded_by_skill_id"]).to eq(result[:skill].id)
      end
    end

    context "effectiveness inheritance" do
      # Fresh learnings/cluster per test — the outer `context "no existing
      # skill matches the cluster"` block's `let!(:proposal)` would otherwise
      # eagerly file (and dedupe-reuse) a proposal for the SAME seed learning
      # before these bodies run, masking the aggregate overrides under test.
      def fresh_cluster(aggregate:)
        a = create(:ai_compound_learning, account: account, embedding: base_vector,
                                           content: "Always flock the shared worktree resource", importance_score: 0.8)
        b = create(:ai_compound_learning, account: account, embedding: base_vector,
                                           content: "Stagger concurrent DB preps", importance_score: 0.7)
        sample_cluster(member_ids: [a.id, b.id], aggregate: aggregate)
      end

      it "seeds effectiveness_score from the cluster's positive/negative outcome rate when present" do
        agg_cluster = fresh_cluster(aggregate: { total_positive_outcome_count: 8, total_negative_outcome_count: 2 })
        result = service.propose_from_cluster(agg_cluster)
        approve!(result[:proposal])

        applied = service.apply_approved_proposal!(result[:proposal].id)
        expect(applied[:skill].effectiveness_score.to_f).to eq(0.8)
      end

      it "falls back to the cluster's mean_effectiveness_score when there is no outcome count signal" do
        agg_cluster = fresh_cluster(aggregate: { mean_effectiveness_score: 0.72 })
        result = service.propose_from_cluster(agg_cluster)
        approve!(result[:proposal])

        applied = service.apply_approved_proposal!(result[:proposal].id)
        expect(applied[:skill].effectiveness_score.to_f).to eq(0.72)
      end
    end

    context "the cluster maps to an existing skill (clone-on-evolve refresh)" do
      let!(:existing_skill) do
        create(:ai_skill, :global, :system_skill, name: "Worktree Concurrency Guard",
               slug: "worktree-concurrency-guard-#{SecureRandom.hex(3)}", category: "devops",
               effectiveness_score: 0.63, tags: %w[existing_tag])
      end
      let!(:existing_node) do
        create(:ai_knowledge_graph_node, account: account, entity_type: "skill", node_type: "entity",
               ai_skill_id: existing_skill.id, embedding: base_vector, status: "active")
      end

      let!(:proposal) do
        result = service.propose_from_cluster(cluster)
        approve!(result[:proposal])
        result[:proposal].reload
      end

      it "marks matched_existing true and forks the global baseline instead of editing it in place" do
        applied = service.apply_approved_proposal!(proposal.id)

        expect(applied[:matched_existing]).to be true
        expect(applied[:skill].cloned_from_id).to eq(existing_skill.id)
        expect(applied[:skill].account_id).to eq(account.id)
        expect(existing_skill.reload.account_id).to be_nil
      end

      it "merges cluster tags onto the refreshed skill without touching its effectiveness_score" do
        applied = service.apply_approved_proposal!(proposal.id)

        expect(applied[:skill].tags).to include("existing_tag", "worktree_lock", "concurrency")
        expect(applied[:skill].effectiveness_score.to_f).to eq(0.63)
      end

      it "marks the proposal created against the refreshed (cloned) skill" do
        applied = service.apply_approved_proposal!(proposal.id)

        expect(proposal.reload.status).to eq("created")
        expect(proposal.created_skill_id).to eq(applied[:skill].id)
      end

      it "supersedes the source learnings against the refreshed (cloned) skill" do
        applied = service.apply_approved_proposal!(proposal.id)

        expect(learning_a.reload.metadata["superseded_by_skill_id"]).to eq(applied[:skill].id)
        expect(learning_b.reload.metadata["superseded_by_skill_id"]).to eq(applied[:skill].id)
      end
    end
  end
end
