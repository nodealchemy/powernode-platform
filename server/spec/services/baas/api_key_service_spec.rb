# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaaS::ApiKeyService, type: :service do
  let(:account) { create(:account) }
  let(:tenant) { create(:baas_tenant, account: account) }
  let(:service) { described_class.new(tenant: tenant) }

  describe "#create_key" do
    it "creates a new API key" do
      result = service.create_key(
        name: "Test API Key",
        environment: "development"
      )

      expect(result[:success]).to be true
      expect(result[:api_key]).to be_a(BaaS::ApiKey)
      expect(result[:raw_key]).to start_with("sk_test_")
    end

    it "creates production key with correct prefix" do
      result = service.create_key(
        name: "Live API Key",
        environment: "production"
      )

      expect(result[:success]).to be true
      expect(result[:raw_key]).to start_with("sk_live_")
    end

    it "stores hashed key" do
      result = service.create_key(
        name: "Test Key",
        environment: "development"
      )

      api_key = result[:api_key]
      expect(api_key.key_hash).not_to eq(result[:raw_key])
      expect(api_key.key_hash).to eq(Digest::SHA256.hexdigest(result[:raw_key]))
    end

    it "sets default scopes" do
      result = service.create_key(
        name: "Test Key",
        environment: "development"
      )

      expect(result[:api_key].scopes).to include("*")
    end

    it "accepts custom scopes" do
      result = service.create_key(
        name: "Read Only Key",
        environment: "development",
        scopes: [ "read" ]
      )

      expect(result[:api_key].scopes).to eq([ "read" ])
    end
  end

  describe ".authenticate" do
    let!(:api_key_result) do
      service.create_key(
        name: "Auth Test Key",
        environment: "development"
      )
    end

    it "authenticates valid key" do
      result = described_class.authenticate(api_key_result[:raw_key])

      expect(result[:success]).to be true
      expect(result[:api_key]).to eq(api_key_result[:api_key])
    end

    it "returns error for invalid key" do
      result = described_class.authenticate("sk_test_invalid")

      expect(result[:success]).to be false
      expect(result[:error]).to eq("Invalid API key")
    end

    it "returns error for revoked key" do
      api_key_result[:api_key].revoke!
      result = described_class.authenticate(api_key_result[:raw_key])

      # find_by_key only finds active keys, so revoked key returns "Invalid API key"
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Invalid API key")
    end

    it "updates last_used_at" do
      expect { described_class.authenticate(api_key_result[:raw_key]) }
        .to change { api_key_result[:api_key].reload.last_used_at }
    end
  end

  describe "#revoke_key" do
    let!(:api_key_result) { service.create_key(name: "Test", environment: "development") }

    it "revokes the key" do
      result = service.revoke_key(api_key_result[:api_key].id)

      expect(result[:success]).to be true
      expect(api_key_result[:api_key].reload.revoked?).to be true
    end

    it "returns error when already revoked" do
      api_key_result[:api_key].revoke!
      result = service.revoke_key(api_key_result[:api_key].id)

      expect(result[:success]).to be false
      expect(result[:error]).to eq("API key already revoked")
    end
  end

  describe "#roll_key" do
    let!(:api_key_result) { service.create_key(name: "Original Key", environment: "development") }

    it "creates new key and revokes old one" do
      old_key = api_key_result[:api_key]
      result = service.roll_key(old_key.id)

      expect(result[:success]).to be true
      expect(old_key.reload.revoked?).to be true
      expect(result[:api_key]).not_to eq(old_key)
      expect(result[:api_key].name).to eq("Original Key")
    end

    it "returns new raw key" do
      result = service.roll_key(api_key_result[:api_key].id)

      expect(result[:raw_key]).to be_present
      expect(result[:raw_key]).to start_with("sk_test_")
    end
  end

  describe "#list_keys" do
    before do
      service.create_key(name: "Test Key 1", environment: "development")
      service.create_key(name: "Test Key 2", environment: "development")
      service.create_key(name: "Prod Key", environment: "production")
    end

    it "lists all keys for tenant" do
      result = service.list_keys

      expect(result[:success]).to be true
      expect(result[:api_keys].count).to eq(3)
    end

    it "filters by environment" do
      result = service.list_keys(environment: "development")

      expect(result[:api_keys].count).to eq(2)
    end

    it "filters by status" do
      tenant.api_keys.first.revoke!
      result = service.list_keys(status: "active")

      expect(result[:api_keys].count).to eq(2)
    end
  end
end
