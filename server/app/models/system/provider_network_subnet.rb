# frozen_string_literal: true

module System
  class ProviderNetworkSubnet < BaseRecord
    include System::Base

    # === Constants ===
    STATUSES = %w[pending available deleting deleted error].freeze

    # === Associations ===
    belongs_to :network, class_name: 'System::ProviderNetwork'
    belongs_to :availability_zone, class_name: 'System::ProviderAvailabilityZone', optional: true

    # Delegate account access through network
    delegate :account, to: :network
    delegate :account_id, to: :network
    delegate :provider, to: :network
    delegate :provider_region, to: :network

    # === Validations ===
    validates :name, presence: true, uniqueness: { scope: :network_id, case_sensitive: false }
    validates :cidr_block, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validate :valid_cidr_format
    validate :cidr_within_network

    # === Scopes ===
    scope :by_status, ->(status) { where(status: status) }
    scope :pending, -> { by_status('pending') }
    scope :available, -> { by_status('available') }
    scope :deleting, -> { by_status('deleting') }
    scope :deleted, -> { by_status('deleted') }
    scope :errored, -> { by_status('error') }

    scope :public_subnets, -> { where(is_public: true) }
    scope :private_subnets, -> { where(is_public: false) }
    scope :auto_assign_public_ip, -> { where(map_public_ip_on_launch: true) }
    scope :by_name, -> { order(name: :asc) }

    # === Status Predicates ===
    STATUSES.each do |status_name|
      define_method("#{status_name}?") { status == status_name }
    end

    # === Methods ===
    def can_delete?
      available?
    end

    def network_name
      network&.name
    end

    def zone_name
      availability_zone&.name
    end

    private

    def valid_cidr_format
      return unless cidr_block.present?
      unless cidr_block.match?(/\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\/\d{1,2}\z/)
        errors.add(:cidr_block, 'must be a valid CIDR block (e.g., 10.0.1.0/24)')
      end
    end

    def cidr_within_network
      # This would need proper IP calculation to validate
      # For now, just check basic format
      true
    end
  end
end
