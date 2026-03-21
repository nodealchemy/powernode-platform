# frozen_string_literal: true

module System
  class ProviderNetwork < BaseRecord
    include System::Base

    # === Constants ===
    STATUSES = %w[pending available deleting deleted error].freeze

    # === Associations ===
    belongs_to :account
    belongs_to :provider, class_name: 'System::Provider'
    belongs_to :provider_region, class_name: 'System::ProviderRegion', optional: true

    has_many :subnets, class_name: 'System::ProviderNetworkSubnet', foreign_key: :network_id, dependent: :destroy
    has_many :operations, class_name: 'System::Operation', as: :operable, dependent: :destroy

    # === Validations ===
    validates :name, presence: true, uniqueness: { scope: :account_id, case_sensitive: false }
    validates :cidr_block, presence: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validate :valid_cidr_format

    # === Scopes ===
    scope :by_status, ->(status) { where(status: status) }
    scope :pending, -> { by_status('pending') }
    scope :available, -> { by_status('available') }
    scope :deleting, -> { by_status('deleting') }
    scope :deleted, -> { by_status('deleted') }
    scope :errored, -> { by_status('error') }

    scope :default_networks, -> { where(is_default: true) }
    scope :custom_networks, -> { where(is_default: false) }
    scope :with_dns_support, -> { where(enable_dns_support: true) }
    scope :with_dns_hostnames, -> { where(enable_dns_hostnames: true) }
    scope :by_name, -> { order(name: :asc) }

    # === Status Predicates ===
    STATUSES.each do |status_name|
      define_method("#{status_name}?") { status == status_name }
    end

    # === Methods ===
    def can_delete?
      available? && !is_default && subnets.empty?
    end

    def subnet_count
      subnets.count
    end

    def public_subnets
      subnets.where(is_public: true)
    end

    def private_subnets
      subnets.where(is_public: false)
    end

    def available_ip_count
      subnets.sum(:available_ip_count)
    end

    private

    def valid_cidr_format
      return unless cidr_block.present?
      # Basic CIDR validation (e.g., 10.0.0.0/16)
      unless cidr_block.match?(/\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\/\d{1,2}\z/)
        errors.add(:cidr_block, 'must be a valid CIDR block (e.g., 10.0.0.0/16)')
      end
    end
  end
end
