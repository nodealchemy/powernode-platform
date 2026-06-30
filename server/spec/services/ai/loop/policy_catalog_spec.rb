# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Loop::PolicyCatalog do
  describe ".keep_manual?" do
    it "matches protected payment/billing globs" do
      expect(described_class.keep_manual?("server/app/services/payments/charge.rb")).to be true
      expect(described_class.keep_manual?("server/app/services/billing/invoice.rb")).to be true
    end

    it "matches auth / authorization / permission globs" do
      expect(described_class.keep_manual?("server/app/controllers/auth/sessions_controller.rb")).to be true
      expect(described_class.keep_manual?("server/app/policies/authorization/gate.rb")).to be true
      expect(described_class.keep_manual?("server/app/models/permissions/grant.rb")).to be true
    end

    it "matches credential / secret / vault / key / signing / wallet globs" do
      expect(described_class.keep_manual?("config/credentials.yml.enc")).to be true
      expect(described_class.keep_manual?("server/app/lib/secret_store.rb")).to be true
      expect(described_class.keep_manual?("server/app/services/vault/client.rb")).to be true
      expect(described_class.keep_manual?("server/lib/private_key_loader.rb")).to be true
      expect(described_class.keep_manual?("server/app/services/signing/signer.rb")).to be true
      expect(described_class.keep_manual?("server/app/services/wallet/ledger.rb")).to be true
    end

    it "matches the Rails secret files (.env / master.key / credentials*)" do
      expect(described_class.keep_manual?(".env.production")).to be true
      expect(described_class.keep_manual?("config/master.key")).to be true
    end

    it "does NOT match ordinary code paths" do
      expect(described_class.keep_manual?("server/app/models/user.rb")).to be false
      expect(described_class.keep_manual?("frontend/src/App.tsx")).to be false
      expect(described_class.keep_manual?("server/db/migrate/20260101000000_add_thing.rb")).to be false
    end

    it "is false for blank input" do
      expect(described_class.keep_manual?(nil)).to be false
      expect(described_class.keep_manual?("")).to be false
    end
  end

  describe ".good_first?" do
    it "recognises the loop-friendly categories" do
      %w[ci_triage dependency_bump lint_fix test_fix doc_update].each do |category|
        expect(described_class.good_first?(category)).to be true
      end
    end

    it "accepts symbols too" do
      expect(described_class.good_first?(:lint_fix)).to be true
    end

    it "rejects keep-manual categories" do
      expect(described_class.good_first?("auth")).to be false
      expect(described_class.good_first?("payments")).to be false
      expect(described_class.good_first?(nil)).to be false
    end
  end

  describe ".manual_paths" do
    it "returns only the keep-manual subset of the given paths" do
      paths = [
        "server/app/models/user.rb",
        "server/app/services/payments/charge.rb",
        "frontend/src/App.tsx",
        "config/master.key"
      ]

      expect(described_class.manual_paths(paths)).to match_array(
        ["server/app/services/payments/charge.rb", "config/master.key"]
      )
    end

    it "returns [] when no path is keep-manual" do
      expect(described_class.manual_paths(["server/app/models/user.rb"])).to eq([])
    end

    it "ignores blank entries" do
      expect(described_class.manual_paths(["", nil, "  "])).to eq([])
    end
  end
end
