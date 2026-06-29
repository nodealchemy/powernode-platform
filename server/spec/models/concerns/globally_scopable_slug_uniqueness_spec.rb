# frozen_string_literal: true

require "rails_helper"

# Fix for "broken global-content seeds (duplicate-slug aborts)": GloballyScopable
# content models partition slug uniqueness BY SCOPE — unique among GLOBAL rows
# (account_id nil) and within each account — instead of a single global unique
# slug. This lets an account row legitimately reuse (override) a global slug, and
# stops a pre-existing account-scoped shadow from aborting the global content seed.
RSpec.describe "GloballyScopable slug uniqueness (partitioned by scope)" do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  describe KnowledgeBase::Article do
    let(:cat) { create(:kb_category) }

    it "allows a GLOBAL and an ACCOUNT article to share a slug (the override case)" do
      global = create(:kb_article, account: nil, slug: "shared-slug", category: cat)
      owned  = create(:kb_article, account: account, slug: "shared-slug", category: cat)
      expect(global).to be_persisted
      expect(owned).to be_persisted
    end

    it "rejects a second GLOBAL article with the same slug" do
      create(:kb_article, account: nil, slug: "dup-global", category: cat)
      expect { create(:kb_article, account: nil, slug: "dup-global", category: cat) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "rejects two articles in the same account with the same slug" do
      create(:kb_article, account: account, slug: "dup-acct", category: cat)
      expect { create(:kb_article, account: account, slug: "dup-acct", category: cat) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "allows two different accounts to each use the same slug" do
      create(:kb_article, account: account, slug: "per-acct", category: cat)
      expect(create(:kb_article, account: other_account, slug: "per-acct", category: cat)).to be_persisted
    end
  end

  describe Ai::Skill do
    it "allows a GLOBAL and an ACCOUNT skill to share a slug (the override case)" do
      global = create(:ai_skill, account: nil, slug: "shared-skill")
      owned  = create(:ai_skill, account: account, slug: "shared-skill")
      expect(global).to be_persisted
      expect(owned).to be_persisted
    end

    it "rejects a second GLOBAL skill with the same slug" do
      create(:ai_skill, account: nil, slug: "dup-skill")
      expect { create(:ai_skill, account: nil, slug: "dup-skill") }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "allows two different accounts to each use the same skill slug" do
      create(:ai_skill, account: account, slug: "per-acct-skill")
      expect(create(:ai_skill, account: other_account, slug: "per-acct-skill")).to be_persisted
    end
  end
end
