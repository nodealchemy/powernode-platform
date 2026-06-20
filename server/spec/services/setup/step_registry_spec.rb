# frozen_string_literal: true

require "rails_helper"

RSpec.describe Setup::StepRegistry do
  let(:account) { create(:account) }

  describe ".steps_for" do
    it "returns ordered core steps annotated with completion" do
      steps = described_class.steps_for(account)
      keys = steps.map { |s| s[:key] }

      expect(keys).to include("admin", "domain", "email", "general_settings")
      expect(keys.index("admin")).to be < keys.index("domain")
      expect(keys.index("domain")).to be < keys.index("email")
      expect(keys.index("email")).to be < keys.index("general_settings")
      expect(steps.find { |s| s[:key] == "domain" }[:completed]).to be(false)
    end

    it "marks the admin step complete once a user exists" do
      create(:user, account: account)
      admin = described_class.steps_for(account).find { |s| s[:key] == "admin" }
      expect(admin[:completed]).to be(true)
    end

    it "marks a core step complete after its stamp, with a timestamp" do
      account.mark_setup_step!("domain")
      domain = described_class.steps_for(account).find { |s| s[:key] == "domain" }
      expect(domain[:completed]).to be(true)
      expect(domain[:completed_at]).to be_present
    end
  end

  describe "component-based steps" do
    it "includes the extension_selection step with a component and no schema" do
      ext = described_class.steps_for(account).find { |s| s[:key] == "extension_selection" }
      expect(ext[:component]).to eq("core/extension_selection")
      expect(ext[:schema]).to be_nil
    end
  end

  describe "provider steps (2d)" do
    it "includes ai/cloud/git component steps ordered after extensions, before seed" do
      keys = described_class.steps_for(account).map { |s| s[:key] }

      expect(keys).to include("ai_provider", "cloud_provider", "git_provider")
      expect(keys.index("extension_selection")).to be < keys.index("ai_provider")
      expect(keys.index("ai_provider")).to be < keys.index("cloud_provider")
      expect(keys.index("cloud_provider")).to be < keys.index("git_provider")
      expect(keys.index("git_provider")).to be < keys.index("seed")
    end

    it "resolves provider-step completion from credential presence (per category)" do
      allow(Shared::ProviderCredentialState).to receive(:has_credentials?).and_return(false)
      allow(Shared::ProviderCredentialState).to receive(:has_credentials?).with(account, "ai").and_return(true)

      steps = described_class.steps_for(account)
      expect(steps.find { |s| s[:key] == "ai_provider" }[:completed]).to be(true)
      expect(steps.find { |s| s[:key] == "cloud_provider" }[:completed]).to be(false)
    end
  end

  describe "extension-step completion (Phase 4)" do
    let(:ext_step) do
      {
        key: "testext.foo", title: "Foo", description: "Configure foo.", order: 50,
        required: false, owner: "testext", component: "@ext/testext/Foo",
        endpoint: "/api/v1/setup/extensions/testext/foo"
      }
    end

    before { allow(described_class).to receive(:extension_steps).and_return([ext_step]) }

    it "is incomplete until the extension is configured, then complete with a timestamp" do
      step = described_class.steps_for(account).find { |s| s[:key] == "testext.foo" }
      expect(step[:completed]).to be(false)

      account.mark_extension_configured!("testext")
      step = described_class.steps_for(account).find { |s| s[:key] == "testext.foo" }
      expect(step[:completed]).to be(true)
      expect(step[:completed_at]).to be_present
    end

    it "lists the extension in pending_extension_slugs until configured" do
      expect(described_class.pending_extension_slugs(account)).to include("testext")
      account.mark_extension_configured!("testext")
      expect(described_class.pending_extension_slugs(account)).not_to include("testext")
    end

    it "does not let pending extension steps block bootstrap" do
      # admin exists => required core steps done => bootstrap complete regardless of ext.
      create(:user, account: account)
      expect(described_class.bootstrap_complete?(account)).to be(true)
    end
  end

  describe ".bootstrap_complete?" do
    it "is false with no users and true once an admin exists" do
      expect(described_class.bootstrap_complete?(account)).to be(false)
      create(:user, account: account)
      expect(described_class.bootstrap_complete?(account)).to be(true)
    end
  end

  describe ".find" do
    it "locates a core step definition by key" do
      expect(described_class.find("domain")[:endpoint]).to eq("/api/v1/setup/steps/domain")
    end

    it "returns nil for an unknown key" do
      expect(described_class.find("nope")).to be_nil
    end
  end

  describe ".pending" do
    it "groups incomplete steps by owner" do
      groups = described_class.pending(account)
      core = groups.find { |g| g[:owner] == "core" }
      expect(core[:steps].map { |s| s[:key] }).to include("admin", "domain")
    end
  end
end
