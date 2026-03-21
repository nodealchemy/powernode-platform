# frozen_string_literal: true

module System
  class ProviderVolumeType < BaseRecord
    include System::Base

    # === Constants ===
    VOLUME_TYPES = %w[gp2 gp3 io1 io2 st1 sc1 standard ssd hdd custom].freeze

    # === Associations ===
    belongs_to :account
    belongs_to :provider, class_name: 'System::Provider'

    has_many :volumes, class_name: 'System::ProviderVolume', foreign_key: :volume_type_id, dependent: :restrict_with_error
    has_many :region_volume_types, class_name: 'System::RegionVolumeType', foreign_key: :volume_type_id, dependent: :destroy
    has_many :provider_regions, through: :region_volume_types

    # === Validations ===
    validates :name, presence: true, uniqueness: { scope: :account_id, case_sensitive: false }
    validates :volume_type, presence: true, inclusion: { in: VOLUME_TYPES }
    validates :min_size_gb, numericality: { only_integer: true, greater_than: 0 }
    validates :max_size_gb, numericality: { only_integer: true, greater_than: 0 }
    validate :max_size_greater_than_min

    # === Scopes ===
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :by_type, ->(type) { where(volume_type: type) }
    scope :ssd_types, -> { where(volume_type: %w[gp2 gp3 io1 io2 ssd]) }
    scope :hdd_types, -> { where(volume_type: %w[st1 sc1 standard hdd]) }
    scope :by_name, -> { order(name: :asc) }

    # === Methods ===
    def ssd?
      %w[gp2 gp3 io1 io2 ssd].include?(volume_type)
    end

    def hdd?
      %w[st1 sc1 standard hdd].include?(volume_type)
    end

    def provisioned_iops?
      %w[io1 io2].include?(volume_type)
    end

    def valid_size?(size_gb)
      size_gb >= min_size_gb && size_gb <= max_size_gb
    end

    def valid_iops?(iops)
      return true unless min_iops && max_iops
      iops >= min_iops && iops <= max_iops
    end

    def valid_throughput?(throughput)
      return true unless min_throughput && max_throughput
      throughput >= min_throughput && throughput <= max_throughput
    end

    def volume_count
      volumes.count
    end

    private

    def max_size_greater_than_min
      return unless min_size_gb && max_size_gb
      errors.add(:max_size_gb, 'must be greater than or equal to min_size_gb') if max_size_gb < min_size_gb
    end
  end
end
