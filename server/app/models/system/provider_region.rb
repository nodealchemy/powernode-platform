# frozen_string_literal: true

module System
  class ProviderRegion < BaseRecord
    # Associations
    belongs_to :account
    belongs_to :provider, class_name: 'System::Provider'
    has_many :availability_zones, class_name: 'System::ProviderAvailabilityZone', dependent: :destroy
    has_many :region_instance_types, class_name: 'System::RegionInstanceType', dependent: :destroy
    has_many :provider_instance_types, through: :region_instance_types
    has_many :node_instances, class_name: 'System::NodeInstance'

    # Volume associations (Release 4)
    has_many :region_volume_types, class_name: 'System::RegionVolumeType', dependent: :destroy
    has_many :provider_volume_types, through: :region_volume_types, source: :volume_type
    has_many :provider_volumes, class_name: 'System::ProviderVolume'

    # Network associations (Release 4)
    has_many :provider_networks, class_name: 'System::ProviderNetwork'

    # Validations
    validates :name, presence: true
    validates :region_code, presence: true, uniqueness: { scope: :provider_id }

    # Scopes
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :ordered, -> { order(:name) }
    scope :for_provider, ->(provider) { where(provider: provider) }

    # Capabilities accessor
    store_accessor :capabilities

    def has_capability?(capability)
      capabilities&.dig(capability.to_s) == true
    end

    # Get available instance types for this region
    def available_instance_types
      provider_instance_types.where(
        system_region_instance_types: { available: true }
      )
    end
  end
end
