# frozen_string_literal: true

module System
  class NodeModule < BaseRecord
    include System::Base

    # === Constants ===
    VARIETIES = %w[config instance subscription].freeze

    # === Associations ===
    belongs_to :account
    belongs_to :node_platform, class_name: 'System::NodePlatform', optional: true
    belongs_to :category, class_name: 'System::NodeModuleCategory', optional: true
    belongs_to :copy_path, class_name: 'System::NodeModuleCopyPath', optional: true

    # Versioning associations
    has_many :versions, class_name: 'System::NodeModuleVersion', dependent: :destroy
    belongs_to :current_version, class_name: 'System::NodeModuleVersion', optional: true

    # Node assignments (which nodes have this module)
    has_many :node_module_assignments, class_name: 'System::NodeModuleAssignment', dependent: :destroy
    has_many :nodes, through: :node_module_assignments

    # Template assignments (which templates include this module)
    has_many :template_modules, class_name: 'System::TemplateModule', dependent: :destroy
    has_many :node_templates, through: :template_modules

    # Puppet module assignments (configuration management)
    has_many :module_puppet_assignments, class_name: 'System::ModulePuppetAssignment', dependent: :destroy
    has_many :puppet_modules, through: :module_puppet_assignments

    # Dependencies (what this module requires)
    has_many :module_dependencies,
             class_name: 'System::ModuleDependency',
             foreign_key: :node_module_id,
             dependent: :destroy
    has_many :dependencies,
             through: :module_dependencies,
             source: :dependency

    # Dependents (what requires this module)
    has_many :dependent_relationships,
             class_name: 'System::ModuleDependency',
             foreign_key: :dependency_id,
             dependent: :destroy
    has_many :dependents,
             through: :dependent_relationships,
             source: :node_module

    # === Validations ===
    validates :name, presence: true, uniqueness: { scope: :account_id, case_sensitive: false }
    validates :variety, presence: true, inclusion: { in: VARIETIES }
    validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    # === Scopes ===
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :public_modules, -> { where(public: true) }
    scope :private_modules, -> { where(public: false) }
    scope :by_variety, ->(variety) { where(variety: variety) }
    scope :config_modules, -> { by_variety('config') }
    scope :instance_modules, -> { by_variety('instance') }
    scope :subscription_modules, -> { by_variety('subscription') }
    scope :by_priority, -> { order(priority: :desc, name: :asc) }
    scope :by_name, -> { order(name: :asc) }
    scope :for_platform, ->(platform_id) { where(node_platform_id: platform_id) }
    scope :in_category, ->(category_id) { where(category_id: category_id) }
    scope :locked, -> { where(lock_spec: true) }
    scope :unlocked, -> { where(lock_spec: false) }
    scope :versioned, -> { where.not(current_version_id: nil) }

    # === Callbacks ===
    before_update :check_lock_status, if: :will_save_change_to_versioned_attributes?
    after_update :auto_create_version, if: :saved_change_to_versioned_attributes?

    # === Methods ===
    def config?
      variety == 'config'
    end

    def instance?
      variety == 'instance'
    end

    def subscription?
      variety == 'subscription'
    end

    def has_dependencies?
      module_dependencies.exists?
    end

    def has_dependents?
      dependent_relationships.exists?
    end

    def required_dependencies
      dependencies.joins(:module_dependencies).where(system_module_dependencies: { required: true })
    end

    def optional_dependencies
      dependencies.joins(:module_dependencies).where(system_module_dependencies: { required: false })
    end

    def all_dependencies(visited = Set.new)
      return [] if visited.include?(id)
      visited.add(id)

      direct = dependencies.to_a
      indirect = direct.flat_map { |dep| dep.all_dependencies(visited) }
      (direct + indirect).uniq
    end

    def assignment_count
      node_module_assignments.count
    end

    def template_count
      template_modules.count
    end

    def puppet_module_count
      module_puppet_assignments.count
    end

    def has_puppet_modules?
      module_puppet_assignments.exists?
    end

    def enabled_puppet_modules
      puppet_modules.enabled
    end

    def puppet_assignments_by_priority
      module_puppet_assignments.enabled.by_priority
    end

    # === Versioning Methods ===

    # Check if module spec is locked (immutable)
    def locked?
      lock_spec == true
    end

    # Lock the module to prevent updates
    def lock!
      update!(lock_spec: true)
    end

    # Unlock the module to allow updates
    def unlock!
      update!(lock_spec: false)
    end

    # Get version service for this module
    def version_service(current_user: nil)
      System::ModuleVersionService.new(self, current_user: current_user)
    end

    # Create a new version with changelog
    def create_version!(changelog: nil, user: nil)
      version_service(current_user: user).create_version(changelog: changelog)
    end

    # Rollback to a specific version
    def rollback_to!(version, changelog: nil, user: nil)
      version_service(current_user: user).rollback_to(version, changelog: changelog)
    end

    # Rollback to previous version
    def rollback_to_previous!(user: nil)
      version_service(current_user: user).rollback_to_previous
    end

    # Check if module has any versions
    def versioned?
      versions.exists?
    end

    # Get the latest version
    def latest_version
      versions.ordered.first
    end

    # Get version by number
    def version(number)
      versions.find_by(version_number: number)
    end

    # Get version history
    def version_history(limit: 20)
      version_service.version_history(limit: limit)
    end

    # Check if data file integrity matches checksum
    def verify_data_file(content)
      return false unless data_checksum.present?

      Digest::SHA256.hexdigest(content) == data_checksum
    end

    # Set data file with automatic checksum calculation
    def set_data_file(filename:, content:)
      self.data_file_name = filename
      self.data_file_size = content.bytesize
      self.data_checksum = Digest::SHA256.hexdigest(content)
    end

    private

    # Attributes that trigger versioning when changed
    VERSIONED_ATTRIBUTES = %w[
      mask file_spec package_spec config
      data_file_name data_checksum data_file_size
    ].freeze

    def will_save_change_to_versioned_attributes?
      (changed & VERSIONED_ATTRIBUTES).any?
    end

    def saved_change_to_versioned_attributes?
      (saved_changes.keys & VERSIONED_ATTRIBUTES).any?
    end

    def check_lock_status
      return unless lock_spec && !lock_spec_changed?

      errors.add(:base, 'Module is locked and cannot be modified')
      throw(:abort)
    end

    def auto_create_version
      # Skip if we're in the middle of a rollback or manual version creation
      return if @skip_auto_version

      # Only auto-version if this is a significant change
      return unless versioned?

      @skip_auto_version = true
      create_version!(changelog: 'Auto-versioned on update')
    ensure
      @skip_auto_version = false
    end
  end
end
