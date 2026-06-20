# frozen_string_literal: true

require "rails_helper"

RSpec.describe Setup::SeedService do
  let(:account) { create(:account) }

  it "is a no-op when no :account_seeder provider is registered (core mode)" do
    allow(Powernode::ExtensionRegistry).to receive(:provider).with(:account_seeder).and_return(nil)

    expect(described_class.run!(account)).to eq({ seeded: false, reason: "no_seeder" })
  end

  it "delegates to a registered seeder with the collected domain" do
    seeder = double("seeder")
    allow(Powernode::ExtensionRegistry).to receive(:provider).with(:account_seeder).and_return(seeder)
    SiteSetting.set("domain", "fleet.example.com", is_public: true)

    expect(seeder).to receive(:call).with(account: account, domain: "fleet.example.com", only_if_empty: true)
    expect(described_class.run!(account)).to eq({ seeded: true })
  end

  it "defaults the domain to powernode.internal when unset" do
    seeder = double("seeder")
    allow(Powernode::ExtensionRegistry).to receive(:provider).with(:account_seeder).and_return(seeder)

    expect(seeder).to receive(:call).with(hash_including(domain: "powernode.internal"))
    described_class.run!(account)
  end

  it "returns an error result (never raises) when the seeder blows up" do
    seeder = double("seeder")
    allow(Powernode::ExtensionRegistry).to receive(:provider).with(:account_seeder).and_return(seeder)
    allow(seeder).to receive(:call).and_raise(StandardError, "boom")

    expect(described_class.run!(account)).to eq({ seeded: false, reason: "error" })
  end
end
