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

  context "under HS256 (dev/test)" do
    before do
      allow(Rails.application.config).to receive(:jwt_algorithm).and_return("HS256")
      Rails.cache.delete("jwt_secret_rotation")
    end

    it "rotates the HMAC secret with a grace window cache" do
      result = service.regenerate_jwt_secret
      expect(result[:algorithm]).to eq("HS256")
      expect(result[:new_secret]).to be_present
      expect(Rails.cache.read("jwt_secret_rotation")).to be_present
    end
  end
end
