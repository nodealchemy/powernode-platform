# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaaS::ApiKey, type: :model do
  let(:account) { create(:account) }
  let(:tenant) { create(:baas_tenant, account: account) }

  describe "associations" do
    it { is_expected.to belong_to(:baas_tenant).class_name("BaaS::Tenant") }
  end

  describe "validations" do
    subject { build(:baas_api_key, baas_tenant: tenant) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:key_prefix) }
    it { is_expected.to validate_presence_of(:key_hash) }
    it { is_expected.to validate_presence_of(:key_type) }
    it { is_expected.to validate_presence_of(:environment) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_uniqueness_of(:key_hash) }
    it { is_expected.to validate_inclusion_of(:key_type).in_array(%w[secret publishable restricted]) }
    it { is_expected.to validate_inclusion_of(:environment).in_array(%w[development staging production]) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[active revoked expired]) }
  end

  describe ".generate_key" do
    it "generates key with correct prefix for secret type" do
      key = described_class.generate_key(type: "secret", environment: "production")
      expect(key).to start_with("sk_live_")
    end

    it "generates key with correct prefix for publishable type" do
      key = described_class.generate_key(type: "publishable", environment: "production")
      expect(key).to start_with("pk_live_")
    end

    it "generates key with test prefix for development environment" do
      key = described_class.generate_key(type: "secret", environment: "development")
      expect(key).to start_with("sk_test_")
    end
  end

  describe ".hash_key" do
    it "returns SHA256 hash of key" do
      key = "test_key_123"
      expected = Digest::SHA256.hexdigest(key)
      expect(described_class.hash_key(key)).to eq(expected)
    end
  end

  describe ".find_by_key" do
    let!(:api_key) do
      raw_key = described_class.generate_key(type: "secret", environment: "production")
      create(:baas_api_key,
        baas_tenant: tenant,
        key_hash: described_class.hash_key(raw_key),
        key_prefix: raw_key[0..7],
        status: "active"
      ).tap { |k| @raw_key = raw_key }
    end

    it "finds key by raw key value" do
      result = described_class.find_by_key(@raw_key)
      expect(result).to eq(api_key)
    end

    it "returns nil for invalid key" do
      result = described_class.find_by_key("invalid_key")
      expect(result).to be_nil
    end

    it "returns nil for blank key" do
      expect(described_class.find_by_key("")).to be_nil
      expect(described_class.find_by_key(nil)).to be_nil
    end
  end

  describe "#active?" do
    let(:api_key) { create(:baas_api_key, baas_tenant: tenant) }

    it "returns true when status is active and not expired" do
      expect(api_key.active?).to be true
    end

    it "returns false when status is revoked" do
      api_key.update!(status: "revoked")
      expect(api_key.active?).to be false
    end

    it "returns false when expired" do
      api_key.update!(expires_at: 1.day.ago)
      expect(api_key.active?).to be false
    end
  end

  describe "#revoked?" do
    let(:api_key) { create(:baas_api_key, baas_tenant: tenant) }

    it "returns false when not revoked" do
      expect(api_key.revoked?).to be false
    end

    it "returns true when status is revoked" do
      api_key.update!(status: "revoked")
      expect(api_key.revoked?).to be true
    end
  end

  describe "#expired?" do
    let(:api_key) { create(:baas_api_key, baas_tenant: tenant) }

    it "returns false when no expiration date" do
      expect(api_key.expired?).to be false
    end

    it "returns true when expires_at is in the past" do
      api_key.update!(expires_at: 1.day.ago)
      expect(api_key.expired?).to be true
    end

    it "returns false when expires_at is in the future" do
      api_key.update!(expires_at: 1.day.from_now)
      expect(api_key.expired?).to be false
    end
  end

  describe "#revoke!" do
    let(:api_key) { create(:baas_api_key, baas_tenant: tenant) }

    it "sets status to revoked" do
      api_key.revoke!
      expect(api_key.status).to eq("revoked")
    end
  end

  describe "#check_expiration!" do
    let(:api_key) { create(:baas_api_key, baas_tenant: tenant, status: "active") }

    it "updates status to expired when expired" do
      api_key.update!(expires_at: 1.day.ago)
      api_key.check_expiration!
      expect(api_key.status).to eq("expired")
    end

    it "does nothing when not expired" do
      api_key.update!(expires_at: 1.day.from_now)
      api_key.check_expiration!
      expect(api_key.status).to eq("active")
    end
  end

  describe "#record_usage!" do
    let(:api_key) { create(:baas_api_key, baas_tenant: tenant, total_requests: 0) }

    it "increments total_requests" do
      expect { api_key.record_usage! }.to change { api_key.total_requests }.by(1)
    end

    it "updates last_used_at" do
      expect { api_key.record_usage! }.to change { api_key.last_used_at }
    end
  end

  describe "#has_scope?" do
    let(:api_key) { create(:baas_api_key, baas_tenant: tenant, scopes: ["read", "write"]) }

    it "returns true when scope is present" do
      expect(api_key.has_scope?("read")).to be true
    end

    it "returns false when scope is not present" do
      expect(api_key.has_scope?("admin")).to be false
    end

    it "returns true for any scope when wildcard is present" do
      api_key.update!(scopes: ["*"])
      expect(api_key.has_scope?("anything")).to be true
    end
  end

  describe "#within_rate_limit?" do
    let(:api_key) { create(:baas_api_key, baas_tenant: tenant, rate_limit_per_minute: 100, rate_limit_per_day: 10000) }

    it "returns true when under limit" do
      expect(api_key.within_rate_limit?(50)).to be true
    end

    it "returns false when at or over limit" do
      expect(api_key.within_rate_limit?(100)).to be false
      expect(api_key.within_rate_limit?(150)).to be false
    end
  end

  describe "#summary" do
    let(:api_key) { create(:baas_api_key, baas_tenant: tenant) }

    it "returns summary hash" do
      summary = api_key.summary
      expect(summary).to include(:id, :name, :key_prefix, :key_type, :environment, :status)
    end
  end

  describe "scopes" do
    let!(:active_key) { create(:baas_api_key, baas_tenant: tenant, status: "active") }
    let!(:revoked_key) { create(:baas_api_key, baas_tenant: tenant, status: "revoked") }
    let!(:secret_key) { create(:baas_api_key, baas_tenant: tenant, key_type: "secret") }
    let!(:publishable_key) { create(:baas_api_key, baas_tenant: tenant, key_type: "publishable", key_prefix: "pk_test") }

    it "filters active keys" do
      expect(described_class.active).to include(active_key)
      expect(described_class.active).not_to include(revoked_key)
    end

    it "filters secret keys" do
      expect(described_class.secret_keys).to include(secret_key)
      expect(described_class.secret_keys).not_to include(publishable_key)
    end

    it "filters publishable keys" do
      expect(described_class.publishable_keys).to include(publishable_key)
      expect(described_class.publishable_keys).not_to include(secret_key)
    end
  end
end
