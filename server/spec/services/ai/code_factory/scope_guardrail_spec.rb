# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::CodeFactory::ScopeGuardrail do
  let(:account) { create(:account) }

  describe "#evaluate" do
    it "allows ordinary code paths" do
      result = described_class.new.evaluate(["server/app/models/user.rb", "frontend/src/App.tsx"])

      expect(result[:allowed]).to be true
      expect(result[:violations]).to eq([])
      expect(result[:highest_tier]).to be_nil
      expect(result[:summary]).to be_nil
    end

    it "treats an empty changeset as allowed" do
      result = described_class.new.evaluate([])

      expect(result[:allowed]).to be true
      expect(result[:violations]).to eq([])
      expect(result[:highest_tier]).to be_nil
    end

    it "ignores blank entries" do
      result = described_class.new.evaluate(["", nil, "  "])

      expect(result[:allowed]).to be true
    end

    it "blocks payments paths" do
      result = described_class.new.evaluate(["server/app/services/payments/charge.rb"])

      expect(result[:allowed]).to be false
      expect(result[:violations].first[:file]).to eq("server/app/services/payments/charge.rb")
      expect(result[:violations].first[:reason]).to match(/protected path/)
    end

    it "blocks auth paths" do
      result = described_class.new.evaluate(["server/app/controllers/auth/sessions_controller.rb"])
      expect(result[:allowed]).to be false
    end

    it "blocks credentials paths" do
      result = described_class.new.evaluate(["config/credentials.yml.enc"])
      expect(result[:allowed]).to be false
    end

    it "blocks private_key paths" do
      result = described_class.new.evaluate(["server/lib/private_key_loader.rb"])
      expect(result[:allowed]).to be false
    end

    it "reports every violating file with a summary" do
      files = ["server/app/services/payments/charge.rb", "server/app/lib/secret_store.rb"]
      result = described_class.new.evaluate(files)

      expect(result[:allowed]).to be false
      expect(result[:violations].map { |v| v[:file] }).to match_array(files)
      expect(result[:summary]).to eq("blocked 2 file(s): #{files.join(', ')}")
    end

    it "does NOT block migrations or schema (deliberately excluded)" do
      result = described_class.new.evaluate([
        "server/db/migrate/20260101000000_add_thing.rb",
        "server/db/schema.rb"
      ])
      expect(result[:allowed]).to be true
    end

    it "honours an allow override that exempts a protected path" do
      config = { "allow" => ["server/app/services/payments/**"] }
      result = described_class.new(config: config).evaluate(["server/app/services/payments/charge.rb"])

      expect(result[:allowed]).to be true
      expect(result[:violations]).to eq([])
    end

    it "derives its default denylist from the policy catalog (G14)" do
      expect(described_class::DEFAULT_DENYLIST).to equal(Ai::Loop::PolicyCatalog::KEEP_MANUAL_DENYLIST)

      # A path the catalog marks keep-manual is blocked by the guardrail.
      manual_path = "server/app/services/wallet/ledger.rb"
      expect(Ai::Loop::PolicyCatalog.keep_manual?(manual_path)).to be true
      expect(described_class.new.evaluate([manual_path])[:allowed]).to be false
    end

    it "does NOT block structural/test files merely named credential (catalog refinement)" do
      result = described_class.new.evaluate([
        "server/spec/services/ai/provider_management_service/credential_validation_spec.rb",
        "server/app/models/concerns/credential_display.rb"
      ])

      expect(result[:allowed]).to be true
      expect(result[:violations]).to eq([])
    end

    it "extends the denylist via config deny" do
      config = { "deny" => ["**/danger_zone/**"] }
      result = described_class.new(config: config).evaluate(["server/app/danger_zone/x.rb"])

      expect(result[:allowed]).to be false
      expect(result[:violations].first[:reason]).to match(/danger_zone/)
    end

    it "blocks a critical-tier change classified by a RiskContract" do
      contract = Ai::CodeFactory::RiskContract.create!(
        account: account, name: "c", status: "active",
        risk_tiers: [{ "tier" => "critical", "patterns" => ["**/core_engine/**"] }]
      )

      result = described_class.new(risk_contract: contract).evaluate(["server/app/core_engine/x.rb"])

      expect(result[:allowed]).to be false
      expect(result[:highest_tier]).to eq("critical")
      expect(result[:violations].first[:reason]).to match(/critical-tier change/)
    end

    it "does not double-flag a file caught by both denylist and critical tier" do
      contract = Ai::CodeFactory::RiskContract.create!(
        account: account, name: "c", status: "active",
        risk_tiers: [{ "tier" => "critical", "patterns" => ["**/payments/**"] }]
      )

      result = described_class.new(risk_contract: contract).evaluate(["server/app/payments/charge.rb"])

      expect(result[:violations].size).to eq(1)
      expect(result[:violations].first[:reason]).to match(/protected path/)
    end
  end
end
