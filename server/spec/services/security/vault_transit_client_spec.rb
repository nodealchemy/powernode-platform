# frozen_string_literal: true

require "rails_helper"

RSpec.describe Security::VaultTransitClient do
  let(:vault_logical) { instance_double(Vault::Logical) }
  let(:vault_client) { instance_double(Vault::Client, logical: vault_logical) }
  let(:underlying) { instance_double(Security::VaultClient, client: vault_client) }
  let(:client) { described_class.new(vault_client: underlying) }

  describe "#peppered_blob?" do
    it "matches the vault: prefix" do
      expect(client.peppered_blob?("vault:v1:abc")).to be true
      expect(client.peppered_blob?("vault:v2:def")).to be true
    end

    it "rejects non-Vault values" do
      expect(client.peppered_blob?("AKIAEXAMPLE")).to be false
      expect(client.peppered_blob?("")).to be false
      expect(client.peppered_blob?(nil)).to be false
    end
  end

  describe "#create_key" do
    it "POSTs to transit/keys/<name> with default config" do
      expect(vault_logical).to receive(:write)
        .with("transit/keys/account-1", hash_including(type: "aes256-gcm96"))
      expect(client.create_key("account-1")).to be true
    end
  end

  describe "#encrypt" do
    it "base64-encodes plaintext + returns Vault ciphertext blob" do
      response = double(data: { ciphertext: "vault:v1:abc123" })
      expect(vault_logical).to receive(:write)
        .with("transit/encrypt/account-1", plaintext: Base64.strict_encode64("AKIAEXAMPLE"))
        .and_return(response)

      expect(client.encrypt("account-1", "AKIAEXAMPLE")).to eq("vault:v1:abc123")
    end

    it "raises ArgumentError for blank name" do
      expect { client.encrypt("", "x") }.to raise_error(ArgumentError, /name/)
    end

    it "raises ArgumentError for nil plaintext" do
      expect { client.encrypt("account-1", nil) }.to raise_error(ArgumentError, /plaintext/)
    end

    it "raises TransitError when Vault returns no ciphertext" do
      response = double(data: { ciphertext: nil })
      allow(vault_logical).to receive(:write).and_return(response)

      expect { client.encrypt("account-1", "x") }.to raise_error(Security::VaultTransitClient::TransitError)
    end
  end

  describe "#decrypt" do
    it "decodes Vault plaintext from base64" do
      response = double(data: { plaintext: Base64.strict_encode64("AKIAEXAMPLE") })
      expect(vault_logical).to receive(:write)
        .with("transit/decrypt/account-1", ciphertext: "vault:v1:abc")
        .and_return(response)

      expect(client.decrypt("account-1", "vault:v1:abc")).to eq("AKIAEXAMPLE")
    end

    it "raises CiphertextMismatchError for non-Vault input" do
      expect { client.decrypt("account-1", "not-a-vault-blob") }
        .to raise_error(Security::VaultTransitClient::CiphertextMismatchError)
    end

    it "raises ArgumentError for blank inputs" do
      expect { client.decrypt("", "vault:v1:abc") }.to raise_error(ArgumentError, /name/)
      expect { client.decrypt("account-1", "") }.to raise_error(ArgumentError, /ciphertext/)
    end
  end

  describe "error translation" do
    let(:http_error) { Vault::HTTPError.new("transit", double(code: 404, body: "")) }

    it "translates Vault HTTPError 404 to KeyNotFoundError" do
      allow(vault_logical).to receive(:write).and_raise(http_error)

      expect { client.encrypt("missing", "x") }
        .to raise_error(Security::VaultTransitClient::KeyNotFoundError)
    end

    it "translates Vault::HTTPConnectionError to VaultUnavailableError" do
      allow(vault_logical).to receive(:write)
        .and_raise(Vault::HTTPConnectionError.new("vault.example.com", StandardError.new("refused")))

      expect { client.encrypt("k", "x") }
        .to raise_error(Security::VaultTransitClient::VaultUnavailableError)
    end

    it "translates underlying Security::VaultClient::ConnectionError to VaultUnavailableError" do
      allow(vault_logical).to receive(:write)
        .and_raise(Security::VaultClient::ConnectionError.new("circuit open"))

      expect { client.encrypt("k", "x") }
        .to raise_error(Security::VaultTransitClient::VaultUnavailableError)
    end

    it "wraps generic transit errors in TransitError" do
      generic_error = Vault::HTTPError.new("server", double(code: 500, body: "boom"))
      allow(vault_logical).to receive(:write).and_raise(generic_error)

      expect { client.encrypt("k", "x") }
        .to raise_error(Security::VaultTransitClient::TransitError)
    end
  end

  describe "#rotate_key" do
    it "writes to transit/keys/<name>/rotate + returns key metadata" do
      meta_response = double(data: { latest_version: 2, min_decryption_version: 1 })
      expect(vault_logical).to receive(:write)
        .with("transit/keys/account-1/rotate")
      expect(vault_logical).to receive(:read)
        .with("transit/keys/account-1")
        .and_return(meta_response)

      result = client.rotate_key("account-1")
      expect(result[:latest_version]).to eq(2)
    end
  end
end
