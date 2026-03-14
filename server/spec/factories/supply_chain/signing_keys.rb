# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_signing_key, class: "SupplyChain::SigningKey" do
    association :account

    sequence(:key_id) { |n| "key-#{SecureRandom.hex(8)}" }
    key_type { "cosign" }
    name { "#{Faker::Hacker.adjective.capitalize} Signing Key" }
    public_key { OpenSSL::PKey::EC.generate("prime256v1").public_key.to_pem rescue SecureRandom.hex(64) }
    fingerprint { Digest::SHA256.hexdigest(public_key) }
    status { "active" }
    expires_at { 1.year.from_now }
    metadata { {} }

    # ============================================
    # Key Type Traits
    # ============================================
    trait :cosign do
      key_type { "cosign" }
      name { "Cosign Signing Key" }
    end

    trait :gpg do
      key_type { "gpg" }
      name { "GPG Signing Key" }
      public_key do
        # Simulated GPG public key block
        "-----BEGIN PGP PUBLIC KEY BLOCK-----\n" \
        "#{SecureRandom.base64(128).chars.each_slice(64).map(&:join).join("\n")}\n" \
        "-----END PGP PUBLIC KEY BLOCK-----"
      end
    end

    trait :oidc_identity do
      key_type { "oidc_identity" }
      name { "OIDC Identity Key" }
      oidc_issuer { "https://token.actions.githubusercontent.com" }
      oidc_subject { "repo:#{Faker::Internet.slug}/#{Faker::App.name.downcase}:ref:refs/heads/main" }
    end

    trait :sigstore do
      key_type { "oidc_identity" }
      name { "Sigstore Keyless Key" }
      oidc_issuer { "https://oauth2.sigstore.dev/auth" }
    end

    # ============================================
    # KMS Reference Traits
    # ============================================
    trait :kms_reference do
      key_type { "kms_reference" }
      name { "KMS Reference Key" }
      kms_provider { "aws_kms" }
      kms_key_uri { "arn:aws:kms:us-east-1:123456789012:key/#{SecureRandom.uuid}" }
    end

    trait :aws_kms do
      key_type { "kms_reference" }
      name { "AWS KMS Signing Key" }
      kms_provider { "aws_kms" }
      kms_key_uri { "arn:aws:kms:us-east-1:123456789012:key/#{SecureRandom.uuid}" }
    end

    trait :gcp_kms do
      key_type { "kms_reference" }
      name { "GCP KMS Signing Key" }
      kms_provider { "gcp_kms" }
      kms_key_uri { "gcpkms://projects/my-project/locations/us-east1/keyRings/my-keyring/cryptoKeys/my-key/cryptoKeyVersions/1" }
    end

    trait :azure_keyvault do
      key_type { "kms_reference" }
      name { "Azure Key Vault Signing Key" }
      kms_provider { "azure_keyvault" }
      kms_key_uri { "azurekms://my-vault.vault.azure.net/keys/my-key/abc123" }
    end

    trait :hashicorp_vault do
      key_type { "kms_reference" }
      name { "HashiCorp Vault Signing Key" }
      kms_provider { "hashicorp_vault" }
      kms_key_uri { "hashivault://transit/keys/my-key" }
    end

    # ============================================
    # Status Traits
    # ============================================
    trait :active do
      status { "active" }
    end

    trait :rotating do
      status { "rotating" }
    end

    trait :rotated do
      status { "rotated" }
      rotated_at { Time.current }
    end

    trait :revoked do
      status { "revoked" }
    end

    trait :expired do
      status { "expired" }
      expires_at { 1.day.ago }
    end

    # ============================================
    # Expiration Traits
    # ============================================
    trait :expiring_soon do
      status { "active" }
      expires_at { 7.days.from_now }
    end

    trait :expiring_very_soon do
      status { "active" }
      expires_at { 1.day.from_now }
    end

    trait :long_lived do
      expires_at { 5.years.from_now }
    end

    trait :no_expiration do
      expires_at { nil }
    end

    # ============================================
    # Private Key Traits
    # ============================================
    trait :with_private_key do
      encrypted_private_key { SecureRandom.hex(128) }
    end

    trait :without_private_key do
      encrypted_private_key { nil }
    end

    # ============================================
    # Association Traits
    # ============================================
    trait :with_created_by do
      association :created_by, factory: :user
    end

    trait :with_rotation_history do
      after(:create) do |key|
        old_key = create(:supply_chain_signing_key, :rotated, account: key.account)
        key.update!(rotated_from: old_key)
      end
    end

    trait :with_attestations do
      after(:create) do |key|
        create_list(:supply_chain_attestation, 3, :signed, signing_key: key, account: key.account)
      end
    end

    # ============================================
    # Compound Traits
    # ============================================
    trait :production_ready do
      active
      cosign
      with_private_key
      long_lived
      with_created_by
    end

    trait :github_actions_keyless do
      oidc_identity
      oidc_issuer { "https://token.actions.githubusercontent.com" }
      oidc_subject { "repo:org/repo:ref:refs/heads/main" }
    end
  end
end
