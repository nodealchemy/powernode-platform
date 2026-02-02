# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_attestation, class: "SupplyChain::Attestation" do
    association :account

    sequence(:attestation_id) { |n| "att-#{Time.current.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}" }
    attestation_type { "slsa_provenance" }
    slsa_level { 1 }
    subject_name { "app:#{Faker::App.name.downcase.gsub(/\s+/, '-')}" }
    subject_digest { SecureRandom.hex(32) }
    subject_digest_algorithm { "sha256" }
    predicate_type { "https://slsa.dev/provenance/v1" }
    predicate { { buildDefinition: {}, runDetails: {} } }
    verification_status { "unverified" }
    signature_format { "dsse" }
    metadata { {} }
    verification_results { {} }

    # ============================================
    # Attestation Type Traits
    # ============================================
    trait :slsa_provenance do
      attestation_type { "slsa_provenance" }
      predicate_type { "https://slsa.dev/provenance/v1" }
      predicate do
        {
          buildDefinition: {
            buildType: "https://github.com/actions/runner",
            externalParameters: {},
            internalParameters: {},
            resolvedDependencies: []
          },
          runDetails: {
            builder: { id: "https://github.com/actions/runner" },
            metadata: {
              invocationId: attestation_id,
              startedOn: 1.hour.ago.iso8601,
              finishedOn: Time.current.iso8601
            }
          }
        }
      end
    end

    trait :sbom do
      attestation_type { "sbom" }
      predicate_type { "https://cyclonedx.org/bom" }
      predicate { { components: [], metadata: { timestamp: Time.current.iso8601 } } }
    end

    trait :vuln_scan do
      attestation_type { "vuln_scan" }
      predicate_type { "https://cosign.sigstore.dev/attestation/vuln/v1" }
      predicate { { scanner: { name: "trivy", version: "0.48.0" }, vulnerabilities: [] } }
    end

    trait :custom do
      attestation_type { "custom" }
      predicate_type { "https://custom.attestation/v1" }
      predicate { { custom_data: {} } }
    end

    # ============================================
    # SLSA Level Traits
    # ============================================
    trait :slsa_level_0 do
      slsa_level { 0 }
    end

    trait :slsa_level_1 do
      slsa_level { 1 }
    end

    trait :slsa_level_2 do
      slsa_level { 2 }
    end

    trait :slsa_level_3 do
      slsa_level { 3 }
    end

    # ============================================
    # Verification Status Traits
    # ============================================
    trait :unverified do
      verification_status { "unverified" }
      verified_at { nil }
    end

    trait :verified do
      verification_status { "verified" }
      verified_at { Time.current }
      verification_results { { success: true, checks: [ { name: "signature", passed: true } ], errors: [] } }
    end

    trait :failed do
      verification_status { "failed" }
      verified_at { Time.current }
      verification_results { { success: false, checks: [ { name: "signature", passed: false } ], errors: [ "Invalid signature" ] } }
    end

    trait :expired do
      verification_status { "expired" }
    end

    # ============================================
    # Signature Traits
    # ============================================
    trait :signed do
      signature { Base64.strict_encode64(SecureRandom.random_bytes(256)) }
      signature_algorithm { "ECDSA-P256" }
      association :signing_key, factory: :supply_chain_signing_key
    end

    trait :unsigned do
      signature { nil }
      signature_algorithm { nil }
      signing_key { nil }
    end

    # ============================================
    # Rekor Transparency Log Traits
    # ============================================
    trait :logged_to_rekor do
      rekor_log_id { SecureRandom.hex(32) }
      rekor_log_url { "https://rekor.sigstore.dev/api/v1/log/entries/#{SecureRandom.hex(32)}" }
      rekor_logged_at { Time.current }
    end

    trait :not_logged_to_rekor do
      rekor_log_id { nil }
      rekor_log_url { nil }
      rekor_logged_at { nil }
    end

    # ============================================
    # Digest Algorithm Traits
    # ============================================
    trait :sha256 do
      subject_digest_algorithm { "sha256" }
      subject_digest { SecureRandom.hex(32) }
    end

    trait :sha384 do
      subject_digest_algorithm { "sha384" }
      subject_digest { SecureRandom.hex(48) }
    end

    trait :sha512 do
      subject_digest_algorithm { "sha512" }
      subject_digest { SecureRandom.hex(64) }
    end

    # ============================================
    # Association Traits
    # ============================================
    trait :with_signing_key do
      association :signing_key, factory: :supply_chain_signing_key
    end

    trait :with_sbom do
      association :sbom, factory: :supply_chain_sbom
    end

    trait :with_pipeline_run do
      association :pipeline_run, factory: :devops_pipeline_run
    end

    trait :with_created_by do
      association :created_by, factory: :user
    end

    trait :with_build_provenance do
      after(:create) do |attestation|
        create(:supply_chain_build_provenance, attestation: attestation, account: attestation.account)
      end
    end

    trait :with_verification_logs do
      after(:create) do |attestation|
        create_list(:supply_chain_verification_log, 2, attestation: attestation, account: attestation.account)
      end
    end

    # ============================================
    # Compound Traits
    # ============================================
    trait :signed_and_verified do
      signed
      verified
      logged_to_rekor
    end

    trait :slsa_compliant do
      slsa_provenance
      slsa_level_2
      signed_and_verified
    end
  end
end
