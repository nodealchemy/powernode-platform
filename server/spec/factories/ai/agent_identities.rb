# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_identity, class: "Ai::AgentIdentity" do
    account
    agent_id { SecureRandom.uuid }
    public_key { OpenSSL::PKey.generate_key("ED25519").public_to_pem }
    encrypted_private_key { Security::CredentialEncryptionService.encrypt_value("fake_encrypted_key", namespace: "agent_identity") }
    key_fingerprint { Digest::SHA256.hexdigest(public_key) }
    algorithm { "ed25519" }
    status { "active" }
    agent_uri { "agent://powernode.io/workflow/assistant/#{agent_id}" }
    attestation_claims { { provisioned_at: Time.current.iso8601 } }
    capabilities { %w[text_generation conversation] }
    expires_at { 365.days.from_now }

    trait :revoked do
      status { "revoked" }
      revoked_at { Time.current }
      revocation_reason { "Manual revocation" }
    end

    trait :rotated do
      status { "rotated" }
      rotated_at { Time.current }
      rotation_overlap_until { 24.hours.from_now }
    end

    trait :expired do
      expires_at { 1.day.ago }
    end

    trait :expiring_soon do
      expires_at { 3.days.from_now }
    end
  end
end
