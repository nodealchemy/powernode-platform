# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Security::AgentIdentityService, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }

  subject(:service) { described_class.new(account: account) }

  describe "#provision!" do
    it "creates an AgentIdentity with Ed25519 keypair" do
      identity = service.provision!(agent: agent)

      expect(identity).to be_persisted
      expect(identity.status).to eq("active")
      expect(identity.algorithm).to eq("ed25519")
      expect(identity.agent_id).to eq(agent.id)
      expect(identity.public_key).to be_present
      expect(identity.encrypted_private_key).to be_present
      expect(identity.key_fingerprint).to be_present
      expect(identity.agent_uri).to include("powernode.io/workflow")
      expect(identity.expires_at).to be > Time.current
    end

    it "generates a valid Ed25519 public key" do
      identity = service.provision!(agent: agent)

      public_key = OpenSSL::PKey.read(identity.public_key)
      expect(public_key).to be_a(OpenSSL::PKey::PKey)
    end

    it "generates unique fingerprints for each identity" do
      id1 = service.provision!(agent: agent)

      agent2 = create(:ai_agent, account: account, provider: provider)
      id2 = service.provision!(agent: agent2)

      expect(id1.key_fingerprint).not_to eq(id2.key_fingerprint)
    end

    it "creates an audit trail entry" do
      expect {
        service.provision!(agent: agent)
      }.to change(Ai::SecurityAuditTrail, :count).by_at_least(1)
    end
  end

  describe "#sign and #verify" do
    let!(:identity) { service.provision!(agent: agent) }
    let(:payload) { { message: "test", timestamp: Time.current.to_i } }

    it "signs a payload and verifies successfully" do
      signature = service.sign(agent: agent, payload: payload)
      expect(signature).to be_present

      result = service.verify(agent_id: agent.id, payload: payload, signature: signature)
      expect(result[:valid]).to be true
      expect(result[:identity_id]).to eq(identity.id)
    end

    it "rejects an invalid signature" do
      result = service.verify(
        agent_id: agent.id,
        payload: payload,
        signature: Base64.strict_encode64("invalid_signature")
      )
      expect(result[:valid]).to be false
      expect(result[:reason]).to include("verification failed")
    end

    it "rejects verification for agents with no identity" do
      agent2 = create(:ai_agent, account: account, provider: provider)
      result = service.verify(
        agent_id: agent2.id,
        payload: payload,
        signature: Base64.strict_encode64("any")
      )
      expect(result[:valid]).to be false
      expect(result[:reason]).to include("No usable identity")
    end

    it "raises SigningError when no active identity exists" do
      agent2 = create(:ai_agent, account: account, provider: provider)
      expect {
        service.sign(agent: agent2, payload: "test")
      }.to raise_error(Ai::Security::AgentIdentityService::SigningError)
    end

    it "signs string payloads correctly" do
      signature = service.sign(agent: agent, payload: "simple string")
      result = service.verify(agent_id: agent.id, payload: "simple string", signature: signature)
      expect(result[:valid]).to be true
    end
  end

  describe "#rotate!" do
    let!(:original_identity) { service.provision!(agent: agent) }

    it "creates a new identity and marks the old one as rotated" do
      new_identity = service.rotate!(agent: agent)

      expect(new_identity).to be_persisted
      expect(new_identity.status).to eq("active")
      expect(new_identity.id).not_to eq(original_identity.id)

      original_identity.reload
      expect(original_identity.status).to eq("rotated")
      expect(original_identity.rotated_at).to be_present
      expect(original_identity.rotation_overlap_until).to be > Time.current
    end

    it "allows verification with old key during overlap window" do
      payload = "test_payload"
      old_signature = service.sign(agent: agent, payload: payload)

      service.rotate!(agent: agent)

      result = service.verify(agent_id: agent.id, payload: payload, signature: old_signature)
      expect(result[:valid]).to be true
    end

    it "raises error when no active identity exists" do
      agent2 = create(:ai_agent, account: account, provider: provider)
      expect {
        service.rotate!(agent: agent2)
      }.to raise_error(Ai::Security::AgentIdentityService::IdentityError)
    end
  end

  describe "#revoke!" do
    let!(:identity) { service.provision!(agent: agent) }

    it "revokes all active identities for the agent" do
      result = service.revoke!(agent: agent, reason: "Compromised key")

      expect(result[:revoked_count]).to eq(1)
      expect(result[:reason]).to eq("Compromised key")

      identity.reload
      expect(identity.status).to eq("revoked")
      expect(identity.revoked_at).to be_present
      expect(identity.revocation_reason).to eq("Compromised key")
    end

    it "prevents signing after revocation" do
      service.revoke!(agent: agent, reason: "Test")

      expect {
        service.sign(agent: agent, payload: "test")
      }.to raise_error(Ai::Security::AgentIdentityService::SigningError)
    end
  end

  describe "#attestation_token" do
    let!(:identity) { service.provision!(agent: agent) }

    it "generates a time-bounded attestation token" do
      token = service.attestation_token(agent: agent)

      expect(token).to be_present
      parts = token.split(".")
      expect(parts.length).to eq(2)

      claims = JSON.parse(Base64.urlsafe_decode64(parts[0]))
      expect(claims["iss"]).to eq("powernode.io")
      expect(claims["sub"]).to eq(agent.id)
      expect(claims["kid"]).to eq(identity.key_fingerprint)
      expect(claims["exp"]).to be > Time.current.to_i
    end

    it "includes custom capabilities when provided" do
      token = service.attestation_token(agent: agent, capabilities: ["custom_cap"])
      parts = token.split(".")
      claims = JSON.parse(Base64.urlsafe_decode64(parts[0]))
      expect(claims["capabilities"]).to eq(["custom_cap"])
    end
  end
end
