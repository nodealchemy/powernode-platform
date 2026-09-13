# frozen_string_literal: true

require "rails_helper"

# HIER-P0 — Ai::DelegationPolicy uniqueness is ACCOUNT-scoped.
#
# The table and the REST controller are account-scoped, but the model validated
# `agent_id` unique GLOBALLY (and the schema carried a unique index on agent_id
# alone). Under the canonical rule (official agents are GLOBAL seeded rows,
# account_id NULL; account agents are clones) two accounts customising the SAME
# canonical agent's delegation authority collided on the second write, and a
# canonical (account-less) row for the agent was impossible because account_id
# was NOT NULL.
#
# Three shapes, pinned separately because the model validation and the DB
# indexes are two different guards that must agree:
#   * same agent, two accounts       -> both rows persist
#   * same agent, same account twice -> the second is refused
#   * a global (account nil) row     -> allowed once, refused twice
RSpec.describe Ai::DelegationPolicy, type: :model do
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }
  let(:owner)     { create(:user, account: account_a) }
  let(:provider)  { create(:ai_provider, account: account_a) }

  # A GLOBAL canonical agent, the shape the seeds write.
  let(:canonical_agent) do
    create(:ai_agent, account: nil, name: "System Concierge", agent_type: "assistant",
                      source_key: "system-concierge", is_system: true,
                      creator: owner, provider: provider)
  end

  describe "uniqueness of agent_id scoped to account_id" do
    it "lets two accounts each hold a policy for the same canonical agent" do
      create(:ai_delegation_policy, account: account_a, agent: canonical_agent, max_depth: 2)

      second = build(:ai_delegation_policy, account: account_b, agent: canonical_agent, max_depth: 4)

      expect(second).to be_valid
      expect { second.save! }.to change { described_class.where(agent_id: canonical_agent.id).count }.from(1).to(2)
    end

    it "refuses a second policy for the same agent in the same account" do
      create(:ai_delegation_policy, account: account_a, agent: canonical_agent)

      duplicate = build(:ai_delegation_policy, account: account_a, agent: canonical_agent)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:agent_id]).to be_present
      # The DB guard must agree with the validation — bypass it and expect the
      # partial unique index to refuse the row.
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows exactly one global (account-less) row per agent" do
      global_row = build(:ai_delegation_policy, account: nil, agent: canonical_agent, max_depth: 1)
      expect(global_row).to be_valid
      global_row.save!

      duplicate = build(:ai_delegation_policy, account: nil, agent: canonical_agent, max_depth: 3)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:agent_id]).to be_present
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "keeps a global row and an account row for the same agent side by side" do
      create(:ai_delegation_policy, account: nil, agent: canonical_agent, max_depth: 1)

      account_row = build(:ai_delegation_policy, account: account_a, agent: canonical_agent, max_depth: 5)

      expect(account_row).to be_valid
      expect { account_row.save! }.not_to raise_error
    end
  end

  describe ".resolve_for" do
    it "prefers the account's own row over the canonical global row" do
      global_row  = create(:ai_delegation_policy, account: nil, agent: canonical_agent, max_depth: 1)
      account_row = create(:ai_delegation_policy, account: account_a, agent: canonical_agent, max_depth: 5)

      expect(described_class.resolve_for(agent_id: canonical_agent.id, account_id: account_a.id)).to eq(account_row)
      expect(described_class.resolve_for(agent_id: canonical_agent.id, account_id: account_b.id)).to eq(global_row)
    end

    it "returns nil when neither an account row nor a global row exists" do
      expect(described_class.resolve_for(agent_id: canonical_agent.id, account_id: account_a.id)).to be_nil
    end
  end

  # HIER-P0 (E4) — an EMPTY allowed_delegate_types means NONE, not ANY.
  #
  # #allows_delegate_type? was `allowed_delegate_types.blank? || include?`, so a
  # leaf whose list was deliberately left empty read as UNRESTRICTED. Nine
  # canonical leaves under Powernode Assistant are seeded exactly that way
  # (CORE_HIERARCHY_CHILD_DELEGATION in ai_agent_hierarchy_seed.rb), and the
  # seeds had already grown a "none" sentinel to work around the fail-open
  # (RELEASE_MANAGER_NO_DELEGATES, CanonicalTeamReconciler::NO_SUCH_TYPE_SENTINEL).
  #
  # The governance opt-in is the POLICY ROW, not the list: no policy at all
  # still means unrestricted (Ai::Autonomy::DelegationAuthorityService returns
  # allowed: true when .resolve_for finds nothing). Once a row exists, its
  # allowlist is read literally.
  describe "#allows_delegate_type?" do
    let(:policy) { build(:ai_delegation_policy, account: account_a, agent: canonical_agent) }

    it "admits a type on the list" do
      policy.allowed_delegate_types = %w[monitor assistant]

      expect(policy.allows_delegate_type?("monitor")).to be(true)
      expect(policy.allows_delegate_type?(:assistant)).to be(true)
    end

    it "refuses a type that is not on the list" do
      policy.allowed_delegate_types = %w[monitor]

      expect(policy.allows_delegate_type?("data_analyst")).to be(false)
    end

    it "refuses EVERY type when the list is empty" do
      policy.allowed_delegate_types = []

      expect(policy.allows_delegate_type?("monitor")).to be(false)
      expect(policy.allows_delegate_type?("assistant")).to be(false)
      expect(policy.allows_delegate_type?("")).to be(false)
    end

    it "refuses every type when the list is nil" do
      # Not persistable — the column is jsonb NOT NULL DEFAULT '[]' — but an
      # in-memory nil must not reopen the fail-open the empty list just closed.
      policy.allowed_delegate_types = nil

      expect(policy.allows_delegate_type?("monitor")).to be(false)
    end

    it "reads the seeded no-delegates sentinel as delegating to nobody real" do
      policy.allowed_delegate_types = [ Ai::Teams::CanonicalTeamReconciler::NO_SUCH_TYPE_SENTINEL ]

      expect(policy.allows_delegate_type?("monitor")).to be(false)
      expect(policy.allows_delegate_type?("assistant")).to be(false)
    end

    it "leaves #allows_action? alone — delegatable_actions keeps blank-means-any" do
      # Deliberately NOT changed by E4: the audit's HIER-P0 finding is about
      # delegate types. Pinned so the asymmetry is a recorded decision rather
      # than an oversight, and so a later change to it is deliberate.
      policy.delegatable_actions = []

      expect(policy.allows_action?("anything")).to be(true)
    end
  end
end
