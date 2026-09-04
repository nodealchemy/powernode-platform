# frozen_string_literal: true

require "rails_helper"

# HIER-P2I — THE ONE resolver of "which Ai::Agent row ACTS for canonical X in
# account Y". A global canonical is a template (ruling 8); the account's
# executing principal is its clone, minted lazily on first use through the
# HIER-P1 canonical rule, and everything the account had keyed on the
# canonical's id (its intervention-policy rows, trust, delegation policy,
# skills) follows the clone so the first tick through it still acts.
RSpec.describe Ai::Agents::AccountPrincipalResolver do
  let(:seeding_account) { create(:account, name: "Powernode Admin") }
  let(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let(:canonical) do
    create(:ai_agent, :global, owner_account: seeding_account,
                              name: "Fleet Autonomy", slug: "fleet-autonomy", source_key: "fleet-autonomy",
                              agent_type: "monitor", is_system: true)
  end

  describe ".for(canonical_slug:, account:)" do
    it "mints the account's clone of the canonical on first use, keeping the canonical's identity" do
      canonical

      clone = described_class.for(canonical_slug: "fleet-autonomy", account: account)

      expect(clone).to be_present
      expect(clone.id).not_to eq(canonical.id)
      expect(clone.account_id).to eq(account.id)
      expect(clone.global?).to be(false)
      expect(clone.is_system).to be(false)
      expect(clone.cloned_from_id).to eq(canonical.id)
      expect(clone.source_key).to eq("fleet-autonomy")
      # The account's row keeps the canonical's name and slug: Ai::Agent
      # partitions uniqueness by account, and every `resolve_for(name:)` site
      # then finds the clone override-first without a second lookup rule.
      expect(clone.name).to eq("Fleet Autonomy")
      expect(clone.slug).to eq("fleet-autonomy")
      expect(clone.creator.account_id).to eq(account.id)
    end

    it "writes the canonical_clone lineage edge through HierarchyWriter" do
      canonical
      clone = described_class.for(canonical_slug: "fleet-autonomy", account: account)

      edge = Ai::AgentLineage.find_by(parent_agent_id: canonical.id, child_agent_id: clone.id)
      expect(edge).to be_present
      expect(edge.spawn_reason).to eq("canonical_clone")
      expect(edge.account_id).to eq(account.id)
      expect(clone.reload.parent_agent_id).to eq(canonical.id)
    end

    it "is idempotent: a second resolution returns the same row and mints nothing" do
      canonical
      first = described_class.for(canonical_slug: "fleet-autonomy", account: account)

      expect { described_class.for(canonical_slug: "fleet-autonomy", account: account) }
        .not_to change(Ai::Agent, :count)
      expect(described_class.for(canonical_slug: "fleet-autonomy", account: account).id).to eq(first.id)
    end

    it "resolves by source_key as well as slug" do
      canonical
      expect(described_class.for(canonical_slug: "fleet-autonomy", account: account).cloned_from_id).to eq(canonical.id)
    end

    it "prefers the account's existing row for the slug over minting" do
      canonical
      # Ai::Agent derives the slug from the name on create, so the same name
      # in this account yields the same slug — the override shape.
      owned = create(:ai_agent, account: account, name: "Fleet Autonomy", agent_type: "monitor", creator: user)
      expect(owned.slug).to eq("fleet-autonomy")

      expect { expect(described_class.for(canonical_slug: "fleet-autonomy", account: account)).to eq(owned) }
        .not_to change(Ai::Agent, :count)
    end

    it "prefers the account's existing row for the source_key over minting" do
      canonical
      owned = create(:ai_agent, account: account, name: "Renamed Reconciler", source_key: "fleet-autonomy",
                                agent_type: "monitor", creator: user)

      expect(described_class.for(canonical_slug: "fleet-autonomy", account: account)).to eq(owned)
    end

    it "returns nil when no canonical carries the slug" do
      expect(described_class.for(canonical_slug: "no-such-agent", account: account)).to be_nil
    end

    it "returns nil (mints nothing) when the account has no user to own the clone" do
      canonical
      empty = create(:account)

      expect { expect(described_class.for(canonical_slug: "fleet-autonomy", account: empty)).to be_nil }
        .not_to change(Ai::Agent, :count)
    end

    it "uses the given user as creator only when that user belongs to the account" do
      canonical
      foreign = create(:user, account: seeding_account)

      clone = described_class.for(canonical_slug: "fleet-autonomy", account: account, user: foreign)

      expect(clone.creator.account_id).to eq(account.id)
    end
  end

  describe "what follows the clone" do
    it "re-homes the account's agent-scoped intervention-policy rows from the canonical onto the clone" do
      canonical
      mine = Ai::InterventionPolicy.create!(account: account, ai_agent_id: canonical.id, scope: "agent",
                                            action_category: "system.cert_rotate", policy: "block",
                                            priority: 10, is_active: true)
      other_account = create(:account)
      theirs = Ai::InterventionPolicy.create!(account: other_account, ai_agent_id: canonical.id, scope: "agent",
                                              action_category: "system.cert_rotate", policy: "auto_approve",
                                              priority: 10, is_active: true)

      clone = described_class.for(canonical_slug: "fleet-autonomy", account: account)

      expect(mine.reload.ai_agent_id).to eq(clone.id)
      expect(mine.policy).to eq("block")
      expect(theirs.reload.ai_agent_id).to eq(canonical.id)
    end

    it "copies the canonical's skill bindings" do
      canonical
      skill = create(:ai_skill, account: seeding_account)
      Ai::AgentSkill.create!(agent: canonical, skill: skill, is_active: true, priority: 3)

      clone = described_class.for(canonical_slug: "fleet-autonomy", account: account)

      binding = Ai::AgentSkill.find_by(ai_agent_id: clone.id, ai_skill_id: skill.id)
      expect(binding).to be_present
      expect(binding.priority).to eq(3)
    end

    it "copies the canonical's trust score under the clone's account" do
      canonical
      Ai::AgentTrustScore.create!(account: seeding_account, agent: canonical, tier: "trusted", overall_score: 0.9)

      clone = described_class.for(canonical_slug: "fleet-autonomy", account: account)

      score = Ai::AgentTrustScore.find_by(agent_id: clone.id)
      expect(score.account_id).to eq(account.id)
      expect(score.tier).to eq("trusted")
    end

    it "copies the delegation policy that governed the canonical for this account" do
      canonical
      Ai::Agents::HierarchyWriter.new(account: account)
        .ensure_delegation_policy!(agent: canonical, max_depth: 2, allowed_delegate_types: [ "monitor" ])

      clone = described_class.for(canonical_slug: "fleet-autonomy", account: account)

      policy = Ai::DelegationPolicy.resolve_for(agent_id: clone.id, account_id: account.id)
      expect(policy).to be_present
      expect(policy.max_depth).to eq(2)
      expect(policy.allowed_delegate_types).to eq([ "monitor" ])
    end
  end

  describe ".acting(agent, account:)" do
    it "returns an account-scoped agent unchanged" do
      own = create(:ai_agent, account: account, creator: user)
      expect(described_class.acting(own, account: account)).to eq(own)
    end

    it "returns nil for nil" do
      expect(described_class.acting(nil, account: account)).to be_nil
    end

    it "swaps a global canonical for the account's clone, minting it on first use" do
      acting = described_class.acting(canonical, account: account)

      expect(acting.account_id).to eq(account.id)
      expect(acting.cloned_from_id).to eq(canonical.id)
      expect(described_class.acting(canonical, account: account).id).to eq(acting.id)
    end

    it "finds an existing clone by cloned_from_id even when its name and slug were changed" do
      clone = canonical.clone_to_account(account, creator: user)
      clone.update!(name: "Renamed Reconciler")

      expect(described_class.acting(canonical, account: account)).to eq(clone)
    end

    it "hands the canonical back untouched when no clone can be minted (the tool seam then refuses it by name)" do
      empty = create(:account)
      expect(described_class.acting(canonical, account: empty)).to eq(canonical)
    end
  end

  # This seam is not the only path that mints a clone: AgentManagementTool
  # #clone_canonical_agent and the REST clone door both write provenance and
  # NOTHING else. An account that arrived through one of those must still get a
  # principal the gate can read — otherwise every lane is GATE_POLICY_MISSING
  # and PolicyReconciler cannot repair it (it maps the CLONE's id, so a row
  # still on the canonical is not a re-homable former owner; it would write
  # fresh declared defaults on the clone and orphan the operator's tuned row).
  describe "follow-on moves on a clone this seam did not mint" do
    let!(:foreign_clone) { canonical.clone_to_account(account, creator: user) }

    def policy_on(agent, category, **attrs)
      Ai::InterventionPolicy.register_category!(category)
      Ai::InterventionPolicy.create!(
        { account: account, ai_agent_id: agent.id, action_category: category, scope: "agent",
          policy: "auto_approve", priority: 5, is_active: true }.merge(attrs)
      )
    end

    it "re-homes the account's agent-scoped rows off the canonical on plain resolution" do
      row = policy_on(canonical, "spec.hier.p2i.rehome")

      acting = described_class.acting(canonical, account: account)

      expect(acting.id).to eq(foreign_clone.id)
      expect(row.reload.ai_agent_id).to eq(foreign_clone.id)
    end

    it "moves an operator-shape row too — the gate's own read does not filter user_id" do
      row = policy_on(canonical, "spec.hier.p2i.rehome.user", user_id: user.id)

      described_class.acting(canonical, account: account)

      expect(row.reload.ai_agent_id).to eq(foreign_clone.id)
    end

    it "leaves ANOTHER account's rows on the canonical" do
      other = create(:account)
      Ai::InterventionPolicy.register_category!("spec.hier.p2i.rehome.other")
      row = Ai::InterventionPolicy.create!(
        account: other, ai_agent_id: canonical.id, action_category: "spec.hier.p2i.rehome.other",
        scope: "agent", policy: "auto_approve", priority: 5, is_active: true
      )

      described_class.acting(canonical, account: account)

      expect(row.reload.ai_agent_id).to eq(canonical.id)
    end

    it "is idempotent and mints nothing on a second resolution" do
      policy_on(canonical, "spec.hier.p2i.rehome.idem")

      described_class.acting(canonical, account: account)
      expect { described_class.acting(canonical, account: account) }.not_to change(Ai::Agent, :count)
    end

    it "runs for .for(canonical_slug:) too" do
      row = policy_on(canonical, "spec.hier.p2i.rehome.by-slug")

      expect(described_class.for(canonical_slug: "fleet-autonomy", account: account).id)
        .to eq(foreign_clone.id)
      expect(row.reload.ai_agent_id).to eq(foreign_clone.id)
    end
  end

  describe ".concierge_for(account)" do
    it "resolves the account's executing concierge — a clone of the global concierge on first use" do
      global = create(:ai_agent, :global, owner_account: seeding_account, is_concierge: true, status: "active",
                                          name: "Powernode Assistant", slug: "powernode-assistant",
                                          source_key: "powernode-assistant", is_system: true)

      concierge = described_class.concierge_for(account, user: user)

      expect(concierge.account_id).to eq(account.id)
      expect(concierge.cloned_from_id).to eq(global.id)
      expect(concierge.is_concierge).to be(true)
      # The read-only resolver now sees the clone first, so no second mint.
      expect(Ai::Agent.resolve_concierge_for(account.id)).to eq(concierge)
      expect(described_class.concierge_for(account, user: user)).to eq(concierge)
    end

    it "returns nil when no concierge exists at all" do
      expect(described_class.concierge_for(account, user: user)).to be_nil
    end
  end
end
