# frozen_string_literal: true

module Ai
  class DataSourceCredential < ApplicationRecord
    self.table_name = "ai_data_source_credentials"

    # Concerns
    include Auditable

    # Associations
    belongs_to :data_source, class_name: "Ai::DataSource", foreign_key: "ai_data_source_id"
    belongs_to :account

    # Rails 8 encrypted attributes
    encrypts :encrypted_api_key
    encrypts :encrypted_api_secret

    # OAuth 2.0 app credentials + user-context tokens (I2, x-com-provider campaign).
    # Same shape as the api_key/api_secret pair above: plain string column,
    # encrypted at the Rails layer. access_token/refresh_token are written only by
    # the OAuth callback (a later increment) — never accepted from client params.
    encrypts :encrypted_client_id
    encrypts :encrypted_client_secret
    encrypts :encrypted_access_token
    encrypts :encrypted_refresh_token

    # Friendlier OAuth2-standard names for the app-credential pair, so controllers
    # and callers can use client_id/client_secret while storage/encryption stays
    # on the encrypted_* column.
    alias_attribute :client_id, :encrypted_client_id
    alias_attribute :client_secret, :encrypted_client_secret

    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :ai_data_source_id, presence: true
    validates :account_id, presence: true

    # JSON column defaults (lambda required for mutable defaults)
    attribute :rate_limits, :json, default: -> { {} }
    attribute :usage_stats, :json, default: -> { {} }
    attribute :oauth_scopes, :json, default: -> { [] }

    # Scopes
    scope :active, -> { where(is_active: true) }
    scope :for_data_source, ->(ds) { where(ai_data_source_id: ds.is_a?(Ai::DataSource) ? ds.id : ds) }
    scope :expired, -> { where("expires_at IS NOT NULL AND expires_at <= ?", Time.current) }
    scope :healthy, -> { where(consecutive_failures: 0..2) }

    # Callbacks
    after_create :set_as_default_if_first

    # Rails 8 encrypts handles transparent decryption via attribute access
    def decrypted_api_key
      encrypted_api_key
    end

    def decrypted_api_secret
      encrypted_api_secret
    end

    def decrypted_client_id
      encrypted_client_id
    end

    def decrypted_client_secret
      encrypted_client_secret
    end

    def decrypted_access_token
      encrypted_access_token
    end

    def decrypted_refresh_token
      encrypted_refresh_token
    end

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    # Whether the OAuth2 access token itself (access_token_expires_at) has
    # already lapsed. Distinct from `expired?`, which covers the generic
    # api_key credential's `expires_at`.
    def token_expired?
      access_token_expires_at.present? && access_token_expires_at <= Time.current
    end

    # True when the access token is already expired or will expire within
    # `buffer` seconds — the refresh broker (I3) uses this to refresh silently
    # ahead of expiry rather than waiting for a 401.
    def needs_refresh?(buffer: 60)
      access_token_expires_at.present? && access_token_expires_at <= buffer.seconds.from_now
    end

    def healthy?
      is_active? && !expired? && consecutive_failures < 5
    end

    def record_success!
      update_columns(
        success_count: success_count + 1,
        consecutive_failures: 0,
        last_used_at: Time.current,
        last_test_at: Time.current,
        last_test_status: "success",
        last_error: nil
      )
      data_source.update_health_status!
    end

    def record_failure!(error_message = nil)
      new_failures = consecutive_failures + 1
      attrs = {
        failure_count: failure_count + 1,
        consecutive_failures: new_failures,
        last_used_at: Time.current,
        last_test_at: Time.current,
        last_test_status: "failed",
        last_error: error_message&.truncate(1000)
      }
      attrs[:is_active] = false if new_failures >= 5
      update_columns(attrs)
      data_source.update_health_status!
    end

    def make_default!
      transaction do
        self.class.where(ai_data_source_id: ai_data_source_id, account_id: account_id)
            .where.not(id: id)
            .update_all(is_default: false)
        update!(is_default: true)
      end
    end

    private

    def set_as_default_if_first
      return if self.class.where(ai_data_source_id: ai_data_source_id, account_id: account_id).count > 1

      update_column(:is_default, true)
    end
  end
end
