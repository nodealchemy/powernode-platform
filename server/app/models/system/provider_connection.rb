# frozen_string_literal: true

module System
  class ProviderConnection < BaseRecord
    # Status constants
    STATUSES = %w[pending connected error].freeze

    # Encryption for sensitive fields
    encrypts :access_key
    encrypts :secret_key

    # Associations
    belongs_to :account
    belongs_to :provider, class_name: 'System::Provider'

    # Validations
    validates :name, presence: true, uniqueness: { scope: :account_id }
    validates :status, presence: true, inclusion: { in: STATUSES }

    # Scopes
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :connected, -> { where(status: 'connected') }
    scope :pending, -> { where(status: 'pending') }
    scope :errored, -> { where(status: 'error') }
    scope :for_provider, ->(provider) { where(provider: provider) }

    # Config accessor
    store_accessor :config

    # Status predicates
    STATUSES.each do |status_name|
      define_method("#{status_name}?") { status == status_name }
    end

    # Mark as connected
    def mark_connected!(message = nil)
      update!(
        status: 'connected',
        last_tested_at: Time.current,
        last_test_status: 'success',
        last_test_message: message
      )
    end

    # Mark as error
    def mark_error!(message)
      update!(
        status: 'error',
        last_tested_at: Time.current,
        last_test_status: 'error',
        last_test_message: message
      )
    end

    # Test connection (to be implemented by provider-specific services)
    def test_connection!
      # This would be implemented by a service class
      # For now, just update the last_tested_at
      update!(last_tested_at: Time.current)
    end
  end
end
