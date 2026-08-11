# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Skill, type: :model do
  describe "provenance / trust_level (G6)" do
    it "defaults to internal provenance and trusted trust_level" do
      skill = create(:ai_skill)

      expect(skill.provenance).to eq("internal")
      expect(skill.trust_level).to eq("trusted")
      expect(skill).to be_trusted
      expect(skill).to be_internal_provenance
    end

    it "validates provenance is one of the allowed values" do
      skill = build(:ai_skill, provenance: "totally-made-up")

      expect(skill).not_to be_valid
      expect(skill.errors[:provenance]).to be_present
    end

    it "validates trust_level is one of the allowed values" do
      skill = build(:ai_skill, trust_level: "kinda-trusted")

      expect(skill).not_to be_valid
      expect(skill.errors[:trust_level]).to be_present
    end

    it "accepts every declared provenance and trust_level value" do
      Ai::Skill::PROVENANCES.each do |prov|
        expect(build(:ai_skill, provenance: prov)).to be_valid
      end
      Ai::Skill::TRUST_LEVELS.each do |lvl|
        expect(build(:ai_skill, trust_level: lvl)).to be_valid
      end
    end

    it "exposes trust predicates" do
      expect(build(:ai_skill, trust_level: "review")).to be_needs_review
      expect(build(:ai_skill, trust_level: "untrusted")).to be_untrusted
      expect(build(:ai_skill, :community)).to be_external_provenance
    end

    it "scopes by trust level" do
      trusted   = create(:ai_skill, trust_level: "trusted")
      review    = create(:ai_skill, trust_level: "review")
      untrusted = create(:ai_skill, trust_level: "untrusted")

      expect(described_class.trusted).to include(trusted)
      expect(described_class.needs_review).to include(review)
      expect(described_class.untrusted).to include(untrusted)
      expect(described_class.untrusted).not_to include(trusted)
    end

    it "surfaces provenance + trust_level in skill_summary" do
      summary = create(:ai_skill, :community, trust_level: "review").skill_summary

      expect(summary[:provenance]).to eq("community")
      expect(summary[:trust_level]).to eq("review")
    end
  end

  # IMP-8eb424f427bc. idx_kg_nodes_unique_active_skill is PARTIAL (ai_skill_id
  # NOT NULL AND status = 'active'), so several rows may share one ai_skill_id as
  # long as only one is active. knowledge_graph_node was unscoped, so it returned
  # an arbitrary row among them and ~19 readers could not tell.
  # IMP-019fedd4 (partial). The unique index is per [account_id, ai_skill_id] and
  # sync_to_knowledge_graph gives a GLOBAL skill one active node PER ACCOUNT by
  # design, so the bare has_one returns an arbitrary tenant's node for a global
  # skill. This is the account-scoped reader that callers holding an account must
  # use — the same lookup shape SkillGraph::BridgeService#sync_skill already uses
  # for exactly this reason (IMP-059e6c5af2bf).
  # IMP-019fedd4, the half left open by f5cdfc8ca. recalculate_effectiveness!
  # weighted kg_confidence at 0.3 off the bare has_one, so a GLOBAL skill's single
  # effectiveness_score column was computed from whichever tenant's node the DB
  # happened to return — non-deterministic, and one account's data leaking into a
  # score every other account reads.
  #
  # effectiveness_score is one global column, so there is no per-tenant answer to
  # give a global skill. It therefore gets the NEUTRAL 0.5 the method already uses
  # when no node exists: deterministic, and no cross-tenant read. An account-owned
  # skill keeps using its own account's node.
  #
  # Assertions are RELATIVE (against a no-node control, or against the score
  # moving) so they do not encode the unrelated usage/compound-learning terms.
  describe "#recalculate_effectiveness! tenant scoping" do
    let(:account_a) { create(:account) }
    let(:account_b) { create(:account) }

    # NB: skill.update! re-syncs the skill's KG node and RESETS its confidence
    # (measured: 0.0 -> 1.0), so a helper that saves the skill destroys the very
    # value it is about to measure. Usage counts are therefore seeded at creation,
    # and confidence is set immediately before each recalculation with no
    # intervening skill save.
    def recalc(skill)
      skill.recalculate_effectiveness!
      skill.reload.effectiveness_score
    end

    def scored_with(skill, account_id, confidence)
      skill.knowledge_graph_node_for(account_id).update!(confidence: confidence)
      recalc(skill)
    end

    def global_skill(name)
      create(:ai_skill, account: nil, is_system: true, name: name,
                        positive_usage_count: 8, negative_usage_count: 2)
    end

    def owned_skill(name)
      create(:ai_skill, account: account_a, name: name,
                        positive_usage_count: 8, negative_usage_count: 2)
    end

    # The control: a global skill with NO node anywhere already takes the 0.5
    # neutral path, so a global skill WITH foreign nodes must score identically.
    it "scores a GLOBAL skill as if it had no node, not off a foreign tenant's" do
      with_foreign = global_skill("Global Foreign")
      create(:ai_knowledge_graph_node, account: account_a, entity_type: "skill",
             ai_skill_id: with_foreign.id, status: "active", confidence: 1.0)
      create(:ai_knowledge_graph_node, account: account_b, entity_type: "skill",
             ai_skill_id: with_foreign.id, status: "active", confidence: 0.0)
      control = global_skill("Global Control")

      expect(recalc(with_foreign)).to eq(recalc(control))
    end

    it "is deterministic for a global skill whichever tenant's node happens to exist" do
      high = global_skill("G High")
      low  = global_skill("G Low")
      create(:ai_knowledge_graph_node, account: account_a, entity_type: "skill",
             ai_skill_id: high.id, status: "active", confidence: 1.0)
      create(:ai_knowledge_graph_node, account: account_b, entity_type: "skill",
             ai_skill_id: low.id, status: "active", confidence: 0.0)

      expect(recalc(high)).to eq(recalc(low))
    end

    # An account-owned skill must still be sensitive to ITS OWN node...
    it "still tracks an account-owned skill's own node confidence" do
      skill = owned_skill("Owned Scorer")

      high = scored_with(skill, account_a.id, 1.0)
      low  = scored_with(skill, account_a.id, 0.0)

      expect(low).to be < high
    end

    # ...and insensitive to any other tenant's.
    it "ignores another tenant's node for an account-owned skill" do
      skill = owned_skill("Owned Isolated")
      before = scored_with(skill, account_a.id, 0.5)

      create(:ai_knowledge_graph_node, account: account_b, entity_type: "skill",
             ai_skill_id: skill.id, status: "active", confidence: 1.0)

      expect(scored_with(skill, account_a.id, 0.5)).to eq(before)
    end
  end

  describe "#knowledge_graph_node_for" do
    let(:account_a) { create(:account) }
    let(:account_b) { create(:account) }
    let(:global_skill) { create(:ai_skill, account: nil, is_system: true, name: "Global Reviewer") }

    it "returns the requesting account's node, not an arbitrary tenant's" do
      node_a = create(:ai_knowledge_graph_node, account: account_a, entity_type: "skill",
                      ai_skill_id: global_skill.id, status: "active", confidence: 0.9)
      node_b = create(:ai_knowledge_graph_node, account: account_b, entity_type: "skill",
                      ai_skill_id: global_skill.id, status: "active", confidence: 0.1)

      expect(global_skill.knowledge_graph_node_for(account_a.id)).to eq(node_a)
      expect(global_skill.knowledge_graph_node_for(account_b.id)).to eq(node_b)
    end

    it "returns nil when this account has no node, rather than another account's" do
      create(:ai_knowledge_graph_node, account: account_b, entity_type: "skill",
             ai_skill_id: global_skill.id, status: "active")

      expect(global_skill.knowledge_graph_node_for(account_a.id)).to be_nil
    end

    it "ignores a non-active node for the requesting account" do
      create(:ai_knowledge_graph_node, account: account_a, entity_type: "skill",
             ai_skill_id: global_skill.id, status: "archived")

      expect(global_skill.knowledge_graph_node_for(account_a.id)).to be_nil
    end
  end

  describe "#knowledge_graph_node scoping" do
    let(:account) { create(:account) }
    let(:skill)   { create(:ai_skill, account: account) }

    # after_commit :sync_to_knowledge_graph already creates an ACTIVE node on
    # skill create, so these drive the archived state off that real node rather
    # than fabricating a second one — otherwise the callback's node satisfies the
    # assertion and the spec proves nothing.
    let!(:original) { skill.reload.knowledge_graph_node || raise("callback did not create a node") }

    it "returns the active node when an archived duplicate shares the FK" do
      original.update!(status: "archived")
      replacement = create(:ai_knowledge_graph_node, account: account, entity_type: "skill",
                           ai_skill_id: skill.id, status: "active")

      expect(original.id).to be < replacement.id # the archived row is found first unscoped
      expect(skill.reload.knowledge_graph_node).to eq(replacement)
    end

    it "returns nil rather than a stale node when the only node is archived" do
      original.update!(status: "archived")

      expect(skill.reload.knowledge_graph_node).to be_nil
    end

    it "returns nil rather than a merged node" do
      original.update!(status: "merged")

      expect(skill.reload.knowledge_graph_node).to be_nil
    end
  end
end
