# frozen_string_literal: true

module System
  class PuppetModule < BaseRecord
    include System::Base

    # == Associations
    belongs_to :account
    has_many :puppet_resources, class_name: 'System::PuppetResource',
             foreign_key: :puppet_module_id, dependent: :destroy, inverse_of: :puppet_module
    has_many :module_puppet_assignments, class_name: 'System::ModulePuppetAssignment',
             foreign_key: :puppet_module_id, dependent: :destroy, inverse_of: :puppet_module
    has_many :node_modules, through: :module_puppet_assignments

    # == Validations
    validates :name, presence: true,
              uniqueness: { scope: :account_id, message: 'must be unique within account' },
              length: { maximum: 255 }
    validates :version, length: { maximum: 50 }, allow_blank: true
    validates :author, length: { maximum: 255 }, allow_blank: true
    validates :license, length: { maximum: 100 }, allow_blank: true
    validates :source_url, length: { maximum: 500 }, allow_blank: true
    validates :project_url, length: { maximum: 500 }, allow_blank: true
    validates :forge_name, length: { maximum: 255 }, allow_blank: true
    validate :validate_dependencies_format

    # == Scopes
    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }
    scope :public_modules, -> { where(public: true) }
    scope :private_modules, -> { where(public: false) }
    scope :by_author, ->(author) { where(author: author) }
    scope :from_forge, -> { where.not(forge_name: [nil, '']) }
    scope :search, ->(query) {
      where('name ILIKE :q OR description ILIKE :q OR forge_name ILIKE :q', q: "%#{query}%")
    }

    # == Class Methods
    def self.find_by_forge_name(forge_name)
      find_by(forge_name: forge_name)
    end

    # == Instance Methods
    def enable!
      update!(enabled: true)
    end

    def disable!
      update!(enabled: false)
    end

    def make_public!
      update!(public: true)
    end

    def make_private!
      update!(public: false)
    end

    def forge_module?
      forge_name.present?
    end

    def full_name
      forge_name.presence || name
    end

    def dependency_names
      dependencies.map { |dep| dep['name'] || dep[:name] }
    end

    def has_dependency?(module_name)
      dependency_names.include?(module_name)
    end

    def add_dependency(name, version_requirement = nil)
      dep = { 'name' => name }
      dep['version_requirement'] = version_requirement if version_requirement.present?
      self.dependencies = dependencies + [dep]
    end

    def remove_dependency(name)
      self.dependencies = dependencies.reject { |dep| (dep['name'] || dep[:name]) == name }
    end

    def resources_by_type(type)
      puppet_resources.where(resource_type: type)
    end

    def enabled_resources
      puppet_resources.enabled
    end

    def resource_types
      puppet_resources.distinct.pluck(:resource_type)
    end

    def resource_count
      puppet_resources.count
    end

    def assigned_to_modules
      node_modules.distinct
    end

    def assigned_module_count
      module_puppet_assignments.count
    end

    private

    def validate_dependencies_format
      return if dependencies.blank?

      unless dependencies.is_a?(Array)
        errors.add(:dependencies, 'must be an array')
        return
      end

      dependencies.each_with_index do |dep, index|
        unless dep.is_a?(Hash)
          errors.add(:dependencies, "item at index #{index} must be a hash")
          next
        end

        unless dep['name'].present? || dep[:name].present?
          errors.add(:dependencies, "item at index #{index} must have a name")
        end
      end
    end
  end
end
