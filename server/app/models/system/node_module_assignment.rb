# frozen_string_literal: true

module System
  class NodeModuleAssignment < BaseRecord
    include System::Base

    # === Associations ===
    belongs_to :node, class_name: 'System::Node'
    belongs_to :node_module, class_name: 'System::NodeModule'

    # Delegate account access through node
    delegate :account, to: :node
    delegate :account_id, to: :node

    # === Validations ===
    validates :node_id, uniqueness: { scope: :node_module_id, message: 'already has this module assigned' }
    validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    # === Scopes ===
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :by_priority, -> { order(priority: :desc) }

    # === Methods ===
    def merged_config
      (node_module.config || {}).deep_merge(config || {})
    end

    def module_name
      node_module&.name
    end

    def module_variety
      node_module&.variety
    end
  end
end
