# frozen_string_literal: true

require "rails_helper"

# Ai::Agent slug uniqueness is partitioned by scope (model: uniqueness scope:
# :account_id; DB: partial unique indexes from 20260629000013). generate_slug
# dedupes WITHIN scope, so a global agent and an account override can hold the
# same slug, while collisions inside one scope still get a unique suffix.
RSpec.describe Ai::Agent, "scope-partitioned slug uniqueness" do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:provider) { create(:ai_provider, provider_type: "openai") }

  def global_agent(name)
    create(:ai_agent, account: nil, creator: create(:user, account: account),
                      provider: provider, status: "active", name: name)
  end

  it "lets an ACCOUNT agent keep the same slug as the GLOBAL agent it overrides" do
    g = global_agent("Override Planner")
    a = create(:ai_agent, account: account, provider: provider, status: "active", name: "Override Planner")

    expect(g.account_id).to be_nil
    expect(g.slug).to eq("override-planner")
    expect(a.account_id).to eq(account.id)
    expect(a.slug).to eq("override-planner") # same slug, different scope — the override case
    expect(a).to be_persisted
  end

  # Names differ (so the name-uniqueness validation passes) but parameterize to
  # the same base slug — exercising slug dedup within a single scope.
  it "dedupes slug-colliding GLOBAL agents within the global scope" do
    first  = global_agent("Dup Planner")
    second = global_agent("Dup Planner!")

    expect(first.slug).to eq("dup-planner")
    expect(second.slug).to eq("dup-planner-1")
  end

  it "dedupes slug-colliding agents within one account" do
    first  = create(:ai_agent, account: account, provider: provider, status: "active", name: "Acct Planner")
    second = create(:ai_agent, account: account, provider: provider, status: "active", name: "Acct Planner!")

    expect(first.slug).to eq("acct-planner")
    expect(second.slug).to eq("acct-planner-1")
  end

  it "lets two different accounts each hold the same slug" do
    a = create(:ai_agent, account: account, provider: provider, status: "active", name: "Cross Acct")
    b = create(:ai_agent, account: other_account, provider: provider, status: "active", name: "Cross Acct")

    expect(a.slug).to eq("cross-acct")
    expect(b.slug).to eq("cross-acct")
    expect(b).to be_persisted
  end
end
