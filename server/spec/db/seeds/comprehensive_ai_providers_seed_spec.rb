# frozen_string_literal: true

require "rails_helper"

# IMP-dfaebf1c9019 — the provider catalog seed resolves the bootstrap admin
# account generically. A wizard-created account carries the operator's own
# name and email, so a lookup keyed on the demo account's name/email left it
# with no catalog providers.
RSpec.describe "comprehensive_ai_providers_seed" do
  def load_seed!
    silence_warnings do
      expect { load Rails.root.join("db", "seeds", "comprehensive_ai_providers_seed.rb") }.to output.to_stdout
    end
  end

  let(:catalog_names) { Ai::ProviderCatalog.all.map { |c| c[:name] } }

  before { Role.sync_from_config! }

  context "with a wizard-style account (arbitrary name and email)" do
    let!(:account) { create(:account, name: "Acme Operations") }
    let!(:admin) { create(:user, :super_admin, account: account, email: "ops-lead@acme-ops.example") }

    it "creates the catalog providers for that account, without credentials" do
      load_seed!

      expect(account.ai_providers.where(name: catalog_names).pluck(:name)).to match_array(catalog_names)
      expect(Ai::ProviderCredential.joins(:provider).where(ai_providers: { account_id: account.id })).to be_empty
    end

    it "is idempotent" do
      load_seed!
      expect(account.ai_providers.where(name: catalog_names).count).to eq(catalog_names.size)
      expect { load_seed! }.not_to change { Ai::Provider.where(account: account).count }
    end

    it "targets the super_admin's account, not other accounts" do
      other = create(:account, name: "Bystander")
      create(:user, account: other, email: "someone@bystander.example")

      load_seed!

      expect(other.ai_providers.where(name: catalog_names)).to be_empty
    end
  end

  it "seeds the only account when no super_admin exists" do
    only = create(:account, name: "Solo")

    load_seed!

    expect(only.ai_providers.where(name: catalog_names).count).to eq(catalog_names.size)
  end

  it "keeps the demo account path working" do
    demo = create(:account, name: "Powernode Admin")
    create(:user, account: demo, email: "admin@powernode.org")
    create(:account, name: "Other Tenant")

    load_seed!

    expect(demo.ai_providers.where(name: catalog_names).count).to eq(catalog_names.size)
  end

  it "does not guess between several accounts when none is an admin account" do
    create(:account, name: "One")
    create(:account, name: "Two")

    load_seed!

    expect(Ai::Provider.where(name: catalog_names)).to be_empty
  end

  it "is a no-op with no account yet" do
    expect(Account.count).to eq(0)
    load_seed!
    expect(Ai::Provider.where(name: catalog_names)).to be_empty
  end
end
