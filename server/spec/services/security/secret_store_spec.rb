# frozen_string_literal: true

require "rails_helper"

RSpec.describe Security::SecretStore do
  let(:account) { create(:account) }

  before { AdminSetting.where(key: described_class::SETTING_KEY).delete_all }

  describe "database backend (default)" do
    it "defaults to the database backend" do
      expect(described_class.backend).to eq(:database)
    end

    it "round-trips a secret" do
      described_class.write(account: account, scope: "email", key: "smtp_password", value: "hunter2")
      expect(described_class.read(account: account, scope: "email", key: "smtp_password")).to eq("hunter2")
    end

    it "upserts on repeated writes (one row)" do
      described_class.write(account: account, scope: "email", key: "smtp_password", value: "a")
      described_class.write(account: account, scope: "email", key: "smtp_password", value: "b")

      expect(described_class.read(account: account, scope: "email", key: "smtp_password")).to eq("b")
      expect(Security::Secret.where(account: account, scope: "email", key: "smtp_password").count).to eq(1)
    end

    it "deletes a secret" do
      described_class.write(account: account, scope: "email", key: "k", value: "v")
      described_class.delete(account: account, scope: "email", key: "k")
      expect(described_class.read(account: account, scope: "email", key: "k")).to be_nil
    end

    it "stores the value encrypted at rest (no plaintext in the column)" do
      described_class.write(account: account, scope: "email", key: "smtp_password", value: "supersecretvalue")
      secret = Security::Secret.find_by!(account: account, scope: "email", key: "smtp_password")
      # Read the raw column straight from the connection to bypass Rails `encrypts`
      # attribute decryption (pluck/pick would decrypt) — we want the ciphertext at rest.
      raw = Security::Secret.connection.select_value(
        ActiveRecord::Base.sanitize_sql(["SELECT value FROM security_secrets WHERE id = ?", secret.id])
      )
      expect(raw).to be_present
      expect(raw).not_to include("supersecretvalue")
    end

    it "isolates secrets by account" do
      other = create(:account)
      described_class.write(account: account, scope: "email", key: "k", value: "mine")
      expect(described_class.read(account: other, scope: "email", key: "k")).to be_nil
    end
  end

  describe "vault backend selected" do
    before { AdminSetting.set(described_class::SETTING_KEY, "vault") }

    it "reports the vault backend" do
      expect(described_class.backend).to eq(:vault)
    end

    it "fails closed when Vault is unreachable (no silent DB fallback)" do
      allow(Security::SecretStore::VaultBackend).to receive(:reachable?).and_return(false)

      expect do
        described_class.write(account: account, scope: "email", key: "k", value: "v")
      end.to raise_error(Security::SecretStore::BackendUnavailable)
    end

    it "uses the vault backend when reachable" do
      allow(Security::SecretStore::VaultBackend).to receive(:reachable?).and_return(true)
      expect(Security::SecretStore::VaultBackend).to receive(:write)
        .with(account: account, scope: "email", key: "k", value: "v").and_return("v")

      described_class.write(account: account, scope: "email", key: "k", value: "v")
    end
  end
end
