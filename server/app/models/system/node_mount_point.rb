# frozen_string_literal: true

module System
  class NodeMountPoint < BaseRecord
    include System::Base

    # === Constants ===
    MOUNT_TYPES = %w[nfs cifs tmpfs bind efs ebs custom].freeze

    # === Associations ===
    belongs_to :account

    # Instance mount points (which instances have this mount)
    has_many :instance_mount_points, class_name: 'System::InstanceMountPoint', foreign_key: :mount_point_id, dependent: :destroy
    has_many :node_instances, through: :instance_mount_points

    # === Validations ===
    validates :name, presence: true, uniqueness: { scope: :account_id, case_sensitive: false }
    validates :mount_path, presence: true
    validates :mount_type, presence: true, inclusion: { in: MOUNT_TYPES }

    # === Scopes ===
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :auto_mount, -> { where(auto_mount: true) }
    scope :manual_mount, -> { where(auto_mount: false) }
    scope :by_type, ->(type) { where(mount_type: type) }
    scope :nfs_mounts, -> { by_type('nfs') }
    scope :cifs_mounts, -> { by_type('cifs') }
    scope :efs_mounts, -> { by_type('efs') }
    scope :ebs_mounts, -> { by_type('ebs') }
    scope :by_name, -> { order(name: :asc) }

    # === Methods ===
    def nfs?
      mount_type == 'nfs'
    end

    def cifs?
      mount_type == 'cifs'
    end

    def tmpfs?
      mount_type == 'tmpfs'
    end

    def bind?
      mount_type == 'bind'
    end

    def efs?
      mount_type == 'efs'
    end

    def ebs?
      mount_type == 'ebs'
    end

    def custom?
      mount_type == 'custom'
    end

    def cloud_storage?
      %w[efs ebs].include?(mount_type)
    end

    def network_storage?
      %w[nfs cifs efs].include?(mount_type)
    end

    def fstab_entry
      opts = options.presence || {}
      mount_opts = opts['options'] || 'defaults'
      "#{source} #{mount_path} #{mount_type} #{mount_opts} 0 0"
    end

    def instance_count
      instance_mount_points.count
    end
  end
end
