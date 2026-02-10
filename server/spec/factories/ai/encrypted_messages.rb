# frozen_string_literal: true

FactoryBot.define do
  factory :ai_encrypted_message, class: "Ai::EncryptedMessage" do
    account
    from_agent_id { SecureRandom.uuid }
    to_agent_id { SecureRandom.uuid }
    nonce { SecureRandom.random_bytes(12) }
    ciphertext { SecureRandom.random_bytes(64) }
    auth_tag { SecureRandom.random_bytes(16) }
    sequence(:sequence_number)
    session_id { SecureRandom.uuid }
    status { "delivered" }
    aad { { from_agent_id: from_agent_id, to_agent_id: to_agent_id, timestamp: Time.current.iso8601 }.to_json }

    trait :read do
      status { "read" }
    end

    trait :expired do
      status { "expired" }
    end

    trait :with_signature do
      signature { Base64.strict_encode64(SecureRandom.random_bytes(64)) }
    end

    trait :with_task do
      task_id { SecureRandom.uuid }
    end
  end
end
