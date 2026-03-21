# frozen_string_literal: true

module System
  class ModuleDependency < BaseRecord
    include System::Base

    self.table_name = 'system_module_dependencies'

    # === Constants ===
    DEPENDENCY_TYPES = %w[requires recommends conflicts provides].freeze

    # === Associations ===
    belongs_to :node_module, class_name: 'System::NodeModule'
    belongs_to :dependency, class_name: 'System::NodeModule'

    # Delegate account access through node_module
    delegate :account, to: :node_module
    delegate :account_id, to: :node_module

    # === Validations ===
    validates :node_module_id, uniqueness: { scope: :dependency_id, message: 'already has this dependency' }
    validates :dependency_type, presence: true, inclusion: { in: DEPENDENCY_TYPES }
    validate :not_self_referential
    validate :no_circular_dependency

    # === Scopes ===
    scope :required, -> { where(required: true) }
    scope :optional, -> { where(required: false) }
    scope :by_type, ->(type) { where(dependency_type: type) }
    scope :requires, -> { by_type('requires') }
    scope :recommends, -> { by_type('recommends') }
    scope :conflicts, -> { by_type('conflicts') }
    scope :provides, -> { by_type('provides') }

    # === Methods ===
    def requires?
      dependency_type == 'requires'
    end

    def recommends?
      dependency_type == 'recommends'
    end

    def conflicts?
      dependency_type == 'conflicts'
    end

    def provides?
      dependency_type == 'provides'
    end

    def dependency_name
      dependency&.name
    end

    def module_name
      node_module&.name
    end

    private

    def not_self_referential
      if node_module_id == dependency_id
        errors.add(:dependency_id, "can't be the same as the module itself")
      end
    end

    def no_circular_dependency
      return unless dependency
      return unless node_module

      if dependency.all_dependencies.include?(node_module)
        errors.add(:dependency_id, 'would create a circular dependency')
      end
    end
  end
end
