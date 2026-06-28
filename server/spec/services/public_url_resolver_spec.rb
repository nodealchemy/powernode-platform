# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublicUrlResolver do
  after { described_class.reset_tenant_resolver! }

  describe ".base_url" do
    it "returns '' (host-relative mode) when nothing is configured" do
      expect(described_class.base_url).to eq("")
    end

    it "uses the global SiteSetting public_base_url (DB-driven)" do
      SiteSetting.set("public_base_url", "https://app.example.com/", setting_type: "string")
      expect(described_class.base_url).to eq("https://app.example.com") # trailing slash trimmed
    end

    it "falls back to ENV APP_BASE_URL when no SiteSetting" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("APP_BASE_URL").and_return("https://env.example.com")
      expect(described_class.base_url).to eq("https://env.example.com")
    end
  end

  describe ".url_for" do
    it "builds a host-relative path in core mode" do
      expect(described_class.url_for("/shared/tok")).to eq("/shared/tok")
    end

    it "builds an absolute URL when a base is configured" do
      SiteSetting.set("public_base_url", "https://app.example.com", setting_type: "string")
      expect(described_class.url_for("shared/tok")).to eq("https://app.example.com/shared/tok")
    end
  end

  describe "business-extension tenant seam" do
    let(:account) { build_stubbed(:account) }

    it "consults a registered tenant resolver FIRST (per-account domain wins)" do
      SiteSetting.set("public_base_url", "https://global.example.com", setting_type: "string")
      described_class.register_tenant_resolver(->(acct) { "https://tenant.example.com" if acct })

      expect(described_class.base_url(account: account)).to eq("https://tenant.example.com")
    end

    it "falls back to global when the tenant resolver returns nil" do
      SiteSetting.set("public_base_url", "https://global.example.com", setting_type: "string")
      described_class.register_tenant_resolver(->(_acct) { nil })

      expect(described_class.base_url(account: account)).to eq("https://global.example.com")
    end

    it "is core-mode safe: no resolver registered → account is ignored" do
      expect(described_class.base_url(account: account)).to eq("")
    end

    it "swallows resolver errors and falls back" do
      described_class.register_tenant_resolver(->(_acct) { raise "boom" })
      expect(described_class.base_url(account: account)).to eq("")
    end
  end
end
