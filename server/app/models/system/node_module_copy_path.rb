# frozen_string_literal: true

module System
  class NodeModuleCopyPath < BaseRecord
    include System::Base

    # === Associations ===
    belongs_to :account
    has_many :node_modules, class_name: 'System::NodeModule', foreign_key: :copy_path_id, dependent: :nullify

    # === Validations ===
    validates :name, presence: true, uniqueness: { scope: :account_id, case_sensitive: false }
    validates :source_path, presence: true
    validates :destination_path, presence: true

    # === Scopes ===
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :recursive, -> { where(recursive: true) }
    scope :non_recursive, -> { where(recursive: false) }
    scope :by_name, -> { order(name: :asc) }

    # === Methods ===
    def copy_options
      {
        recursive: recursive,
        preserve_permissions: preserve_permissions
      }
    end

    def module_count
      node_modules.count
    end
  end
end
