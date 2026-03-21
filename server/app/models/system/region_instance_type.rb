# frozen_string_literal: true

module System
  class RegionInstanceType < BaseRecord
    # Associations
    belongs_to :provider_region, class_name: 'System::ProviderRegion'
    belongs_to :provider_instance_type, class_name: 'System::ProviderInstanceType'

    # Validations
    validates :provider_region_id, uniqueness: { scope: :provider_instance_type_id }

    # Scopes
    scope :available, -> { where(available: true) }
    scope :unavailable, -> { where(available: false) }

    # Delegations
    delegate :account, :provider, to: :provider_region
    delegate :name, :instance_type_code, :vcpus, :memory_mb, to: :provider_instance_type, prefix: :instance_type

    # Get effective price (region-specific or base)
    def effective_price
      hourly_price || provider_instance_type.hourly_price
    end

    def effective_currency
      currency || provider_instance_type.currency || 'USD'
    end
  end
end
