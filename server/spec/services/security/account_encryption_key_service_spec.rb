# frozen_string_literal: true

require "rails_helper"

# Comprehensive stabilization sweep P3 — per-account encryption key
# restoration via Vault transit.
RSpec.describe Security::AccountEncryptionKeyService do
  let(:account) { create(:account) }
  let(:transit_client) { instance_double(Security::VaultTransitClient) }

  before do
    described_class.transit_client = transit_client
    allow(transit_client).to receive(:peppered_blob?) { |v| v.is_a?(String) && v.start_with?("vault:v") }
  end

  after { described_class.reset_transit_client! }

  describe ".generate_for" do
    it "creates a transit key and persists the path on the account" do
      expect(transit_client).to receive(:create_key).with("account-#{account.id}")

      path = described_class.generate_for(account)

      expect(path).to eq("transit/keys/account-#{account.id}")
      expect(account.reload.encryption_key_vault_path).to eq("transit/keys/account-#{account.id}")
    end

    it "is idempotent — returns existing path without re-creating the key" do
      account.update!(encryption_key_vault_path: "transit/keys/account-#{account.id}")
      expect(transit_client).not_to receive(:create_key)

      path = described_class.generate_for(account)

      expect(path).to eq("transit/keys/account-#{account.id}")
    end

    it "raises VaultUnavailableError if Vault is unreachable" do
      allow(transit_client).to receive(:create_key)
        .and_raise(Security::VaultTransitClient::VaultUnavailableError, "transit not mounted")

      expect { described_class.generate_for(account) }
        .to raise_error(Security::VaultTransitClient::VaultUnavailableError)

      expect(account.reload.encryption_key_vault_path).to be_nil
    end
  end

  describe ".peppered" do
    it "encrypts plaintext via Vault transit, returning a `vault:v1:` blob" do
      account.update!(encryption_key_vault_path: "transit/keys/account-#{account.id}")

      expect(transit_client).to receive(:encrypt)
        .with("account-#{account.id}", "AKIAEXAMPLE")
        .and_return("vault:v1:abc123")

      result = described_class.peppered(account, "AKIAEXAMPLE")
      expect(result).to eq("vault:v1:abc123")
    end

    it "lazy-generates the account key on first call" do
      expect(transit_client).to receive(:create_key).with("account-#{account.id}").ordered
      expect(transit_client).to receive(:encrypt).with("account-#{account.id}", "secret").ordered.and_return("vault:v1:xyz")

      result = described_class.peppered(account, "secret")
      expect(result).to eq("vault:v1:xyz")
      expect(account.reload.encryption_key_vault_path).to be_present
    end

    it "returns blank as-is" do
      expect(transit_client).not_to receive(:encrypt)

      expect(described_class.peppered(account, "")).to eq("")
      expect(described_class.peppered(account, nil)).to be_nil
    end

    it "propagates VaultUnavailableError from Vault" do
      account.update!(encryption_key_vault_path: "transit/keys/account-#{account.id}")
      allow(transit_client).to receive(:encrypt)
        .and_raise(Security::VaultTransitClient::VaultUnavailableError, "transit unavailable")

      expect { described_class.peppered(account, "x") }
        .to raise_error(Security::VaultTransitClient::VaultUnavailableError)
    end
  end

  describe ".decrypt" do
    it "decrypts a Vault transit blob back to plaintext" do
      expect(transit_client).to receive(:decrypt)
        .with("account-#{account.id}", "vault:v1:abc123")
        .and_return("AKIAEXAMPLE")

      result = described_class.decrypt(account, "vault:v1:abc123")
      expect(result).to eq("AKIAEXAMPLE")
    end

    it "returns nil for blank input" do
      expect(transit_client).not_to receive(:decrypt)
      expect(described_class.decrypt(account, "")).to be_nil
      expect(described_class.decrypt(account, nil)).to be_nil
    end

    it "returns the input unchanged if it doesn't look like a Vault blob (legacy un-peppered)" do
      expect(transit_client).not_to receive(:decrypt)

      result = described_class.decrypt(account, "AKIAEXAMPLE")
      expect(result).to eq("AKIAEXAMPLE")
    end
  end

  describe ".rotate_for" do
    it "rotates the account's transit key" do
      account.update!(encryption_key_vault_path: "transit/keys/account-#{account.id}")

      expect(transit_client).to receive(:rotate_key)
        .with("account-#{account.id}")
        .and_return({ latest_version: 2, min_decryption_version: 1 })

      result = described_class.rotate_for(account)
      expect(result[:latest_version]).to eq(2)
    end

    it "raises if account has no key to rotate" do
      expect(transit_client).not_to receive(:rotate_key)

      expect { described_class.rotate_for(account) }.to raise_error(ArgumentError, /no key/)
    end
  end

  describe ".peppered_blob?" do
    it "delegates to the transit client's prefix check" do
      expect(described_class.peppered_blob?("vault:v1:abc")).to be true
      expect(described_class.peppered_blob?("AKIAEXAMPLE")).to be false
      expect(described_class.peppered_blob?(nil)).to be false
    end
  end
end
