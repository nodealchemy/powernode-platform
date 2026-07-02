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

    # Refinement (crypto protected-path gate false positives): the broad
    # *credential*/*secret* NAME globs must not gate structural/test/concern
    # files that merely carry the word in their filename — only genuine
    # secret-storage surfaces. Directory-form globs stay unconditional.
    context "name-hint refinement (*credential* / *secret* false positives)" do
      it "does NOT match spec/test files merely named credential/secret" do
        expect(described_class.keep_manual?("server/spec/services/ai/provider_management_service/credential_validation_spec.rb")).to be false
        expect(described_class.keep_manual?("server/spec/services/shared/provider_credential_state_spec.rb")).to be false
        expect(described_class.keep_manual?("frontend/src/features/settings/CredentialsForm.test.tsx")).to be false
        expect(described_class.keep_manual?("frontend/src/features/settings/secretRotationBanner.spec.ts")).to be false
      end

      it "does NOT match concern/factory files merely named credential" do
        expect(described_class.keep_manual?("server/app/models/concerns/credential_display.rb")).to be false
        expect(described_class.keep_manual?("server/spec/factories/git_credentials.rb")).to be false
      end

      it "still matches genuine secret-storage files named credential/secret (fail-closed)" do
        expect(described_class.keep_manual?("server/app/lib/secret_store.rb")).to be true
        expect(described_class.keep_manual?("server/app/services/security/secret_store.rb")).to be true
        expect(described_class.keep_manual?("server/app/services/shared/provider_credential_state.rb")).to be true
      end

      it "keeps directory-form and Rails-secret globs unconditional, even for specs/concerns" do
        expect(described_class.keep_manual?("server/spec/services/vault/client_spec.rb")).to be true
        expect(described_class.keep_manual?("server/app/models/concerns/signing/key_rotation.rb")).to be true
        expect(described_class.keep_manual?("config/credentials/production.yml.enc")).to be true
        expect(described_class.keep_manual?(".env.test")).to be true
      end

      it "keeps key-material name globs (*private_key*/*api_key*/*signer*) unconditional" do
        expect(described_class.keep_manual?("server/spec/lib/private_key_loader_spec.rb")).to be true
        expect(described_class.keep_manual?("server/app/models/concerns/api_key_hashing.rb")).to be true
      end
    end
  end

  describe ".keep_manual_pattern" do
    it "returns the matching glob for a keep-manual path" do
      expect(described_class.keep_manual_pattern("server/app/services/payments/charge.rb")).to eq("**/payments/**")
      expect(described_class.keep_manual_pattern("server/app/lib/secret_store.rb")).to eq("**/*secret*")
    end

    it "returns nil for exempt structural/test files and ordinary paths" do
      expect(described_class.keep_manual_pattern("server/spec/services/x/credential_validation_spec.rb")).to be_nil
      expect(described_class.keep_manual_pattern("server/app/models/user.rb")).to be_nil
      expect(described_class.keep_manual_pattern(nil)).to be_nil
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
