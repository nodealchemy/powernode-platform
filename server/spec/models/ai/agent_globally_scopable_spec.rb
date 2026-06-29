# frozen_string_literal: true

require "rails_helper"

# Foundation for global/account agents (mirrors Ai::Skill). Fundamental
# core/system agents become GLOBAL (account_id nil); accounts get editable
# overrides/clones that win over the global default. Behavior-preserving for
# existing account-scoped agents.
RSpec.describe "Ai::Agent global/account scoping" do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, :openai, account: account) }

  def global_agent(name:, slug:)
    create(:ai_agent, account: nil, name: name, slug: slug, agent_type: "monitor",
                      provider: provider, creator: user, source_key: slug)
  end

  describe "a global agent" do
    it "persists with a nil account_id and reports global?" do
      agent = global_agent(name: "Fleet Autonomy", slug: "fleet-autonomy")
      expect(agent).to be_persisted
      expect(agent.account_id).to be_nil
      expect(agent.global?).to be true
    end

    it "is visible to every account via for_account, alongside the account's own" do
      g = global_agent(name: "Fleet Autonomy", slug: "fleet-autonomy")
      mine = create(:ai_agent, account: account, name: "My Bot", slug: "my-bot")

      visible = Ai::Agent.for_account(account.id)
      expect(visible).to include(g, mine)
      # other account sees the global but not my account's own
      expect(Ai::Agent.for_account(other_account.id)).to include(g)
      expect(Ai::Agent.for_account(other_account.id)).not_to include(mine)
    end
  end

  describe ".resolve_for (override-aware)" do
    it "returns the GLOBAL default when the account has no override" do
      g = global_agent(name: "Fleet Autonomy", slug: "fleet-autonomy")
      resolved = Ai::Agent.resolve_for(account.id, name: "Fleet Autonomy", agent_type: "monitor")
      expect(resolved).to eq(g)
    end

    it "returns the ACCOUNT's own override in preference to the global default" do
      global_agent(name: "Fleet Autonomy", slug: "fleet-autonomy")
      override = create(:ai_agent, account: account, name: "Fleet Autonomy",
                                   slug: "fleet-autonomy-acct", agent_type: "monitor")

      resolved = Ai::Agent.resolve_for(account.id, name: "Fleet Autonomy", agent_type: "monitor")
      expect(resolved).to eq(override)
      # a different account still gets the global
      expect(Ai::Agent.resolve_for(other_account.id, name: "Fleet Autonomy", agent_type: "monitor").global?).to be true
    end
  end

  describe "#clone_to_account (the override mechanism)" do
    it "clones a global agent into an account as an editable copy with provenance" do
      g = global_agent(name: "Fleet Autonomy", slug: "fleet-autonomy")
      clone = g.clone_to_account(account)

      expect(clone.account_id).to eq(account.id)
      expect(clone.cloned_from_id).to eq(g.id)
      expect(clone.global?).to be false
      expect(clone.clone?).to be true
      expect(clone.slug).not_to eq(g.slug) # globally-unique slug suffixed
    end
  end

  describe "#model_resolution for a global agent" do
    it "resolves under a per-account context via resolving_account" do
      create(:ai_provider_credential, account: account, provider: provider)
      g = global_agent(name: "Fleet Autonomy", slug: "fleet-autonomy")

      g.resolving_account = account
      expect(g.resolved_model).to be_present
      expect(g.resolved_provider).to be_present
    end

    it "falls back to the seeded provider default (no crash) without a resolving account" do
      g = global_agent(name: "Fleet Autonomy", slug: "fleet-autonomy")
      expect { g.resolved_model }.not_to raise_error
      expect(g.resolved_provider).to eq(provider)
    end
  end

  describe "existing account-scoped agents are unaffected" do
    it "still creates and resolves account agents normally" do
      a = create(:ai_agent, account: account, name: "Acct Bot", slug: "acct-bot")
      expect(a.global?).to be false
      expect(Ai::Agent.for_account(account.id)).to include(a)
    end
  end
end
