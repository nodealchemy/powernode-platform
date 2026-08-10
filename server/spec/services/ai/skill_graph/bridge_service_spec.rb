# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::SkillGraph::BridgeService, type: :service do
  let(:account) { create(:account) }
  subject(:service) { described_class.new(account) }

  # Prevent after_commit callback from auto-creating KG nodes
  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
    allow_any_instance_of(Ai::Memory::EmbeddingService).to receive(:generate).and_return(Array.new(1536, 0.1))
  end

  describe "#sync_skill" do
    let(:skill) { create(:ai_skill, account: account, name: "Code Review", description: "Automated code review", category: "productivity", tags: ["code", "review"]) }

    it "creates a KG node linked to the skill" do
      node = service.sync_skill(skill)

      expect(node).to be_persisted
      expect(node.name).to eq("Code Review")
      expect(node.entity_type).to eq("skill")
      expect(node.node_type).to eq("entity")
      expect(node.ai_skill_id).to eq(skill.id)
      expect(node.account).to eq(account)
      expect(node.status).to eq("active")
      expect(node.confidence).to eq(1.0)
    end

    it "generates an embedding for the node" do
      node = service.sync_skill(skill)
      expect(node.embedding).to be_present
    end

    # IMP-019fe968: re-seeding logged ~107 duplicate-key errors per account.
    # ai_knowledge_graph_nodes carries TWO partial-unique indexes over active
    # rows — (account_id, ai_skill_id) and (account_id, name, node_type) — but
    # the guard here only looks up by ai_skill_id, and does not filter status.
    # GraphService#create_node is a bare create! that rescues only RecordInvalid,
    # so a RecordNotUnique falls through to sync_skill's blanket rescue: logged,
    # returns nil, skill silently absent from the graph.
    describe "idempotency (IMP-019fe968)" do
      it "is a no-op-ish update when re-synced, not a second insert" do
        first = service.sync_skill(skill)

        expect { @second = service.sync_skill(skill) }
          .not_to change { Ai::KnowledgeGraphNode.where(account: account).count }
        expect(@second).to be_present
        expect(@second.id).to eq(first.id)
      end

      it "adopts an existing active node that already occupies the (name, node_type) slot" do
        squatter = Ai::KnowledgeGraphNode.create!(
          account: account, name: "Code Review", node_type: "entity",
          entity_type: "technology", description: "extracted earlier by the KG pipeline",
          status: "active", confidence: 1.0
        )

        node = service.sync_skill(skill)

        expect(node).to be_present, "sync_skill returned nil — the unique violation was swallowed"
        expect(node.id).to eq(squatter.id)
        expect(node.ai_skill_id).to eq(skill.id)
      end

      it "refuses to hijack a slot already bound to a different skill" do
        other_skill = create(:ai_skill, account: account, name: "Other Skill", category: "productivity")
        owned = Ai::KnowledgeGraphNode.create!(
          account: account, name: "Code Review", node_type: "entity",
          entity_type: "skill", ai_skill_id: other_skill.id,
          description: "belongs to another skill", status: "active", confidence: 1.0
        )

        expect(service.sync_skill(skill)).to be_nil
        expect(owned.reload.ai_skill_id).to eq(other_skill.id)
      end

      # Adversarial review finding: adoption keyed only on ai_skill_id treats an
      # AGENT's node as unowned (its link lives in metadata.ai_agent_id, not the
      # FK), adopts it, and forces entity_type "skill" — which is exactly what
      # sync_agent looks up by, so the agent's node is destroyed AND its sync is
      # broken forever afterwards.
      it "refuses to adopt a node owned by an agent, and leaves sync_agent working" do
        # Creating the agent auto-syncs its own KG node into the (name, entity)
        # slot — this precondition is produced by ordinary use, not staged.
        agent = create(:ai_agent, account: account, name: "Code Review")
        agent_node = Ai::KnowledgeGraphNode.find_by(
          account_id: account.id, name: "Code Review", node_type: "entity", status: "active"
        )
        expect(agent_node).to be_present, "expected the agent's own sync to have claimed the slot"
        expect(agent_node.entity_type).to eq("agent")

        service.sync_skill(skill)

        expect(agent_node.reload.entity_type).to eq("agent")
        expect(agent_node.ai_skill_id).to be_nil
        expect(service.sync_agent(agent)&.id).to eq(agent_node.id)
      end

      # Adversarial review finding: the primary lookup has no status filter, and
      # partial-unique indexes cover ACTIVE rows only — so archived duplicates are
      # legal. An archived skill-bound row shadows the adoption fallback entirely:
      # it is returned, revived to active, renamed into the occupied slot, and
      # collides. The committed archived-revival example passes only because it
      # has no squatter.
      it "adopts the squatter even when an archived node for the same skill exists" do
        Ai::KnowledgeGraphNode.create!(
          account: account, name: "Code Review (old)", node_type: "entity",
          entity_type: "skill", ai_skill_id: skill.id, description: "stale",
          status: "archived", confidence: 1.0
        )
        squatter = Ai::KnowledgeGraphNode.create!(
          account: account, name: "Code Review", node_type: "entity",
          entity_type: "technology", description: "extracted earlier",
          status: "active", confidence: 1.0
        )

        node = service.sync_skill(skill)

        expect(node).to be_present, "sync_skill returned nil — the archived row shadowed the fallback"
        expect(node.id).to eq(squatter.id)
        expect(node.ai_skill_id).to eq(skill.id)
      end

      it "does not resurrect an archived node into a colliding active slot" do
        Ai::KnowledgeGraphNode.create!(
          account: account, name: "Code Review (old)", node_type: "entity",
          entity_type: "skill", ai_skill_id: skill.id, description: "stale",
          status: "archived", confidence: 1.0
        )

        node = service.sync_skill(skill)

        expect(node).to be_present, "sync_skill returned nil — the unique violation was swallowed"
        expect(node.status).to eq("active")
        expect(
          Ai::KnowledgeGraphNode.where(account: account, ai_skill_id: skill.id, status: "active").count
        ).to eq(1)
      end
    end

    it "stores skill properties on the node" do
      node = service.sync_skill(skill)
      expect(node.properties["category"]).to eq("productivity")
      expect(node.properties["tags"]).to eq(["code", "review"])
    end

    it "updates an existing KG node on re-sync" do
      first_node = service.sync_skill(skill)
      skill.update!(name: "Advanced Code Review")
      second_node = service.sync_skill(skill.reload)

      expect(second_node.id).to eq(first_node.id)
      expect(second_node.name).to eq("Advanced Code Review")
    end

    it "returns nil and logs on failure" do
      allow_any_instance_of(Ai::KnowledgeGraph::GraphService).to receive(:create_node).and_raise(StandardError, "DB error")
      expect(Rails.logger).to receive(:error).with(/sync_skill failed/)
      expect(service.sync_skill(skill)).to be_nil
    end
  end

  describe "#sync_all_skills" do
    before do
      create(:ai_skill, account: account, name: "Skill A", category: "productivity", status: "active")
      create(:ai_skill, account: account, name: "Skill B", category: "sales", status: "active")
      create(:ai_skill, account: account, name: "Skill C", category: "finance", status: "inactive")
    end

    it "syncs only active account skills" do
      result = service.sync_all_skills
      expect(result[:synced]).to eq(2)
      expect(result[:failed]).to eq(0)
    end
  end

  describe "#create_skill_edge" do
    let(:skill_a) { create(:ai_skill, account: account, name: "Skill A", category: "productivity") }
    let(:skill_b) { create(:ai_skill, account: account, name: "Skill B", category: "productivity") }

    before do
      service.sync_skill(skill_a)
      service.sync_skill(skill_b)
    end

    it "creates an edge between two skill nodes" do
      edge = service.create_skill_edge(
        source_skill_id: skill_a.id,
        target_skill_id: skill_b.id,
        relation_type: "requires"
      )

      expect(edge).to be_persisted
      expect(edge.relation_type).to eq("requires")
      expect(edge.source_node_id).to eq(skill_a.reload.knowledge_graph_node.id)
      expect(edge.target_node_id).to eq(skill_b.reload.knowledge_graph_node.id)
    end

    it "raises ArgumentError for invalid relation type" do
      expect {
        service.create_skill_edge(
          source_skill_id: skill_a.id,
          target_skill_id: skill_b.id,
          relation_type: "invalid_type"
        )
      }.to raise_error(ArgumentError, /Invalid skill relation_type/)
    end

    it "raises error when skill node not found" do
      expect {
        service.create_skill_edge(
          source_skill_id: SecureRandom.uuid,
          target_skill_id: skill_b.id,
          relation_type: "requires"
        )
      }.to raise_error(Ai::KnowledgeGraph::GraphServiceError, /Skill node not found/)
    end
  end

  describe "#remove_skill_edge" do
    let(:skill_a) { create(:ai_skill, account: account, name: "Skill A", category: "productivity") }
    let(:skill_b) { create(:ai_skill, account: account, name: "Skill B", category: "sales") }

    before do
      service.sync_skill(skill_a)
      service.sync_skill(skill_b)
    end

    it "deletes the edge" do
      edge = service.create_skill_edge(
        source_skill_id: skill_a.id,
        target_skill_id: skill_b.id,
        relation_type: "enhances"
      )

      expect { service.remove_skill_edge(edge.id) }.to change(Ai::KnowledgeGraphEdge, :count).by(-1)
    end
  end

  describe "#skill_subgraph" do
    let(:skill_a) { create(:ai_skill, account: account, name: "Skill A", category: "productivity") }
    let(:skill_b) { create(:ai_skill, account: account, name: "Skill B", category: "sales") }

    before do
      service.sync_skill(skill_a)
      service.sync_skill(skill_b)
      service.create_skill_edge(
        source_skill_id: skill_a.id,
        target_skill_id: skill_b.id,
        relation_type: "requires"
      )
    end

    it "returns all skill nodes and interconnecting edges" do
      result = service.skill_subgraph

      expect(result[:node_count]).to eq(2)
      expect(result[:edge_count]).to eq(1)
      expect(result[:nodes].map { |n| n[:name] }).to contain_exactly("Skill A", "Skill B")
      expect(result[:edges].first[:relation_type]).to eq("requires")
    end
  end

  describe "#auto_detect_relationships" do
    let(:skill) { create(:ai_skill, account: account, name: "Target Skill", category: "productivity") }

    it "returns empty when skill has no KG node" do
      result = service.auto_detect_relationships(skill)
      expect(result).to eq([])
    end
  end

  # IMP-059e6c5af2bf — global skills (account_id nil) never trigger the model
  # sync hook, so per-account node copies come only from this bridge (seed
  # post-sync / sync_all_skills). Each account must get its OWN node copy: the
  # unscoped has_one :knowledge_graph_node returns an arbitrary account's node
  # for a global skill, so an unscoped lookup here made account B's sync
  # UPDATE account A's node instead of creating B's copy.
  describe "global skills across accounts" do
    let(:other_account) { create(:account) }
    let(:global_skill) do
      create(:ai_skill, account: nil, name: "Design Skill From Intent",
             description: "Author a skill from intent", category: "skill_management")
    end

    it "gives each account its own node copy without clobbering the other's" do
      node_a = service.sync_skill(global_skill)
      # Fresh model object, as every real request has — the shared-object form
      # false-passes through the has_one's cached nil from before A's insert.
      node_b = described_class.new(other_account).sync_skill(Ai::Skill.find(global_skill.id))

      expect(node_a.reload.account_id).to eq(account.id)
      expect(node_b.account_id).to eq(other_account.id)
      expect(node_b.id).not_to eq(node_a.id)
      expect(Ai::KnowledgeGraphNode.where(ai_skill_id: global_skill.id).count).to eq(2)
    end

    it "archives and detaches every account's node copy when the skill is destroyed" do
      node_ids = [
        service.sync_skill(global_skill).id,
        described_class.new(other_account).sync_skill(Ai::Skill.find(global_skill.id)).id
      ]

      # Pre-fix this raised PG::ForeignKeyViolation outright: the has_one's
      # dependent: :nullify cleared only one copy's FK, so a global skill with
      # synced copies could not be destroyed at all.
      Ai::Skill.find(global_skill.id).destroy!

      nodes = Ai::KnowledgeGraphNode.where(id: node_ids)
      expect(nodes.pluck(:status)).to all(eq("archived"))
      expect(nodes.pluck(:ai_skill_id)).to all(be_nil)
    end

    it "covers global skills in sync_all_skills" do
      global_skill
      results = service.sync_all_skills

      expect(results[:synced]).to be >= 1
      expect(Ai::KnowledgeGraphNode.find_by(ai_skill_id: global_skill.id, account_id: account.id)).to be_present
    end
  end
end
