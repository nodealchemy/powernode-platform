# frozen_string_literal: true

module System
  class ProviderAvailabilityZone < BaseRecord
    # Status constants
    STATUSES = %w[available impaired unavailable].freeze

    # Associations
    belongs_to :provider_region, class_name: 'System::ProviderRegion'

    # Delegations
    delegate :account, :account_id, :provider, to: :provider_region

    # Validations
    validates :name, presence: true
    validates :zone_code, presence: true, uniqueness: { scope: :provider_region_id }
    validates :status, presence: true, inclusion: { in: STATUSES }

    # Scopes
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :available, -> { where(status: 'available') }
    scope :impaired, -> { where(status: 'impaired') }
    scope :unavailable, -> { where(status: 'unavailable') }
    scope :operational, -> { where(status: %w[available impaired]) }

    # Capabilities accessor
    store_accessor :capabilities

    # Status predicates
    STATUSES.each do |status_name|
      define_method("#{status_name}?") { status == status_name }
    end

    def operational?
      available? || impaired?
    end

    def has_capability?(capability)
      capabilities&.dig(capability.to_s) == true
    end
  end
end
