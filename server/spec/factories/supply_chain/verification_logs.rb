# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_verification_log, class: "SupplyChain::VerificationLog" do
    association :attestation, factory: :supply_chain_attestation
    association :account

    verification_type { "full" }
    result { "passed" }
    result_message { "All verification checks passed successfully" }
    log_hash { Digest::SHA256.hexdigest("#{SecureRandom.uuid}#{Time.current.to_i}") }
    previous_log_hash { nil }
    verification_details { { checks: [], all_passed: true } }
    metadata { {} }

    # ============================================
    # Verification Type Traits
    # ============================================
    trait :full_verification do
      verification_type { "full" }
      result_message { "Full verification completed successfully" }
      verification_details do
        {
          checks: [
            { name: "signature", passed: true },
            { name: "predicate", passed: true },
            { name: "rekor_log", passed: true }
          ],
          all_passed: true
        }
      end
    end

    trait :signature_verification do
      verification_type { "signature" }
      result_message { "Signature verification completed" }
      verification_details do
        {
          checks: [{ name: "signature", passed: true }],
          algorithm: "ECDSA-P256",
          key_id: "key-#{SecureRandom.hex(8)}"
        }
      end
    end

    trait :rekor_verification do
      verification_type { "rekor" }
      result_message { "Rekor transparency log verification completed" }
      verification_details do
        {
          checks: [{ name: "rekor_log", passed: true }],
          log_id: SecureRandom.hex(32),
          log_index: rand(1000000..9999999)
        }
      end
    end

    trait :predicate_verification do
      verification_type { "predicate" }
      result_message { "Predicate structure validation completed" }
      verification_details do
        {
          checks: [{ name: "predicate", passed: true }],
          predicate_type: "https://slsa.dev/provenance/v1"
        }
      end
    end

    trait :chain_verification do
      verification_type { "chain" }
      result_message { "Verification chain integrity confirmed" }
      verification_details do
        {
          checks: [{ name: "chain_integrity", passed: true }],
          chain_length: rand(1..10)
        }
      end
    end

    # ============================================
    # Result Traits
    # ============================================
    trait :passed do
      result { "passed" }
      result_message { "Verification passed successfully" }
      verification_details { { checks: [{ name: "signature", passed: true }], all_passed: true, errors: [] } }
    end

    trait :failed do
      result { "failed" }
      result_message { "Verification failed: Invalid signature" }
      verification_details do
        {
          checks: [{ name: "signature", passed: false }],
          all_passed: false,
          errors: ["Signature verification failed", "Key mismatch detected"]
        }
      end
    end

    trait :skipped do
      result { "skipped" }
      result_message { "Verification skipped - no signature present" }
      verification_details { { checks: [{ name: "signature", passed: false, skipped: true }], reason: "No signature to verify" } }
    end

    # ============================================
    # Chain Position Traits
    # ============================================
    trait :first_in_chain do
      previous_log_hash { nil }
    end

    trait :chained do
      previous_log_hash { Digest::SHA256.hexdigest(SecureRandom.uuid) }
    end

    # ============================================
    # Verification Error Traits
    # ============================================
    trait :signature_failed do
      result { "failed" }
      verification_type { "signature" }
      result_message { "Signature verification failed" }
      verification_details do
        {
          checks: [{ name: "signature", passed: false }],
          all_passed: false,
          errors: ["Invalid signature: key mismatch"]
        }
      end
    end

    trait :rekor_failed do
      result { "failed" }
      verification_type { "rekor" }
      result_message { "Rekor log verification failed" }
      verification_details do
        {
          checks: [{ name: "rekor_log", passed: false }],
          all_passed: false,
          errors: ["Entry not found in transparency log"]
        }
      end
    end

    trait :predicate_failed do
      result { "failed" }
      verification_type { "predicate" }
      result_message { "Predicate validation failed" }
      verification_details do
        {
          checks: [{ name: "predicate", passed: false }],
          all_passed: false,
          errors: ["Invalid predicate structure: missing required fields"]
        }
      end
    end

    trait :chain_broken do
      result { "failed" }
      verification_type { "chain" }
      result_message { "Verification chain integrity check failed" }
      verification_details do
        {
          checks: [{ name: "chain_integrity", passed: false }],
          all_passed: false,
          errors: ["Hash chain broken: previous hash mismatch"]
        }
      end
    end

    # ============================================
    # Association Traits
    # ============================================
    trait :with_verified_by do
      association :verified_by, factory: :user
    end

    # ============================================
    # Compound Traits
    # ============================================
    trait :complete_verification do
      full_verification
      passed
      with_verified_by
      verification_details do
        {
          checks: [
            { name: "signature", passed: true, algorithm: "ECDSA-P256" },
            { name: "predicate", passed: true, type: "slsa_provenance_v1" },
            { name: "rekor_log", passed: true, log_index: rand(1000000..9999999) },
            { name: "chain_integrity", passed: true }
          ],
          all_passed: true,
          verification_time_ms: rand(50..500)
        }
      end
    end

    trait :partial_failure do
      result { "failed" }
      verification_type { "full" }
      result_message { "Verification partially failed" }
      verification_details do
        {
          checks: [
            { name: "signature", passed: true },
            { name: "predicate", passed: true },
            { name: "rekor_log", passed: false }
          ],
          all_passed: false,
          errors: ["Rekor log entry not found"]
        }
      end
    end
  end
end
