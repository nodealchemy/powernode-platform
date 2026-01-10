# frozen_string_literal: true

module Git
  class ProviderCredential < ApplicationRecord
    # Authentication
    # Belongs to account - access controlled through account ownership

    # Concerns
    include Auditable

    # Constants
    AUTH_TYPES = %w[oauth personal_access_token].freeze
    MAX_CONSECUTIVE_FAILURES = 5

    # Associations
    belongs_to :provider, class_name: "Git::Provider", foreign_key: "git_provider_id"
    belongs_to :account
    belongs_to :user, optional: true
    has_many :repositories, class_name: "Git::Repository", foreign_key: "git_provider_credential_id", dependent: :destroy

    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :auth_type, presence: true, inclusion: { in: AUTH_TYPES }
    validates :encrypted_credentials, presence: true
    validates :encryption_key_id, presence: true
    validates :account_id, uniqueness: {
      scope: %i[git_provider_id is_default],
      conditions: -> { where(is_default: true) },
      message: "can only have one default credential per provider"
    }
    validate :credentials_format
    validate :expiration_date_future, on: :create

    # Scopes
    scope :active, -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }
    scope :default, -> { where(is_default: true) }
    scope :non_default, -> { where(is_default: false) }
    scope :oauth, -> { where(auth_type: "oauth") }
    scope :pat, -> { where(auth_type: "personal_access_token") }
    scope :for_provider, ->(provider) { where(git_provider_id: provider.is_a?(Git::Provider) ? provider.id : provider) }
    scope :expires_soon, ->(days = 30) { where("expires_at IS NOT NULL AND expires_at <= ?", days.days.from_now) }
    scope :expired, -> { where("expires_at IS NOT NULL AND expires_at <= ?", Time.current) }
    scope :healthy, -> { where(consecutive_failures: 0..2) }
    scope :unhealthy, -> { where("consecutive_failures > 2") }
    scope :recently_used, ->(days = 7) { where("last_used_at >= ?", days.days.ago) }

    # Callbacks
    before_validation :ensure_single_default
    before_destroy :prevent_destroy_if_default_and_only
    after_create :set_as_default_if_first

    # Instance Methods

    def credentials
      @credentials ||= decrypt_credentials
    end

    def credentials=(new_credentials)
      @credentials = new_credentials
      self.encrypted_credentials = encrypt_credentials(new_credentials)
      self.encryption_key_id = current_encryption_key_id
    end

    def access_token
      credentials["access_token"] || credentials["token"]
    end

    def refresh_token
      credentials["refresh_token"]
    end

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def expires_soon?(days = 30)
      expires_at.present? && expires_at <= days.days.from_now
    end

    def healthy?
      is_active? && !expired? && consecutive_failures <= 2
    end

    def can_be_used?
      is_active? && !expired? && consecutive_failures <= MAX_CONSECUTIVE_FAILURES
    end

    def record_success!
      increment!(:success_count)
      update!(
        last_used_at: Time.current,
        last_test_at: Time.current,
        last_test_status: "success",
        consecutive_failures: 0,
        last_error: nil,
        is_active: true
      )
    end

    def record_failure!(error_message = nil)
      increment!(:consecutive_failures)
      increment!(:failure_count)
      new_consecutive = consecutive_failures + 1
      update_columns(
        last_test_at: Time.current,
        last_test_status: "failed",
        last_error: error_message&.truncate(1000),
        is_active: new_consecutive <= MAX_CONSECUTIVE_FAILURES
      )
    end

    def make_default!
      transaction do
        account.git_provider_credentials
               .where(git_provider_id: git_provider_id, is_default: true)
               .where.not(id: id)
               .update_all(is_default: false)

        update!(is_default: true, is_active: true)
      end
    end

    def test_connection
      return false unless can_be_used?

      begin
        Git::ProviderTestService.new(self).test_connection
      rescue StandardError => e
        record_failure!(e.message)
        false
      end
    end

    def provider_type
      provider&.provider_type
    end

    def oauth?
      auth_type == "oauth"
    end

    def pat?
      auth_type == "personal_access_token"
    end

    def usage_summary
      {
        success_count: success_count,
        failure_count: failure_count,
        success_rate: total_count.positive? ? (success_count.to_f / total_count * 100).round(2) : 0,
        repositories_count: repositories.count,
        last_used_at: last_used_at,
        last_test_at: last_test_at,
        last_test_status: last_test_status
      }
    end

    # Backwards compatibility alias
    def git_provider
      provider
    end

    private

    def total_count
      success_count + failure_count
    end

    def decrypt_credentials
      return {} unless encrypted_credentials.present?

      if Rails.env.test?
        JSON.parse(Base64.strict_decode64(encrypted_credentials))
      else
        Git::CredentialEncryptionService.decrypt(encrypted_credentials, encryption_key_id)
      end
    rescue StandardError => e
      Rails.logger.error "Failed to decrypt Git credentials: #{e.message}"
      {}
    end

    def encrypt_credentials(credentials_hash)
      return nil unless credentials_hash.present?

      if Rails.env.test?
        Base64.strict_encode64(credentials_hash.to_json)
      else
        Git::CredentialEncryptionService.encrypt(credentials_hash)
      end
    end

    def current_encryption_key_id
      Rails.env.test? ? "test_key" : Git::CredentialEncryptionService.current_key_id
    end

    def credentials_format
      return unless @credentials.present?

      unless @credentials.is_a?(Hash)
        errors.add(:credentials, "must be a hash")
        return
      end

      case auth_type
      when "oauth"
        validate_oauth_credentials
      when "personal_access_token"
        validate_pat_credentials
      end
    end

    def validate_oauth_credentials
      unless @credentials["access_token"].present?
        errors.add(:credentials, "must include access_token for OAuth authentication")
      end
    end

    def validate_pat_credentials
      token = @credentials["token"] || @credentials["access_token"]
      unless token.present?
        errors.add(:credentials, "must include token for personal access token authentication")
      end

      if token.present? && token.length < 10
        errors.add(:credentials, "token appears to be too short")
      end
    end

    def expiration_date_future
      return unless expires_at.present?

      if expires_at <= Time.current
        errors.add(:expires_at, "must be in the future")
      end
    end

    def ensure_single_default
      return unless is_default_changed? && is_default?

      Git::ProviderCredential.where(
        account: account,
        git_provider_id: git_provider_id,
        is_default: true
      ).where.not(id: id).update_all(is_default: false)
    end

    def prevent_destroy_if_default_and_only
      if is_default? && account.git_provider_credentials.for_provider(git_provider_id).count == 1
        errors.add(:base, "Cannot delete the only credential for this provider")
        throw :abort
      end
    end

    def set_as_default_if_first
      return if account.git_provider_credentials.for_provider(git_provider_id).count > 1

      update_column(:is_default, true)
    end
  end
end
