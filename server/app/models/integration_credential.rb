# frozen_string_literal: true

class IntegrationCredential < ApplicationRecord
  # ==================== Concerns ====================
  include Auditable

  # ==================== Constants ====================
  CREDENTIAL_TYPES = %w[github_app oauth2 api_key bearer_token basic_auth].freeze
  VALIDATION_STATUSES = %w[valid invalid expired unknown].freeze

  # ==================== Associations ====================
  belongs_to :account
  belongs_to :created_by_user, class_name: "User", optional: true

  has_many :integration_instances, dependent: :nullify

  # ==================== Validations ====================
  validates :name, presence: true, length: { maximum: 255 }
  validates :name, uniqueness: { scope: :account_id }
  validates :credential_type, presence: true, inclusion: { in: CREDENTIAL_TYPES }
  validates :encrypted_credentials, presence: true
  validates :encryption_key_id, presence: true
  validates :validation_status, inclusion: { in: VALIDATION_STATUSES }, allow_nil: true
  validate :credentials_format

  # ==================== Scopes ====================
  scope :active, -> { where(is_active: true) }
  scope :inactive, -> { where(is_active: false) }
  scope :by_type, ->(type) { where(credential_type: type) }
  scope :valid_credentials, -> { where(validation_status: "valid") }
  scope :expired, -> { where("expires_at IS NOT NULL AND expires_at <= ?", Time.current) }
  scope :expires_soon, ->(days = 7) { where("expires_at IS NOT NULL AND expires_at <= ?", days.days.from_now) }
  scope :healthy, -> { where(consecutive_failures: 0..2) }
  scope :unhealthy, -> { where("consecutive_failures > 2") }
  scope :recently_used, ->(days = 7) { where("last_used_at >= ?", days.days.ago) }

  # ==================== Callbacks ====================
  before_save :check_token_expiration

  # ==================== Instance Methods ====================

  def credentials
    @credentials ||= decrypt_credentials
  end

  def credentials=(new_credentials)
    @credentials = new_credentials
    self.encrypted_credentials = encrypt_credentials(new_credentials)
    self.encryption_key_id = current_encryption_key_id
  end

  def decrypt
    decrypt_credentials
  end

  def credential_summary
    {
      id: id,
      name: name,
      credential_type: credential_type,
      is_active: is_active,
      validation_status: validation_status,
      expires_at: expires_at,
      last_used_at: last_used_at,
      scopes: scopes
    }
  end

  def credential_details
    credential_summary.merge(
      metadata: metadata,
      last_validated_at: last_validated_at,
      consecutive_failures: consecutive_failures,
      last_error: last_error,
      created_at: created_at,
      updated_at: updated_at
    )
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def expires_soon?(days = 7)
    expires_at.present? && expires_at <= days.days.from_now
  end

  def healthy?
    is_active? && !expired? && consecutive_failures <= 2
  end

  def can_be_used?
    is_active? && !expired? && consecutive_failures <= 5
  end

  def record_success!
    update!(
      last_used_at: Time.current,
      last_validated_at: Time.current,
      validation_status: "valid",
      consecutive_failures: 0,
      last_error: nil
    )
  end

  def record_failure!(error_message = nil)
    update!(
      last_validated_at: Time.current,
      validation_status: "invalid",
      consecutive_failures: consecutive_failures + 1,
      last_error: error_message&.truncate(1000),
      is_active: consecutive_failures < 5  # Auto-disable after 5 failures
    )
  end

  def mark_expired!
    update!(
      validation_status: "expired",
      is_active: false
    )
  end

  def activate!
    update!(is_active: true)
  end

  def deactivate!
    update!(is_active: false)
  end

  def refresh_token!
    return unless credential_type == "oauth2"
    return unless encrypted_refresh_token.present?

    # This would be implemented by an OAuth service
    # IntegrationOAuthService.new(self).refresh_token
    raise NotImplementedError, "Token refresh must be implemented by OAuth service"
  end

  def rotate!(new_credentials)
    transaction do
      old_id = id
      self.credentials = new_credentials
      self.rotated_at = Time.current
      self.rotated_from_id = old_id
      self.consecutive_failures = 0
      self.validation_status = "unknown"
      save!
    end
  end

  private

  def decrypt_credentials
    return {} unless encrypted_credentials.present?

    if Rails.env.test?
      JSON.parse(Base64.strict_decode64(encrypted_credentials))
    else
      IntegrationCredentialEncryptionService.decrypt(
        encrypted_credentials,
        encryption_key_id
      )
    end
  rescue StandardError => e
    Rails.logger.error "Failed to decrypt integration credentials: #{e.message}"
    {}
  end

  def encrypt_credentials(credentials_hash)
    return nil unless credentials_hash.present?

    if Rails.env.test?
      Base64.strict_encode64(credentials_hash.to_json)
    else
      IntegrationCredentialEncryptionService.encrypt(credentials_hash)
    end
  end

  def current_encryption_key_id
    Rails.env.test? ? "test_key" : IntegrationCredentialEncryptionService.current_key_id
  end

  def credentials_format
    return unless @credentials.present?

    unless @credentials.is_a?(Hash)
      errors.add(:credentials, "must be a hash")
      return
    end

    case credential_type
    when "api_key"
      validate_api_key_credentials
    when "bearer_token"
      validate_bearer_token_credentials
    when "basic_auth"
      validate_basic_auth_credentials
    when "oauth2"
      validate_oauth2_credentials
    when "github_app"
      validate_github_app_credentials
    end
  end

  def validate_api_key_credentials
    unless @credentials["api_key"].present?
      errors.add(:credentials, "must include api_key")
    end
  end

  def validate_bearer_token_credentials
    unless @credentials["token"].present?
      errors.add(:credentials, "must include token")
    end
  end

  def validate_basic_auth_credentials
    unless @credentials["username"].present? && @credentials["password"].present?
      errors.add(:credentials, "must include username and password")
    end
  end

  def validate_oauth2_credentials
    unless @credentials["access_token"].present?
      errors.add(:credentials, "must include access_token")
    end
  end

  def validate_github_app_credentials
    required = %w[app_id private_key installation_id]
    missing = required.reject { |field| @credentials[field].present? }
    if missing.any?
      errors.add(:credentials, "must include #{missing.join(', ')}")
    end
  end

  def check_token_expiration
    return unless token_expires_at_changed? && token_expires_at.present?

    if token_expires_at <= Time.current
      self.validation_status = "expired"
    end
  end
end
