# frozen_string_literal: true

module System
  class Provider < BaseRecord
    include System::Base

    # Provider type constants
    PROVIDER_TYPES = %w[aws openstack gcp azure digitalocean linode vultr custom mock].freeze

    # Associations
    belongs_to :account
    has_many :provider_regions, class_name: 'System::ProviderRegion', dependent: :destroy
    has_many :provider_connections, class_name: 'System::ProviderConnection', dependent: :destroy
    has_many :provider_instance_types, class_name: 'System::ProviderInstanceType', dependent: :destroy

    # Volume associations (Release 4)
    has_many :provider_volume_types, class_name: 'System::ProviderVolumeType', dependent: :destroy

    # Network associations (Release 4)
    has_many :provider_networks, class_name: 'System::ProviderNetwork', dependent: :destroy

    # Operation associations (Release 4)
    has_many :operations, class_name: 'System::Operation', as: :operable, dependent: :destroy

    # Validations
    validates :name, presence: true, uniqueness: { scope: :account_id }
    validates :provider_type, presence: true, inclusion: { in: PROVIDER_TYPES }

    # Scopes
    scope :by_type, ->(type) { where(provider_type: type) }
    scope :aws, -> { where(provider_type: 'aws') }
    scope :openstack, -> { where(provider_type: 'openstack') }
    scope :gcp, -> { where(provider_type: 'gcp') }
    scope :azure, -> { where(provider_type: 'azure') }

    # Config and capabilities accessors
    store_accessor :config
    store_accessor :capabilities

    # Helper methods
    def aws?
      provider_type == 'aws'
    end

    def openstack?
      provider_type == 'openstack'
    end

    def gcp?
      provider_type == 'gcp'
    end

    def azure?
      provider_type == 'azure'
    end

    def custom?
      provider_type == 'custom'
    end

    def has_capability?(capability)
      capabilities&.dig(capability.to_s) == true
    end
  end
end
