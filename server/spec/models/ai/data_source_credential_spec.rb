# frozen_string_literal: true

require "rails_helper"

# x-com-provider campaign (I2): OAuth2 credential storage on the core
# Ai::DataSourceCredential model — client_id/client_secret (app credentials) +
# access_token/refresh_token (user-context tokens minted by a later OAuth
# callback increment), alongside the pre-existing encrypted api_key/api_secret.
RSpec.describe Ai::DataSourceCredential, type: :model do
  let(:account) { create(:account) }
  let(:data_source) { create(:ai_data_source, account: account) }

  describe "OAuth2 encrypted attributes" do
    subject(:credential) do
      create(
        :ai_data_source_credential,
        account: account,
        data_source: data_source,
        encrypted_client_id: "client-abc123",
        encrypted_client_secret: "supersecretvalue",
        encrypted_access_token: "access-token-xyz",
        encrypted_refresh_token: "refresh-token-xyz"
      )
    end

    it "round-trips client_id/client_secret/access_token/refresh_token through decrypted_* accessors" do
      reloaded = described_class.find(credential.id)

      expect(reloaded.decrypted_client_id).to eq("client-abc123")
      expect(reloaded.decrypted_client_secret).to eq("supersecretvalue")
      expect(reloaded.decrypted_access_token).to eq("access-token-xyz")
      expect(reloaded.decrypted_refresh_token).to eq("refresh-token-xyz")
    end

    it "aliases client_id/client_secret onto the encrypted columns" do
      expect(credential.client_id).to eq("client-abc123")
      expect(credential.client_secret).to eq("supersecretvalue")
    end

    it "does not store the plaintext in the raw database column" do
      raw = ActiveRecord::Base.connection.select_one(<<~SQL.squish)
        SELECT encrypted_client_secret, encrypted_access_token
        FROM ai_data_source_credentials
        WHERE id = '#{credential.id}'
      SQL

      expect(raw["encrypted_client_secret"]).not_to eq("supersecretvalue")
      expect(raw["encrypted_client_secret"]).not_to be_nil
      expect(raw["encrypted_access_token"]).not_to eq("access-token-xyz")
    end
  end

  describe "#oauth_scopes" do
    it "defaults to an empty array" do
      credential = create(:ai_data_source_credential, account: account, data_source: data_source)

      expect(credential.oauth_scopes).to eq([])
    end

    it "persists an array of scope strings" do
      credential = create(
        :ai_data_source_credential,
        account: account, data_source: data_source,
        oauth_scopes: %w[tweet.read tweet.write offline.access]
      )

      expect(credential.reload.oauth_scopes).to eq(%w[tweet.read tweet.write offline.access])
    end
  end

  describe "#token_expired?" do
    subject(:credential) do
      build(:ai_data_source_credential, account: account, data_source: data_source)
    end

    it "is false when access_token_expires_at is blank" do
      credential.access_token_expires_at = nil
      expect(credential.token_expired?).to be false
    end

    it "is false when access_token_expires_at is in the future" do
      credential.access_token_expires_at = 1.hour.from_now
      expect(credential.token_expired?).to be false
    end

    it "is true when access_token_expires_at is in the past" do
      credential.access_token_expires_at = 1.hour.ago
      expect(credential.token_expired?).to be true
    end

    it "is true at the exact expiry boundary" do
      credential.access_token_expires_at = Time.current
      expect(credential.token_expired?).to be true
    end
  end

  describe "#needs_refresh?" do
    subject(:credential) do
      build(:ai_data_source_credential, account: account, data_source: data_source)
    end

    it "is false when access_token_expires_at is blank" do
      credential.access_token_expires_at = nil
      expect(credential.needs_refresh?).to be false
    end

    it "is false when expiry is well beyond the buffer window" do
      credential.access_token_expires_at = 1.hour.from_now
      expect(credential.needs_refresh?(buffer: 60)).to be false
    end

    it "is true when expiry falls within the buffer window" do
      credential.access_token_expires_at = 30.seconds.from_now
      expect(credential.needs_refresh?(buffer: 60)).to be true
    end

    it "is true when already expired" do
      credential.access_token_expires_at = 1.hour.ago
      expect(credential.needs_refresh?(buffer: 60)).to be true
    end
  end
end
