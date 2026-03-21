# frozen_string_literal: true

module System
  class ProviderInstanceType < BaseRecord
    include System::Base

    # Associations
    belongs_to :account
    belongs_to :provider, class_name: 'System::Provider'
    has_many :region_instance_types, class_name: 'System::RegionInstanceType', dependent: :destroy
    has_many :provider_regions, through: :region_instance_types
    has_many :node_instances, class_name: 'System::NodeInstance'

    # Validations
    validates :name, presence: true
    validates :instance_type_code, presence: true, uniqueness: { scope: :provider_id }

    # Scopes
    scope :for_provider, ->(provider) { where(provider: provider) }
    scope :by_vcpus, ->(min, max = nil) { max ? where(vcpus: min..max) : where('vcpus >= ?', min) }
    scope :by_memory, ->(min, max = nil) { max ? where(memory_mb: min..max) : where('memory_mb >= ?', min) }

    # Specs accessor
    store_accessor :specs

    # Human-readable memory
    def memory_gb
      return nil unless memory_mb

      (memory_mb / 1024.0).round(1)
    end

    # Display string
    def display_name
      parts = [name]
      parts << "#{vcpus} vCPUs" if vcpus
      parts << "#{memory_gb} GB" if memory_gb
      parts.join(' - ')
    end

    # Check availability in a specific region
    def available_in_region?(region)
      region_instance_types.exists?(
        provider_region: region,
        available: true
      )
    end

    # Get price for a specific region
    def price_in_region(region)
      rit = region_instance_types.find_by(provider_region: region)
      rit&.hourly_price || hourly_price
    end
  end
end
