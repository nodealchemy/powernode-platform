# frozen_string_literal: true

require "rails_helper"

# HIER-P1 — the ONE writer of Ai::AgentLineage + Ai::DelegationPolicy. Seeds
# and every runtime agent-creation path go through it, so the Autonomy page's
# lineage forest and the delegation panel describe the same structure.
RSpec.describe Ai::Agents::HierarchyWriter do
  let(:account)  { create(:account) }
  let(:user)     { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:parent)   { create(:ai_agent, account: account, creator: user, provider: provider, name: "Parent") }
  let(:child)    { create(:ai_agent, account: account, creator: user, provider: provider, name: "Child") }

  subject(:writer) { described_class.new(account: account) }

  def active_edges_for(agent)
    Ai::AgentLineage.for_child(agent.id).active
  end

  describe "#attach!" do
    it "creates the lineage row and sets the child's parent_agent_id" do
      lineage = writer.attach!(child: child, parent: parent, spawn_reason: "seed")

      expect(lineage).to be_persisted
      expect(lineage.account).to eq(account)
      expect(lineage.parent_agent).to eq(parent)
      expect(lineage.child_agent).to eq(child)
      expect(lineage.spawn_reason).to eq("seed")
      expect(lineage.spawned_at).to be_present
      expect(lineage).to be_active
      expect(child.reload.parent_agent_id).to eq(parent.id)
    end

    it "merges caller metadata over the parent snapshot" do
      lineage = writer.attach!(child: child, parent: parent, spawn_reason: "seed", metadata: { "role" => "specialist" })

      expect(lineage.metadata).to include("role" => "specialist", "parent_type" => parent.agent_type)
    end

    it "REFRESHES the parent snapshot on a re-attach (a stale trust level must not outlive a change)" do
      parent.update!(trust_level: "supervised")
      writer.attach!(child: child, parent: parent, spawn_reason: "seed", metadata: { "role" => "specialist" })

      parent.update!(trust_level: "autonomous")
      lineage = writer.attach!(child: child, parent: parent, spawn_reason: "seed")

      expect(lineage.reload.metadata).to include(
        "parent_trust_level" => "autonomous", "parent_type" => parent.agent_type, "role" => "specialist"
      )
    end

    it "is idempotent on (parent, child): a re-attach creates no second row" do
      first = writer.attach!(child: child, parent: parent, spawn_reason: "seed")

      expect {
        second = writer.attach!(child: child, parent: parent, spawn_reason: "seed")
        expect(second.id).to eq(first.id)
      }.not_to change(Ai::AgentLineage, :count)

      expect(active_edges_for(child).count).to eq(1)
    end

    it "reactivates a terminated edge instead of creating a duplicate" do
      first = writer.attach!(child: child, parent: parent, spawn_reason: "seed")
      first.terminate!(reason: "manual")

      expect {
        writer.attach!(child: child, parent: parent, spawn_reason: "seed")
      }.not_to change(Ai::AgentLineage, :count)

      expect(first.reload.terminated_at).to be_nil
      expect(first.termination_reason).to be_nil
      expect(child.reload.parent_agent_id).to eq(parent.id)
    end

    it "leaves the child with exactly ONE active edge when re-parented" do
      other = create(:ai_agent, account: account, creator: user, provider: provider, name: "Other Parent")
      old_edge = writer.attach!(child: child, parent: other, spawn_reason: "seed")

      writer.attach!(child: child, parent: parent, spawn_reason: "seed")

      expect(old_edge.reload.terminated_at).to be_present
      expect(active_edges_for(child).pluck(:parent_agent_id)).to eq([ parent.id ])
      expect(child.reload.parent_agent_id).to eq(parent.id)
    end

    it "refuses a self edge" do
      expect {
        writer.attach!(child: parent, parent: parent, spawn_reason: "seed")
      }.to raise_error(ActiveRecord::RecordInvalid, /same as parent/)
    end

    it "refuses a cycle (the model's check stays authoritative)" do
      writer.attach!(child: child, parent: parent, spawn_reason: "seed")

      expect {
        writer.attach!(child: parent, parent: child, spawn_reason: "seed")
      }.to raise_error(ActiveRecord::RecordInvalid, /circular/)

      expect(parent.reload.parent_agent_id).to be_nil
      expect(active_edges_for(parent)).to be_empty
    end

    it "requires both endpoints" do
      expect { writer.attach!(child: child, parent: nil, spawn_reason: "seed") }.to raise_error(ArgumentError)
      expect { writer.attach!(child: nil, parent: parent, spawn_reason: "seed") }.to raise_error(ArgumentError)
    end

    it "writes an AuditLog entry naming the seam" do
      expect {
        writer.attach!(child: child, parent: parent, spawn_reason: "seed")
      }.to change { AuditLog.where(resource_type: "Ai::AgentLineage").count }.by(1)

      entry = AuditLog.where(resource_type: "Ai::AgentLineage").last
      expect(entry.account).to eq(account)
      expect(entry.metadata["seam"]).to eq("Ai::Agents::HierarchyWriter")
      expect(entry.metadata["child_agent_id"]).to eq(child.id)
      expect(entry.metadata["parent_agent_id"]).to eq(parent.id)
    end

    it "does not audit an unchanged re-attach" do
      writer.attach!(child: child, parent: parent, spawn_reason: "seed")

      expect {
        writer.attach!(child: child, parent: parent, spawn_reason: "seed")
      }.not_to change { AuditLog.where(resource_type: "Ai::AgentLineage").count }
    end

    it "keys a GLOBAL child's edge on the writer's account (a global agent owns none)" do
      global_child = create(:ai_agent, account: nil, creator: user, provider: provider, name: "Global Child")
      global_root  = create(:ai_agent, account: nil, creator: user, provider: provider, name: "Global Root")

      lineage = writer.attach!(child: global_child, parent: global_root, spawn_reason: "seed")

      expect(lineage.account_id).to eq(account.id)
      expect(global_child.reload.parent_agent_id).to eq(global_root.id)
    end
  end

  describe "#ensure_delegation_policy!" do
    it "creates the policy keyed on (agent_id, account_id)" do
      policy = writer.ensure_delegation_policy!(
        agent: child, inheritance_policy: "conservative", max_depth: 2,
        allowed_delegate_types: %w[system-cve-response], allowed_actions: %w[system.cve_triage]
      )

      expect(policy).to be_persisted
      expect(policy.agent_id).to eq(child.id)
      expect(policy.account_id).to eq(account.id)
      expect(policy.inheritance_policy).to eq("conservative")
      expect(policy.max_depth).to eq(2)
      expect(policy.allowed_delegate_types).to eq(%w[system-cve-response])
      expect(policy.delegatable_actions).to eq(%w[system.cve_triage])
    end

    it "updates the existing row in place instead of creating a second one" do
      first = writer.ensure_delegation_policy!(agent: child, inheritance_policy: "conservative", max_depth: 2)

      expect {
        second = writer.ensure_delegation_policy!(agent: child, inheritance_policy: "moderate", max_depth: 3)
        expect(second.id).to eq(first.id)
      }.not_to change(Ai::DelegationPolicy, :count)

      expect(first.reload.inheritance_policy).to eq("moderate")
      expect(first.max_depth).to eq(3)
    end

    it "is scoped to the writer's account: a policy on another account is not the one it upserts" do
      other_account = create(:account)
      foreign = create(:ai_agent, account: other_account, name: "Foreign")
      foreign_policy = create(:ai_delegation_policy, account: other_account, agent: foreign, max_depth: 5)

      writer.ensure_delegation_policy!(agent: child, max_depth: 1)

      expect(foreign_policy.reload.max_depth).to eq(5)
      expect(Ai::DelegationPolicy.where(account: account).pluck(:agent_id)).to eq([ child.id ])
    end

    # A GLOBAL agent owns no account, but the seam still keys its policy on the
    # writer's account rather than writing the account_id-NULL canonical row
    # HIER-P0's migration makes possible: that keying is legal under the old
    # `account_id NOT NULL` schema too, so seeding never depends on which of
    # the two a database is at.
    it "keys a GLOBAL agent's policy on the writer's account, leaving other accounts free to hold their own" do
      global_agent = create(:ai_agent, account: nil, creator: user, provider: provider, name: "Global Agent")
      other_account = create(:account, name: "Other Co")

      seeded = writer.ensure_delegation_policy!(agent: global_agent, inheritance_policy: "moderate", max_depth: 3)

      expect(seeded.account_id).to eq(account.id)
      expect(seeded).not_to be_global
      expect(Ai::DelegationPolicy.resolve_for(agent_id: global_agent.id, account_id: account.id)).to eq(seeded)

      other = create(:ai_delegation_policy, account: other_account, agent: global_agent, max_depth: 1)
      expect(Ai::DelegationPolicy.resolve_for(agent_id: global_agent.id, account_id: other_account.id)).to eq(other)

      expect {
        writer.ensure_delegation_policy!(agent: global_agent, max_depth: 4)
      }.not_to change { other.reload.max_depth }
      expect(seeded.reload.max_depth).to eq(4)
    end

    it "rejects an attribute it does not own" do
      expect {
        writer.ensure_delegation_policy!(agent: child, bogus: 1)
      }.to raise_error(ArgumentError, /bogus/)
    end

    it "writes an AuditLog entry naming the seam and audits nothing on a no-op re-run" do
      expect {
        writer.ensure_delegation_policy!(agent: child, max_depth: 2)
      }.to change { AuditLog.where(resource_type: "Ai::DelegationPolicy").count }.by(1)

      entry = AuditLog.where(resource_type: "Ai::DelegationPolicy").last
      expect(entry.metadata["seam"]).to eq("Ai::Agents::HierarchyWriter")
      expect(entry.metadata["agent_id"]).to eq(child.id)

      expect {
        writer.ensure_delegation_policy!(agent: child, max_depth: 2)
      }.not_to change { AuditLog.where(resource_type: "Ai::DelegationPolicy").count }
    end
  end
end
