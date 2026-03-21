# frozen_string_literal: true

module System
  class NodeInstance < BaseRecord
    # Constants
    VARIETIES = %w[cloud physical dynamic].freeze
    STATUSES = %w[pending provisioning starting running stopping stopped rebooting terminated error].freeze
    MAC_ADDRESS_REGEX = /\A([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})\z/

    # Encryption for sensitive fields
    encrypts :key

    # Associations
    belongs_to :node, class_name: 'System::Node'
    belongs_to :provider_region, class_name: 'System::ProviderRegion', optional: true
    belongs_to :provider_instance_type, class_name: 'System::ProviderInstanceType', optional: true

    # Mount point associations (Release 3)
    has_many :instance_mount_points, class_name: 'System::InstanceMountPoint', dependent: :destroy
    has_many :mount_points, through: :instance_mount_points, source: :mount_point

    # Operation associations (Release 4)
    has_many :operations, class_name: 'System::Operation', as: :operable, dependent: :destroy

    # Volume associations (Release 4)
    has_many :provider_volumes, class_name: 'System::ProviderVolume'

    # Delegations
    delegate :account, :account_id, to: :node

    # Validations
    validates :name, presence: true, uniqueness: { scope: :node_id }
    validates :variety, presence: true, inclusion: { in: VARIETIES }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :mac_address, format: { with: MAC_ADDRESS_REGEX, message: 'must be a valid MAC address' }, allow_nil: true
    validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
    validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true

    # Config accessors
    store_accessor :config

    # Scopes
    scope :cloud, -> { where(variety: 'cloud') }
    scope :physical, -> { where(variety: 'physical') }
    scope :dynamic, -> { where(variety: 'dynamic') }
    scope :pending, -> { where(status: 'pending') }
    scope :provisioning, -> { where(status: 'provisioning') }
    scope :running, -> { where(status: 'running') }
    scope :stopped, -> { where(status: 'stopped') }
    scope :terminated, -> { where(status: 'terminated') }
    scope :errored, -> { where(status: 'error') }
    scope :active, -> { where(status: %w[pending provisioning running stopped]) }

    # Status predicates
    STATUSES.each do |status_name|
      define_method("#{status_name}?") { status == status_name }
    end

    # Variety predicates
    VARIETIES.each do |variety_name|
      define_method("#{variety_name}?") { variety == variety_name }
    end

    # Check if instance is active (not terminated or error)
    def active?
      !terminated? && !error?
    end

    # Control action predicates
    def can_start?
      %w[stopped error].include?(status)
    end

    def can_stop?
      %w[running starting].include?(status)
    end

    def can_reboot?
      status == "running"
    end

    def can_terminate?
      %w[stopped error running].include?(status)
    end

    # === Geolocation Methods ===
    def has_coordinates?
      latitude.present? && longitude.present?
    end

    def coordinates
      return nil unless has_coordinates?
      { latitude: latitude, longitude: longitude }
    end

    def set_coordinates!(lat, lng)
      update!(latitude: lat, longitude: lng)
    end

    # === Network Methods ===
    def has_mac_address?
      mac_address.present?
    end

    def normalized_mac_address
      return nil unless has_mac_address?
      mac_address.upcase.gsub('-', ':')
    end

    def netboot_enabled?
      physical? && private_netboot == true
    end

    def enable_netboot!
      return false unless physical?
      update!(private_netboot: true)
    end

    def disable_netboot!
      update!(private_netboot: false)
    end
  end
end
