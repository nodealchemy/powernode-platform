# frozen_string_literal: true

module System
  class ModulePuppetAssignment < BaseRecord
    include System::Base

    # == Associations
    belongs_to :node_module, class_name: 'System::NodeModule',
               foreign_key: :node_module_id, inverse_of: :module_puppet_assignments
    belongs_to :puppet_module, class_name: 'System::PuppetModule',
               foreign_key: :puppet_module_id, inverse_of: :module_puppet_assignments

    # == Delegations
    delegate :account, to: :node_module
    delegate :account_id, to: :node_module
    delegate :name, to: :node_module, prefix: true
    delegate :name, to: :puppet_module, prefix: true

    # == Validations
    validates :node_module_id, uniqueness: {
      scope: :puppet_module_id,
      message: 'puppet module already assigned to this node module'
    }
    validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    # == Scopes
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :by_priority, -> { order(priority: :asc) }
    scope :for_node_module, ->(node_module_id) { where(node_module_id: node_module_id) }
    scope :for_puppet_module, ->(puppet_module_id) { where(puppet_module_id: puppet_module_id) }

    # == Instance Methods
    def enable!
      update!(enabled: true)
    end

    def disable!
      update!(enabled: false)
    end

    def config_value(key)
      config[key.to_s]
    end

    def set_config(key, value)
      self.config = config.merge(key.to_s => value)
    end

    def remove_config(key)
      self.config = config.except(key.to_s)
    end

    def parameter(key)
      parameters[key.to_s]
    end

    def set_parameter(key, value)
      self.parameters = parameters.merge(key.to_s => value)
    end

    def remove_parameter(key)
      self.parameters = parameters.except(key.to_s)
    end

    # Merge base puppet module config with assignment-specific config
    def effective_config
      puppet_module.config.deep_merge(config)
    end

    # Get all enabled resources from the puppet module with assignment parameters applied
    def effective_resources
      puppet_module.puppet_resources.enabled.map do |resource|
        {
          resource: resource,
          parameters: resource.parameters.deep_merge(parameters)
        }
      end
    end

    def display_name
      "#{node_module_name} → #{puppet_module_name}"
    end
  end
end
