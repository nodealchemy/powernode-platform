# frozen_string_literal: true

module System
  class Node < BaseRecord
    include System::Base

    # Encryption for sensitive fields
    encrypts :ssh_key
    encrypts :ssh_host_key

    # Associations
    belongs_to :account
    belongs_to :node_template, class_name: 'System::NodeTemplate'
    belongs_to :worker, optional: true
    has_many :node_instances, class_name: 'System::NodeInstance', dependent: :destroy

    # Module associations (Release 3)
    has_many :node_module_assignments, class_name: 'System::NodeModuleAssignment', dependent: :destroy
    has_many :node_modules, through: :node_module_assignments

    # Operation associations (Release 4)
    has_many :operations, class_name: 'System::Operation', as: :operable, dependent: :destroy

    # Validations
    validates :name, presence: true, uniqueness: { scope: :account_id }

    # Config accessors
    store_accessor :config

    # Scopes
    scope :with_worker, -> { where.not(worker_id: nil) }
    scope :without_worker, -> { where(worker_id: nil) }
    scope :with_public_ip, -> { where(allocate_public_ip: true) }
    scope :with_tmpfs, -> { where(tmpfs_store: true) }
    scope :without_tmpfs, -> { where(tmpfs_store: false) }

    # === Runtime Tracking Methods ===
    def increment_runtime!(minutes = 1)
      increment!(:runtime_amount, minutes)
    end

    def runtime_hours
      (runtime_amount || 0) / 60.0
    end

    def runtime_days
      runtime_hours / 24.0
    end

    def reset_runtime!
      update!(runtime_amount: 0)
    end

    # === Storage Methods ===
    def uses_tmpfs?
      tmpfs_store == true
    end

    def enable_tmpfs!
      update!(tmpfs_store: true)
    end

    def disable_tmpfs!
      update!(tmpfs_store: false)
    end
  end
end
