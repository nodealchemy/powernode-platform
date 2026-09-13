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

  end

  # IMP-d2873a16567e — a BLANK delegatable_actions means NONE too.
  #
  # E4 left #allows_action? reading blank as "any action", so the two lists on
  # one row meant opposite things when empty, and every derivation of one list
  # from another had to know which. Operator rule 2026-09-08: a blank
  # permission/scope list means DENY. The list is now read literally.
  describe "#allows_action?" do
    let(:policy) { build(:ai_delegation_policy, account: account_a, agent: canonical_agent) }

    it "admits an action on the list" do
      policy.delegatable_actions = %w[execute]

      expect(policy.allows_action?("execute")).to be(true)
      expect(policy.allows_action?(:execute)).to be(true)
    end

    it "refuses an action that is not on the list" do
      policy.delegatable_actions = %w[execute]

      expect(policy.allows_action?("deploy")).to be(false)
    end

    it "refuses EVERY action when the list is empty" do
      policy.delegatable_actions = []

      expect(policy.allows_action?("execute")).to be(false)
      expect(policy.allows_action?("anything")).to be(false)
    end

    it "refuses every action when the list is nil" do
      policy.delegatable_actions = nil

      expect(policy.allows_action?("execute")).to be(false)
    end
  end

  # DELEGATABLE_ACTIONS is how "every action delegation is checked as" is
  # spelled explicitly — by the hierarchy seeds, the system hierarchy and the
  # migration that repaired blank rows. It must name what the doors pass.
  describe "DELEGATABLE_ACTIONS" do
    it "covers the action type every delegation door checks" do
      expect(described_class::DELEGATABLE_ACTIONS)
        .to include(Ai::TeamStrategies::HierarchicalStrategy::DELEGATED_ACTION_TYPE)
    end
  end

  # THE ORACLE the finding asked for: narrowing a blank parent by a non-empty
  # need must permit strictly less than the parent — which, with a blank
  # parent, is nothing. Under blank-means-any the obvious intersection came out
  # empty and so granted everything.
  describe ".narrow" do
    let(:need) { %w[assistant code_assistant monitor] }

    def permits(list, candidates)
      row = described_class.new(allowed_delegate_types: list)
      candidates.select { |type| row.allows_delegate_type?(type) }
    end

    it "grants nothing when the parent's list is empty" do
      narrowed = described_class.narrow(held: [], needed: need)

      expect(narrowed).to eq([])
      expect(permits(narrowed, need + %w[data_analyst])).to be_empty
    end

    it "grants only the intersection — never a value the parent lacked" do
      narrowed = described_class.narrow(held: %w[assistant monitor data_analyst], needed: need)

      expect(narrowed).to match_array(%w[assistant monitor])
    end

    it "bounds an ABSENT parent (no policy row, so ungoverned) by the need alone" do
      expect(described_class.narrow(held: nil, needed: need)).to match_array(need)
    end

    it "never returns more than the parent permits" do
      held = %w[monitor]
      narrowed = described_class.narrow(held: held, needed: need)

      expect(permits(narrowed, need) - permits(held, need)).to be_empty
    end
  end
end
