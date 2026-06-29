# frozen_string_literal: true

require "rails_helper"

# Companion to globally_scopable_slug_uniqueness_spec for Ai::DevopsTemplate, the
# other GloballyScopable model seeded as GLOBAL content (account_id nil, upserted
# by source_key = slug). Slug uniqueness is partitioned by scope: a GLOBAL
# template and an account override may share a slug; two globals (or two rows in
# one account) with the same slug still collide.
RSpec.describe Ai::DevopsTemplate, "scope-partitioned slug uniqueness" do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  it "allows a GLOBAL and an ACCOUNT template to share a slug (override case)" do
    global = create(:ai_devops_template, account: nil, slug: "shared-tpl")
    owned  = create(:ai_devops_template, account: account, slug: "shared-tpl")
    expect(global.account_id).to be_nil
    expect(global).to be_persisted
    expect(owned.account_id).to eq(account.id)
    expect(owned).to be_persisted
  end

  it "rejects a second GLOBAL template with the same slug" do
    create(:ai_devops_template, account: nil, slug: "dup-tpl")
    expect { create(:ai_devops_template, account: nil, slug: "dup-tpl") }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it "rejects two templates in the same account with the same slug" do
    create(:ai_devops_template, account: account, slug: "dup-acct-tpl")
    expect { create(:ai_devops_template, account: account, slug: "dup-acct-tpl") }
      .to raise_error(ActiveRecord::RecordInvalid)
  end

  it "allows two different accounts to each use the same slug" do
    create(:ai_devops_template, account: account, slug: "per-acct-tpl")
    expect(create(:ai_devops_template, account: other_account, slug: "per-acct-tpl")).to be_persisted
  end
end
