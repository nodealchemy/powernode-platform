# frozen_string_literal: true

require "rails_helper"

RSpec.describe Setup::StepRegistry do
  let(:account) { create(:account) }

  describe ".steps_for" do
    it "returns ordered core steps annotated with completion" do
      steps = described_class.steps_for(account)
      keys = steps.map { |s| s[:key] }

      expect(keys).to include("admin", "domain")
      expect(keys.index("admin")).to be < keys.index("domain")
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
