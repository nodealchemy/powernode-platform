# frozen_string_literal: true

module SupplyChain
  class SigningKey < ApplicationRecord
    include Auditable

    self.table_name = "supply_chain_signing_keys"

    # ============================================
    # Constants
    # ============================================
    KEY_TYPES = %w[cosign oidc_identity kms_reference gpg].freeze
    STATUSES = %w[active rotating rotated revoked expired].freeze
    KMS_PROVIDERS = %w[aws_kms gcp_kms azure_keyvault hashicorp_vault].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :created_by, class_name: "User", optional: true
    belongs_to :rotated_from, class_name: "SupplyChain::SigningKey", optional: true

    has_many :rotated_to, class_name: "SupplyChain::SigningKey",
             foreign_key: :rotated_from_id, dependent: :nullify
    has_many :attestations, class_name: "SupplyChain::Attestation",
             foreign_key: :signing_key_id, dependent: :nullify

    # ============================================
    # Validations
    # ============================================
    validates :key_id, presence: true, uniqueness: { scope: :account_id }
    validates :key_type, presence: true, inclusion: { in: KEY_TYPES }
    validates :name, presence: true
    validates :public_key, presence: true
    validates :fingerprint, presence: true, uniqueness: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :kms_provider, inclusion: { in: KMS_PROVIDERS }, allow_nil: true
    validate :kms_fields_required_for_kms_reference

    # ============================================
    # Scopes
    # ============================================
    scope :active, -> { where(status: "active") }
    scope :by_type, ->(type) { where(key_type: type) }
    scope :cosign_keys, -> { where(key_type: "cosign") }
    scope :kms_keys, -> { where(key_type: "kms_reference") }
    scope :expiring_soon, ->(days = 30) { where("expires_at IS NOT NULL AND expires_at <= ?", days.days.from_now) }
    scope :expired, -> { where("expires_at IS NOT NULL AND expires_at < ?", Time.current) }
    scope :not_expired, -> { where("expires_at IS NULL OR expires_at >= ?", Time.current) }
    scope :recent, -> { order(created_at: :desc) }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :generate_key_id, on: :create
    before_validation :calculate_fingerprint, if: :public_key_changed?
    before_save :sanitize_jsonb_fields
    before_save :check_expiration

    # ============================================
    # Instance Methods
    # ============================================
    def active?
      status == "active"
    end

    def rotating?
      status == "rotating"
    end

    def rotated?
      status == "rotated"
    end

    def revoked?
      status == "revoked"
    end

    def expired?
      status == "expired" || (expires_at.present? && expires_at < Time.current)
    end

    def cosign?
      key_type == "cosign"
    end

    def kms?
      key_type == "kms_reference"
    end

    def oidc?
      key_type == "oidc_identity"
    end

    def gpg?
      key_type == "gpg"
    end

    def can_sign?
      active? && !expired?
    end

    def has_private_key?
      encrypted_private_key.present? || kms_key_uri.present?
    end

    def expiring_soon?(days = 30)
      expires_at.present? && expires_at <= days.days.from_now
    end

    def days_until_expiration
      return nil unless expires_at.present?

      (expires_at.to_date - Date.current).to_i
    end

    def rotate!(new_key)
      transaction do
        update!(status: "rotating")

        new_key.rotated_from = self
        new_key.save!

        update!(
          status: "rotated",
          rotated_at: Time.current
        )

        new_key
      end
    end

    def revoke!
      update!(status: "revoked")
    end

    def private_key
      return nil unless encrypted_private_key.present?

      # Decrypt the private key
      # This would use your encryption service
      encrypted_private_key
    end

    def private_key=(value)
      # Encrypt the private key
      # This would use your encryption service
      self.encrypted_private_key = value
    end

    def sign(data)
      return nil unless can_sign?

      case key_type
      when "cosign"
        sign_with_cosign(data)
      when "kms_reference"
        sign_with_kms(data)
      when "gpg"
        sign_with_gpg(data)
      else
        raise NotImplementedError, "Signing not implemented for #{key_type}"
      end
    end

    def verify(data, signature)
      case key_type
      when "cosign"
        verify_cosign(data, signature)
      when "kms_reference"
        verify_kms(data, signature)
      when "gpg"
        verify_gpg(data, signature)
      else
        raise NotImplementedError, "Verification not implemented for #{key_type}"
      end
    end

    def summary
      {
        id: id,
        key_id: key_id,
        key_type: key_type,
        name: name,
        fingerprint: fingerprint,
        status: status,
        can_sign: can_sign?,
        expires_at: expires_at,
        days_until_expiration: days_until_expiration,
        created_at: created_at
      }
    end

    private

    def generate_key_id
      return if key_id.present?

      self.key_id = "key-#{SecureRandom.hex(8)}"
    end

    def calculate_fingerprint
      return if public_key.blank?

      # Calculate SHA256 fingerprint of the public key
      self.fingerprint = Digest::SHA256.hexdigest(public_key)
    end

    def sanitize_jsonb_fields
      self.metadata ||= {}
    end

    def check_expiration
      if expires_at.present? && expires_at < Time.current && status == "active"
        self.status = "expired"
      end
    end

    def kms_fields_required_for_kms_reference
      return unless kms?

      errors.add(:kms_provider, "is required for KMS reference keys") if kms_provider.blank?
      errors.add(:kms_key_uri, "is required for KMS reference keys") if kms_key_uri.blank?
    end

    def sign_with_cosign(data)
      # Placeholder for Cosign signing implementation
      # Would use the cosign CLI or library
      nil
    end

    def sign_with_kms(data)
      # Placeholder for KMS signing implementation
      # Would use AWS KMS, GCP KMS, or Azure Key Vault
      nil
    end

    def sign_with_gpg(data)
      # Placeholder for GPG signing implementation
      nil
    end

    def verify_cosign(data, signature)
      # Placeholder for Cosign verification
      false
    end

    def verify_kms(data, signature)
      # Placeholder for KMS verification
      false
    end

    def verify_gpg(data, signature)
      # Placeholder for GPG verification
      false
    end
  end
end
