# frozen_string_literal: true

require "rails_helper"

# Admin::SecurityConfigService#regenerate_jwt_secret is algorithm-aware:
# RS256 rotates the RSA keypair via JwtKeyStore (no key material returned);
# HS256 (dev/test) rotates the in-memory HMAC secret with a grace cache.
RSpec.describe Admin::SecurityConfigService, "#regenerate_jwt_secret" do
  let(:user) { create(:user) }
  subject(:service) { described_class.new(user: user) }

  context "under RS256" do
    before do
      allow(Rails.application.config).to receive(:jwt_algorithm).and_return("RS256")
      Security::JwtKeyStore.clear_cache!
      Rails.cache.delete("jwt_secret_rotation")
    end

    after { Security::JwtKeyStore.clear_cache! }

    it "rotates the RSA keypair via JwtKeyStore" do
      expect(Security::JwtKeyStore).to receive(:rotate!).with(grace_hours: 24).and_call_original
      result = service.regenerate_jwt_secret(reason: "test")

      expect(result[:success]).to be(true)
      expect(result[:algorithm]).to eq("RS256")
      expect(result[:grace_period_hours]).to eq(24)
    end

    it "returns NO key material" do
      result = service.regenerate_jwt_secret
      expect(result).not_to have_key(:new_secret)
      expect(result.to_s).not_to include("PRIVATE KEY")
    end

    it "does not touch the HS256 rotation cache" do
      service.regenerate_jwt_secret
      expect(Rails.cache.read("jwt_secret_rotation")).to be_nil
    end

    it "writes a critical audit log for the key rotation" do
      expect { service.regenerate_jwt_secret }
        .to change { AuditLog.where(action: "jwt_secret_regenerated").count }.by(1)
      log = AuditLog.where(action: "jwt_secret_regenerated").last
      expect(log.metadata["algorithm"]).to eq("RS256")
      expect(log.severity).to eq("critical")
    end
  end

  # HS256 runs in production on the hub (rails-start.sh pins JWT_ALGORITHM),
  # so its rotation goes through JwtKeyStore's durable HMAC keyring exactly as
  # RS256 goes through its keypair: no secret in Rails.cache, none returned.
  context "under HS256" do
    before do
      allow(Rails.application.config).to receive(:jwt_algorithm).and_return("HS256")
      Security::JwtKeyStore.clear_cache!
    end

    after { Security::JwtKeyStore.clear_cache! }

    it "rotates the HMAC secret through JwtKeyStore" do
      expect(Security::JwtKeyStore).to receive(:rotate_hmac!).with(grace_hours: 24).and_call_original

      result = service.regenerate_jwt_secret(reason: "test")

      expect(result[:success]).to be(true)
      expect(result[:algorithm]).to eq("HS256")
      expect(result[:grace_period_hours]).to eq(24)
    end

    it "returns NO secret and writes none to Rails.cache" do
      allow(Rails.cache).to receive(:write).and_call_original

      result = service.regenerate_jwt_secret

      expect(result).not_to have_key(:new_secret)
      stored = Security::SecretStore.read(account: nil, scope: Security::JwtKeyStore::SCOPE,
                                          key: Security::JwtKeyStore::ACTIVE_HMAC_SECRET)
      expect(result.to_s).not_to include(stored)
      expect(Rails.cache).not_to have_received(:write).with("jwt_secret_rotation", anything, anything)
    end

    it "writes a critical audit log without secret lengths or material" do
      service.regenerate_jwt_secret
      log = AuditLog.where(action: "jwt_secret_regenerated").last
      expect(log.metadata["algorithm"]).to eq("HS256")
      expect(log.metadata.keys).not_to include("old_secret_length", "new_secret_length")
    end
  end
end
