# frozen_string_literal: true

module Shared
  # Unified prompt template system for AI Workflows and CI/CD Pipelines
  # Supports Liquid templating, versioning, and domain-scoped templates.
  #
  # Domains:
  #   - workflow: Templates for AI workflow nodes
  #   - cicd: Templates for CI/CD pipeline steps
  #   - general: Templates available to both systems
  #
  class PromptTemplate < ApplicationRecord
    self.table_name = "shared_prompt_templates"

    # ============================================
    # Constants
    # ============================================
    CATEGORIES = %w[review implement security deploy docs custom general agent workflow].freeze
    DOMAINS = %w[ai_workflow cicd general].freeze

    # ============================================
    # Associations
    # ============================================
    belongs_to :account
    belongs_to :created_by, class_name: "User", optional: true
    belongs_to :parent_template, class_name: "Shared::PromptTemplate", optional: true

    has_many :versions, class_name: "Shared::PromptTemplate",
             foreign_key: :parent_template_id, dependent: :nullify

    # Polymorphic usage tracking
    has_many :ai_workflow_nodes, class_name: "Ai::WorkflowNode", foreign_key: :shared_prompt_template_id, dependent: :nullify
    has_many :ci_cd_pipeline_steps, class_name: "CiCd::PipelineStep",
             foreign_key: :shared_prompt_template_id, dependent: :nullify

    # ============================================
    # Validations
    # ============================================
    validates :name, presence: true, length: { maximum: 255 }
    validates :slug, presence: true,
                     uniqueness: { scope: :account_id },
                     format: { with: /\A[a-z0-9\-_]+\z/, message: "only allows lowercase letters, numbers, hyphens, and underscores" }
    validates :category, presence: true, inclusion: { in: CATEGORIES }
    validates :domain, presence: true, inclusion: { in: DOMAINS }
    validates :content, presence: true
    validates :version, numericality: { greater_than: 0 }

    validate :system_templates_immutable, on: :update

    # ============================================
    # Scopes
    # ============================================
    scope :active, -> { where(is_active: true) }
    scope :inactive, -> { where(is_active: false) }
    scope :system_templates, -> { where(is_system: true) }
    scope :user_templates, -> { where(is_system: false) }
    scope :by_category, ->(category) { where(category: category) }
    scope :for_domain, ->(domain) { where(domain: [domain, "general"]) }
    scope :for_ai_workflow, -> { for_domain("ai_workflow") }
    scope :for_cicd, -> { for_domain("cicd") }
    scope :latest_versions, -> { where(parent_template_id: nil) }
    scope :search, ->(query) {
      where("name ILIKE :q OR description ILIKE :q OR slug ILIKE :q", q: "%#{query}%")
    }

    # ============================================
    # Callbacks
    # ============================================
    before_validation :generate_slug, on: :create
    before_validation :set_defaults, on: :create

    # ============================================
    # Instance Methods
    # ============================================

    # Render the template with provided variables
    #
    # @param variables [Hash] Variables to substitute
    # @return [String] Rendered content
    def render(variables = {})
      Shared::PromptRenderer.new(self, variables: variables).render
    end

    # Preview render with sample data
    #
    # @param variables [Hash] Sample variables
    # @return [String] Preview content
    def preview(variables = {})
      Shared::PromptRenderer.new(self, variables: variables).preview
    end

    # Validate template syntax
    #
    # @return [Hash] Validation result
    def validate_syntax
      Shared::PromptRenderer.new(self).validate
    end

    # Extract variable names from template content
    #
    # @return [Array<String>] Variable names
    def extract_variables
      Shared::PromptRenderer.new(self).extract_variables
    end

    # Create a new version of this template
    #
    # @param new_content [String] The updated content
    # @param created_by [User] The user creating the version
    # @return [Shared::PromptTemplate] The new version
    def create_version(new_content, created_by: nil)
      transaction do
        new_version = dup
        new_version.content = new_content
        new_version.version = version + 1
        new_version.parent_template = latest_parent
        new_version.created_by = created_by
        new_version.is_system = false # Versions of system templates are not system templates
        new_version.save!

        # Deactivate current version for non-system templates
        update!(is_active: false) unless is_system?

        new_version
      end
    end

    # Duplicate this template with a new name
    #
    # @param new_name [String] Name for the duplicate
    # @param created_by [User] The user creating the duplicate
    # @return [Shared::PromptTemplate] The duplicate
    def duplicate(new_name, created_by: nil)
      dup.tap do |copy|
        copy.name = new_name
        copy.slug = nil # Will be auto-generated
        copy.version = 1
        copy.parent_template = nil
        copy.created_by = created_by
        copy.is_system = false
        copy.save!
      end
    end

    # Get the root parent template
    #
    # @return [Shared::PromptTemplate]
    def latest_parent
      parent_template || self
    end

    # Get all versions of this template
    #
    # @return [ActiveRecord::Relation]
    def all_versions
      latest_parent.versions.order(version: :desc)
    end

    # Get variable definitions with metadata
    #
    # @return [Array<Hash>]
    def variable_definitions
      (variables || []).map do |var|
        {
          name: var["name"],
          type: var["type"] || "string",
          required: var["required"] || false,
          default: var["default"],
          description: var["description"]
        }
      end
    end

    # Validate provided variables against definitions
    #
    # @param provided_variables [Hash] Variables to validate
    # @return [Array<String>] List of validation errors
    def validate_variables(provided_variables)
      errors = []
      variable_definitions.each do |var_def|
        if var_def[:required] && !provided_variables.key?(var_def[:name].to_s)
          errors << "Missing required variable: #{var_def[:name]}"
        end
      end
      errors
    end

    # Check if template can be used in a specific domain
    #
    # @param target_domain [String] The domain to check
    # @return [Boolean]
    def usable_in?(target_domain)
      domain == "general" || domain == target_domain.to_s
    end

    # Usage count across all references
    #
    # @return [Integer]
    def usage_count
      ai_workflow_nodes.count + ci_cd_pipeline_steps.count
    end

    private

    def generate_slug
      return if slug.present?

      base_slug = name.to_s.parameterize
      self.slug = base_slug
      counter = 1

      while account.shared_prompt_templates.where(slug: slug).where.not(id: id).exists?
        self.slug = "#{base_slug}-#{counter}"
        counter += 1
      end
    end

    def set_defaults
      self.domain ||= "general"
      self.category ||= "custom"
      self.version ||= 1
      self.variables ||= []
      self.metadata ||= {}
    end

    def system_templates_immutable
      return unless is_system? && content_changed?

      errors.add(:content, "cannot modify system templates")
    end
  end
end
