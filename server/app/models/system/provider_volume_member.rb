# frozen_string_literal: true

module System
  # Represents individual disk members in a RAID volume configuration
  # Used when raid_level is set on the parent ProviderVolume
  class ProviderVolumeMember < BaseRecord
    include System::Base

    # === Constants ===
    STATUSES = %w[pending creating available attached error deleted].freeze

    # === Associations ===
    belongs_to :provider_volume, class_name: 'System::ProviderVolume'

    # Delegate account access through volume
    delegate :account, to: :provider_volume
    delegate :account_id, to: :provider_volume

    # === Validations ===
    validates :size_gb, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :member_index, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :member_index, uniqueness: { scope: :provider_volume_id }

    # === Scopes ===
    scope :by_status, ->(status) { where(status: status) }
    scope :pending, -> { by_status('pending') }
    scope :creating, -> { by_status('creating') }
    scope :available, -> { by_status('available') }
    scope :attached, -> { by_status('attached') }
    scope :errored, -> { by_status('error') }
    scope :deleted, -> { by_status('deleted') }
    scope :ordered, -> { order(member_index: :asc) }
    scope :active, -> { where.not(status: %w[deleted error]) }

    # === Status Predicates ===
    STATUSES.each do |status_name|
      define_method("#{status_name}?") { status == status_name }
    end

    # === Methods ===

    # Check if member is ready for use
    def ready?
      available? || attached?
    end

    # Check if member can be deleted
    def can_delete?
      !attached?
    end

    # Get the provider from the parent volume
    def provider
      provider_volume&.provider
    end

    # Get the region from the parent volume
    def provider_region
      provider_volume&.provider_region
    end

    # Format member info for display
    def display_name
      "#{provider_volume&.name} - Member #{member_index}"
    end
  end
end
