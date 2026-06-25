# frozen_string_literal: true

require "rails_helper"

# Platform-global secrets (account_id NULL) — e.g. the RS256 JWT signing keypair —
# are owned by no account. Enabled by making Security::Secret#account optional +
# making security_secrets.account_id nullable with a partial unique index.
RSpec.describe "Security::SecretStore platform-global secrets", type: :service do
  let(:scope) { "jwt_signing" }

  it "writes + reads a platform-global secret with account: nil" do
    Security::SecretStore.write(account: nil, scope: scope, key: "active_private_key", value: "PEM-A")
    expect(Security::SecretStore.read(account: nil, scope: scope, key: "active_private_key")).to eq("PEM-A")
  end

  it "upserts a platform-global secret in place (one row per scope/key)" do
    Security::SecretStore.write(account: nil, scope: scope, key: "k", value: "v1")
    Security::SecretStore.write(account: nil, scope: scope, key: "k", value: "v2")
    expect(Security::SecretStore.read(account: nil, scope: scope, key: "k")).to eq("v2")
    expect(Security::Secret.where(account_id: nil, scope: scope, key: "k").count).to eq(1)
  end

  it "keeps platform-global and account-scoped secrets independent" do
    account = create(:account)
    Security::SecretStore.write(account: nil, scope: scope, key: "k", value: "global")
    Security::SecretStore.write(account: account, scope: scope, key: "k", value: "scoped")

    expect(Security::SecretStore.read(account: nil, scope: scope, key: "k")).to eq("global")
    expect(Security::SecretStore.read(account: account, scope: scope, key: "k")).to eq("scoped")
  end

  it "encrypts the value at rest (ciphertext != plaintext in the column)" do
    Security::SecretStore.write(account: nil, scope: scope, key: "k", value: "super-secret")
    # Read the RAW column via SQL — pluck/pick would apply the encrypted-attribute
    # type cast and hand back the decrypted plaintext, hiding the ciphertext.
    raw = Security::Secret.connection.select_value(
      Security::Secret.where(account_id: nil, scope: scope, key: "k").select(:value).to_sql
    )
    expect(raw).to be_present
    expect(raw).not_to include("super-secret")
  end
end
