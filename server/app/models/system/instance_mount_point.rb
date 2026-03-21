# frozen_string_literal: true

module System
  class InstanceMountPoint < BaseRecord
    include System::Base

    # === Constants ===
    STATUSES = %w[pending mounted unmounted error].freeze

    # === Associations ===
    belongs_to :node_instance, class_name: 'System::NodeInstance'
    belongs_to :mount_point, class_name: 'System::NodeMountPoint'

    # Delegate account access through instance
    delegate :account, to: :node_instance
    delegate :account_id, to: :node_instance

    # === Validations ===
    validates :node_instance_id, uniqueness: { scope: :mount_point_id, message: 'already has this mount point' }
    validates :status, presence: true, inclusion: { in: STATUSES }

    # === Scopes ===
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :by_status, ->(status) { where(status: status) }
    scope :pending, -> { by_status('pending') }
    scope :mounted, -> { by_status('mounted') }
    scope :unmounted, -> { by_status('unmounted') }
    scope :errored, -> { by_status('error') }

    # === Methods ===
    def pending?
      status == 'pending'
    end

    def mounted?
      status == 'mounted'
    end

    def unmounted?
      status == 'unmounted'
    end

    def error?
      status == 'error'
    end

    def merged_config
      (mount_point.options || {}).deep_merge(config || {})
    end

    def mount_path
      mount_point&.mount_path
    end

    def mount_type
      mount_point&.mount_type
    end

    def mount_name
      mount_point&.name
    end

    def instance_name
      node_instance&.name
    end

    def mark_mounted!
      update!(status: 'mounted')
    end

    def mark_unmounted!
      update!(status: 'unmounted')
    end

    def mark_error!(message = nil)
      update!(status: 'error', config: config.merge('error_message' => message))
    end
  end
end
