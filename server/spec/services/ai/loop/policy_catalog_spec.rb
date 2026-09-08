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

  # IMP-a25913975485 — the globs are lowercase and the matcher was case-sensitive,
  # so **/*credential* and **/*secret* only ever matched snake_case Ruby paths.
  # Frontend files are PascalCase/camelCase, which made every TSX credential
  # surface invisible to the guard: IMP-18832c3c6128 added a panel that lists and
  # deletes stored cloud credentials and closed unchallenged, while a snake_case
  # controller touching the same domain in the same session was blocked.
  describe "case-insensitive name hints" do
    it "treats a PascalCase credential component as keep-manual" do
      expect(
        described_class.keep_manual?(
          "extensions/system/frontend/src/features/system/components/providers/ProviderCredentialsPanel.tsx"
        )
      ).to be true
    end

    it "treats a camelCase credential api module as keep-manual" do
      expect(
        described_class.keep_manual?(
          "extensions/system/frontend/src/features/system/services/api/providerCredentialsApi.ts"
        )
      ).to be true
    end

  end

  # IMP-0079b72da3cc — the key-material hints are the one family where a glob
  # cannot express the rule. They need to be separator-agnostic (api_key,
  # api-key, apiKey, ApiKey are one concept) AND word-bounded (*signer* must not
  # claim "designer"). fnmatch can do neither, so these three moved to regexes
  # over a normalised path while everything else stays a glob.
  describe "key-material name hints" do
    it "matches every separator convention for the same concept" do
      %w[
        frontend/src/settings/ApiKeyForm.tsx
        frontend/src/settings/apiKeyForm.tsx
        frontend/src/settings/api-key-form.tsx
        frontend/src/settings/api_key_form.tsx
        frontend/src/settings/APIKeyForm.tsx
        frontend/src/settings/ApiKeysPage.tsx
        frontend/src/settings/APIKEY.tsx
        frontend/src/settings/apikey.ts
        frontend/src/settings/privatekey.rb
        frontend/src/components/settings/ApiKeyForm.tsx
        frontend/src/features/settings/PrivateKeyUpload.tsx
      ].each do |path|
        expect(described_class.keep_manual?(path)).to be(true), "expected #{path} to be keep-manual"
      end
    end

    it "matches the private-key and signer families the same way" do
      %w[
        server/lib/private_key_loader.rb
        frontend/src/settings/PrivateKeyUpload.tsx
        frontend/src/settings/private-key-upload.tsx
        server/app/services/signer.rb
        server/app/services/RequestSigner.rb
        server/app/services/request-signer.rb
      ].each do |path|
        expect(described_class.keep_manual?(path)).to be(true), "expected #{path} to be keep-manual"
      end
    end

    # The false positive this replaces. "**/*signer*" is a substring match, so it
    # claimed every path containing "designer" — the topology-designer seed and
    # its agent skeleton were keep-manual for a reason that has nothing to do
    # with signing keys. Word boundaries, not an exemption list, because the
    # problem is the matcher rather than these particular files.
    it "does not claim a word that merely contains a key-material token" do
      [
        "extensions/system/server/db/seeds/system_topology_designer_agent.rb",
        ".claude/agents/powernode/system-topology-designer.md",
        "frontend/src/components/DesignerCanvas.tsx",
        "frontend/src/components/SignerlessFlow.tsx",
        # The TRAILING boundary specifically. Without it these two match, and
        # the signer examples above would not have caught that: every one of
        # them ends the token at a separator or end-of-string.
        "frontend/src/features/devops/ApiKeywordFilter.tsx",
        "server/app/services/api_keyserver.rb"
      ].each do |path|
        expect(described_class.keep_manual?(path)).to be(false), "expected #{path} NOT to be keep-manual"
      end
    end

    it "normalises separators and camel boundaries before matching" do
      # Pinned directly, because a failure here is otherwise reported as a
      # mysterious keep_manual? result three layers up. Both camel rules are
      # exercised: fooBar splits at the lower-to-upper transition, APIKey needs
      # the acronym rule because there is no such transition at the K.
      expect(described_class.normalize_for_hint("frontend/src/settings/ApiKeyForm.tsx"))
        .to eq("frontend_src_settings_api_key_form_tsx")
      expect(described_class.normalize_for_hint("server/lib/private-key-loader.rb"))
        .to eq("server_lib_private_key_loader_rb")
      expect(described_class.normalize_for_hint("a/APIKeyForm.tsx")).to eq("a_api_key_form_tsx")
      # "designer" survives as ONE token, which is what keeps \bsigner\b off it.
      expect(described_class.normalize_for_hint("db/seeds/system_topology_designer_agent.rb"))
        .to eq("db_seeds_system_topology_designer_agent_rb")
    end

    it "reports a label rather than a glob, because no glob would match" do
      # These match the whole normalised PATH, so a directory segment counts.
      # Reporting "**/*api_key*" would hand the operator a pattern that returns
      # false if they paste it back into fnmatch against the same path.
      expect(
        described_class.keep_manual_pattern("frontend/src/settings/ApiKeyForm.tsx")
      ).to eq("key-material name: api_key")
    end

    it "gates a directory segment carrying the token, which the old glob could not" do
      # File.fnmatch("**/*api_key*", "app/api_keys/foo.rb", FNM) is false under
      # FNM_PATHNAME: the glob cannot see inside a directory name.
      expect(described_class.keep_manual?("app/api_keys/foo.rb")).to be true
    end

    it "reports the glob that matched, not merely a boolean" do
      expect(
        described_class.keep_manual_pattern(
          "extensions/system/frontend/src/features/system/services/api/providerCredentialsApi.ts"
        )
      ).to eq("**/*credential*")
    end

    # NAME_HINT_EXEMPT must keep its meaning: a test file named after a credential
    # surface stores no key material, and case-folding must not start gating specs.
    it "keeps a PascalCase credential spec name-hint exempt" do
      expect(
        described_class.keep_manual?(
          "extensions/system/frontend/src/features/system/components/providers/ProviderCredentialsPanel.test.tsx"
        )
      ).to be false
    end

    it "keeps a camelCase credential api spec name-hint exempt" do
      expect(
        described_class.keep_manual?(
          "extensions/system/frontend/src/features/system/services/api/providerCredentialsApi.test.ts"
        )
      ).to be false
    end

    # An UNCONDITIONAL directory glob is not a name hint and is never exempted,
    # so a spec living under a gated directory stays keep-manual.
    it "folds case on unconditional DIRECTORY globs too, not just name hints" do
      # Cased on purpose: the all-lowercase form is already asserted above and
      # passes with or without the fix, so it carries no information here.
      expect(described_class.keep_manual?("server/spec/services/Vault/client_spec.rb")).to be true
    end

    # The symmetric consequence, pinned so it is a decision rather than a surprise:
    # NAME_HINT_EXEMPT folds too, so a cased structural directory now exempts a
    # name-hint hit exactly as its lowercase twin always did.
    it "exempts a name-hint hit under a cased structural directory" do
      expect(described_class.keep_manual?("server/app/models/Concerns/credential_display.rb")).to be false
      expect(described_class.keep_manual?("server/app/models/concerns/credential_display.rb")).to be false
    end
  end
end
