# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Security::TokenScopeAuditService do
  describe "#run" do
    context "provider credentials" do
      it "flags a wildcard access scope as over-provisioned" do
        cred = create(:ai_provider_credential, access_scopes: ["*"])

        result = described_class.new.run

        finding = result[:findings].find { |f| f[:subject_id] == cred.id }
        expect(finding).to be_present
        expect(finding[:subject_type]).to eq("Ai::ProviderCredential")
        expect(finding[:issues].join).to match(/blanket|unrestricted/i)
        expect(result[:over_provisioned_count]).to be >= 1
      end

      it "flags an admin-broad access scope" do
        cred = create(:ai_provider_credential, access_scopes: ["admin:all"])

        finding = described_class.new.run[:findings].find { |f| f[:subject_id] == cred.id }

        expect(finding).to be_present
        expect(finding[:issues].join).to match(/admin/i)
      end

      it "flags an active credential left with no scope restriction (empty-but-active)" do
        cred = create(:ai_provider_credential, access_scopes: [])

        finding = described_class.new.run[:findings].find { |f| f[:subject_id] == cred.id }

        expect(finding).to be_present
        expect(finding[:issues].join).to match(/unrestricted|no scope/i)
      end

      it "does NOT flag a tightly-scoped, active credential" do
        cred = create(:ai_provider_credential, access_scopes: ["models:read"])

        finding = described_class.new.run[:findings].find { |f| f[:subject_id] == cred.id }

        expect(finding).to be_nil
      end

      it "ignores inactive credentials" do
        cred = create(:ai_provider_credential, :inactive, access_scopes: ["*"])

        finding = described_class.new.run[:findings].find { |f| f[:subject_id] == cred.id }

        expect(finding).to be_nil
      end

      it "flags scopes outside a configured baseline" do
        cred = create(:ai_provider_credential, access_scopes: ["models:read", "billing:write"])

        result = described_class.new(baseline: ["models:read"]).run
        finding = result[:findings].find { |f| f[:subject_id] == cred.id }

        expect(finding).to be_present
        expect(finding[:issues].join).to match(/baseline/i)
        expect(finding[:issues].join).to include("billing:write")
      end
    end

    context "api keys" do
      it "flags a wildcard-scoped API key" do
        key = create(:api_key, scopes: ["read:*"])

        finding = described_class.new.run[:findings].find { |f| f[:subject_id] == key.id }

        expect(finding).to be_present
        expect(finding[:subject_type]).to eq("ApiKey")
        expect(finding[:issues].join).to match(/wildcard/i)
      end

      it "does not flag a tightly-scoped API key" do
        key = create(:api_key, scopes: ["read:users"])

        finding = described_class.new.run[:findings].find { |f| f[:subject_id] == key.id }

        expect(finding).to be_nil
      end
    end

    context "account scoping" do
      it "limits the audit to the given account" do
        mine = create(:account)
        other = create(:account)
        create(:ai_provider_credential, account: mine, access_scopes: ["*"])
        create(:ai_provider_credential, account: other, access_scopes: ["*"])

        result = described_class.new(account: mine).run

        subjects = result[:findings].map { |f| f[:subject_id] }
        mine_ids = ::Ai::ProviderCredential.where(account_id: mine.id).pluck(:id)
        expect(subjects).to match_array(mine_ids)
      end
    end

    context "crypto safety" do
      it "never surfaces secret/token values in findings — only ids + scope names" do
        secret = "sk-supersecret-#{SecureRandom.hex(12)}"
        cred = create(:ai_provider_credential,
                      access_scopes: ["*"],
                      credentials: { "api_key" => secret, "model" => "test-model" })
        key = create(:api_key, scopes: ["admin:settings"])

        result = described_class.new.run
        dumped = result.to_s

        expect(dumped).not_to include(secret)
        expect(dumped).not_to include(cred.encrypted_credentials.to_s)
        expect(dumped).not_to include(key.key_digest.to_s)
      end
    end
  end
end
