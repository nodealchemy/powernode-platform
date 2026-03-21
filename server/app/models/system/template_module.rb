# frozen_string_literal: true

module System
  class TemplateModule < BaseRecord
    include System::Base

    # === Associations ===
    belongs_to :node_template, class_name: 'System::NodeTemplate'
    belongs_to :node_module, class_name: 'System::NodeModule'

    # Delegate account access through template
    delegate :account, to: :node_template
    delegate :account_id, to: :node_template

    # === Validations ===
    validates :node_template_id, uniqueness: { scope: :node_module_id, message: 'already has this module' }
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

    def template_name
      node_template&.name
    end
  end
end
