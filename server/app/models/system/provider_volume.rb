# frozen_string_literal: true

module System
  class ProviderVolume < BaseRecord
    include System::Base

    # === Constants ===
    STATUSES = %w[creating available in-use deleting deleted error].freeze
    RAID_LEVELS = [0, 1].freeze # 0 = striping, 1 = mirroring

    # === Associations ===
    belongs_to :account
    belongs_to :volume_type, class_name: 'System::ProviderVolumeType', optional: true
    belongs_to :provider_region, class_name: 'System::ProviderRegion', optional: true
    belongs_to :availability_zone, class_name: 'System::ProviderAvailabilityZone', optional: true
    belongs_to :node_instance, class_name: 'System::NodeInstance', optional: true

    has_many :snapshots, class_name: 'System::ProviderVolumeSnapshot', foreign_key: :volume_id, dependent: :restrict_with_error
    has_many :operations, class_name: 'System::Operation', as: :operable, dependent: :destroy

    # RAID members
    has_many :volume_members, class_name: 'System::ProviderVolumeMember', dependent: :destroy

    # === Validations ===
    validates :raid_level, inclusion: { in: RAID_LEVELS }, allow_nil: true
    validates :name, presence: true, uniqueness: { scope: :account_id, case_sensitive: false }
    validates :size_gb, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :iops, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validates :throughput, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

    # === Scopes ===
    scope :by_status, ->(status) { where(status: status) }
    scope :creating, -> { by_status('creating') }
    scope :available, -> { by_status('available') }
    scope :in_use, -> { by_status('in-use') }
    scope :deleting, -> { by_status('deleting') }
    scope :deleted, -> { by_status('deleted') }
    scope :errored, -> { by_status('error') }

    scope :attached, -> { where.not(node_instance_id: nil) }
    scope :unattached, -> { where(node_instance_id: nil) }
    scope :encrypted_volumes, -> { where(encrypted: true) }
    scope :unencrypted_volumes, -> { where(encrypted: false) }
    scope :by_name, -> { order(name: :asc) }
    scope :by_size, -> { order(size_gb: :desc) }

    # === Status Predicates ===
    STATUSES.each do |status_name|
      method_name = status_name.gsub('-', '_')
      define_method("#{method_name}?") { status == status_name }
    end

    # === Methods ===
    def attached?
      node_instance_id.present?
    end

    def can_attach?
      available? && !attached?
    end

    def can_detach?
      in_use? && attached?
    end

    def can_delete?
      (available? || error?) && !attached?
    end

    def can_snapshot?
      available? || in_use?
    end

    def attach_to!(instance, device_name = nil)
      return false unless can_attach?
      update!(
        node_instance: instance,
        device_name: device_name,
        status: 'in-use'
      )
      true
    end

    def detach!
      return false unless can_detach?
      update!(
        node_instance: nil,
        device_name: nil,
        status: 'available'
      )
      true
    end

    def snapshot_count
      snapshots.count
    end

    def provider
      volume_type&.provider || provider_region&.provider
    end

    # === RAID Methods ===
    def raid?
      raid_level.present?
    end

    def raid_capacity
      return size_gb unless raid?
      # RAID 0: striping doubles capacity (size × member_count)
      # RAID 1: mirroring maintains capacity (size only)
      raid_level == 0 ? size_gb * active_member_count : size_gb
    end

    def active_member_count
      raid? ? volume_members.active.count : 1
    end

    def total_member_count
      volume_members.count
    end

    def all_members_ready?
      return true unless raid?
      volume_members.active.all?(&:ready?)
    end

    def add_member!(size_gb:, device_name: nil)
      return false unless raid?
      # Use -1 as default so first member gets index 0
      next_index = (volume_members.maximum(:member_index) || -1) + 1
      volume_members.create!(
        size_gb: size_gb,
        device_name: device_name,
        member_index: next_index,
        status: 'pending'
      )
    end

    def minimum_members_for_raid
      raid_level == 0 ? 2 : 2 # Both RAID 0 and 1 need minimum 2 members
    end

    def has_minimum_members?
      return true unless raid?
      active_member_count >= minimum_members_for_raid
    end
  end
end
