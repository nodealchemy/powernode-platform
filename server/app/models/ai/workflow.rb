# frozen_string_literal: true

module Ai
  class Workflow < ApplicationRecord
    self.table_name = "ai_workflows"

    # Core concerns
    include Auditable
    include Searchable

    # Extracted concerns
    include Ai::Workflow::StateChecks
    include Ai::Workflow::StructureValidation
    include Ai::Workflow::Execution
    include Ai::Workflow::Templates
    include Ai::Workflow::Duplication
    include Ai::Workflow::Statistics
    include Ai::Workflow::Versioning

    # Associations
    belongs_to :account
    belongs_to :creator, class_name: "User"

    has_many :workflow_nodes, class_name: "Ai::WorkflowNode", foreign_key: "ai_workflow_id", dependent: :destroy
    has_many :workflow_edges, class_name: "Ai::WorkflowEdge", foreign_key: "ai_workflow_id", dependent: :destroy
    has_many :workflow_variables, class_name: "Ai::WorkflowVariable", foreign_key: "ai_workflow_id", dependent: :destroy
    has_many :workflow_triggers, class_name: "Ai::WorkflowTrigger", foreign_key: "ai_workflow_id", dependent: :destroy
    has_many :workflow_runs, class_name: "Ai::WorkflowRun", foreign_key: "ai_workflow_id", dependent: :destroy
    has_many :workflow_schedules, class_name: "Ai::WorkflowSchedule", foreign_key: "ai_workflow_id", dependent: :destroy
    has_many :workflow_template_installations, class_name: "Ai::WorkflowTemplateInstallation", foreign_key: "ai_workflow_id", dependent: :destroy
    has_many :workflow_validations, class_name: "WorkflowValidation", foreign_key: :workflow_id, dependent: :destroy

    # Versioning associations
    belongs_to :parent_version, class_name: "Ai::Workflow", optional: true
    has_many :child_versions, class_name: "Ai::Workflow", foreign_key: "parent_version_id", dependent: :nullify

    # Association aliases for convenience and compatibility
    has_many :nodes, -> { }, class_name: "Ai::WorkflowNode", foreign_key: "ai_workflow_id", dependent: :destroy
    has_many :edges, -> { }, class_name: "Ai::WorkflowEdge", foreign_key: "ai_workflow_id", dependent: :destroy
    has_many :variables, -> { }, class_name: "Ai::WorkflowVariable", foreign_key: "ai_workflow_id", dependent: :destroy
    has_many :triggers, -> { }, class_name: "Ai::WorkflowTrigger", foreign_key: "ai_workflow_id", dependent: :destroy
    has_many :runs, -> { }, class_name: "Ai::WorkflowRun", foreign_key: "ai_workflow_id", dependent: :destroy
    has_many :schedules, -> { }, class_name: "Ai::WorkflowSchedule", foreign_key: "ai_workflow_id", dependent: :destroy
    has_many :template_installations, -> { }, class_name: "Ai::WorkflowTemplateInstallation", foreign_key: "ai_workflow_id", dependent: :destroy

    # Workflow type constants
    WORKFLOW_TYPES = %w[ai cicd].freeze

    # Validations
    validates :name, presence: true, length: { minimum: 1, maximum: 255 }
    validates :description, length: { maximum: 1000 }
    validates :slug, presence: true, uniqueness: { scope: [ :account_id, :version ] },
                     length: { maximum: 150 },
                     format: { with: /\A[a-z0-9\-_]+\z/, message: "can only contain lowercase letters, numbers, hyphens, and underscores" }
    validates :status, presence: true, inclusion: {
      in: %w[draft active paused inactive archived]
    }
    validates :visibility, presence: true, inclusion: {
      in: %w[private account public],
      message: "must be a valid visibility level"
    }
    validates :workflow_type, presence: true, inclusion: {
      in: WORKFLOW_TYPES,
      message: "must be 'ai' or 'cicd'"
    }
    validates :configuration, presence: true
    validates :version, presence: true, format: { with: /\A\d+\.\d+\.\d+\z/, message: "must be in semantic version format (x.y.z)" },
                       uniqueness: { scope: [ :account_id, :name ] }
    validates :is_active, inclusion: { in: [ true, false ] }
    validate :only_one_active_version_per_workflow
    validate :validate_workflow_structure
    validate :validate_template_requirements
    validate :validate_configuration_format

    # JSON columns for flexible data storage
    attribute :configuration, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }

    # Scopes
    scope :active, -> { where(status: "active") }
    scope :draft, -> { where(status: "draft") }
    scope :inactive, -> { where(status: "inactive") }
    scope :archived, -> { where(status: "archived") }
    scope :paused, -> { where(status: "paused") }
    scope :templates, -> { where(is_template: true) }
    scope :workflows, -> { where(is_template: false) }
    scope :public_workflows, -> { where(visibility: "public") }
    scope :private_workflows, -> { where(visibility: "private") }
    scope :by_category, ->(category) { where(template_category: category) }
    scope :recently_executed, ->(days = 30) { where("last_executed_at >= ?", days.days.ago) }
    scope :search_by_text, ->(query) {
      where("name ILIKE ? OR description ILIKE ?", "%#{query}%", "%#{query}%")
    }
    # Workflow type scopes - for unified CI/CD and AI workflow system
    scope :ai_workflows, -> { where(workflow_type: "ai") }
    scope :cicd_pipelines, -> { where(workflow_type: "cicd") }
    scope :by_workflow_type, ->(type) { where(workflow_type: type) }

    # Additional scopes for test compatibility
    scope :executable, -> { where(status: %w[active paused]) }
    scope :by_status, ->(status_val) { where(status: status_val) }
    scope :search, ->(query) {
      return all if query.blank?
      where("name ILIKE ? OR description ILIKE ?", "%#{query}%", "%#{query}%")
    }
    scope :recent, ->(period = 1.month) { where("created_at >= ?", period.ago) }

    # Versioning scopes
    scope :active_versions, -> { where(is_active: true) }
    scope :inactive_versions, -> { where(is_active: false) }
    scope :version_family, ->(name, account_id) { where(name: name, account_id: account_id).order(:version) }
    scope :latest_version, ->(name, account_id) { version_family(name, account_id).active_versions.first }
    scope :with_active_runs, -> { joins(:workflow_runs).where(ai_workflow_runs: { status: [ "running", "paused" ] }).distinct }

    # Callbacks
    before_validation :generate_slug, if: -> { name.present? && (slug.blank? || name_changed?) }
    before_save :update_version_if_changed
    after_create :create_default_configuration
    after_update :update_related_schedules, if: :saved_change_to_status?

    def to_param
      slug
    end

    def display_name
      name
    end

    private

    def generate_slug
      base_slug = name.downcase.gsub(/[^a-z0-9\s]/, "").gsub(/\s+/, "-").strip
      self.slug = ensure_unique_slug(base_slug)
    end

    def ensure_unique_slug(base_slug)
      return base_slug if account.nil?

      slug_candidate = base_slug
      counter = 1

      while account.ai_workflows.where(slug: slug_candidate).where.not(id: id).exists?
        slug_candidate = "#{base_slug}-#{counter}"
        counter += 1
      end

      slug_candidate
    end

    def update_version_if_changed
      if configuration_changed? && persisted?
        self.version = increment_version(version)
      end
    end

    def create_default_configuration
      return if configuration.present?

      default_config = {
        "execution_mode" => "sequential",
        "timeout_seconds" => 3600,
        "max_parallel_nodes" => 5,
        "auto_retry" => false,
        "error_handling" => "stop",
        "notifications" => {
          "on_completion" => false,
          "on_error" => true
        },
        # Loop prevention settings - protect against endless loops
        "loop_prevention" => {
          # Maximum times any single node can be executed in one workflow run
          # Prevents feedback loops that revisit nodes indefinitely
          "max_node_visits" => 10,
          # Maximum consecutive validation/quality check failures before aborting
          # Prevents retry loops where validation never passes
          "max_validation_failures" => 5,
          # Maximum depth for nested sub-workflow calls
          # Prevents workflow A -> B -> A recursive loops
          "max_sub_workflow_depth" => 5,
          # Maximum times a node can be requeued waiting for prerequisites
          # Prevents deadlock scenarios
          "max_requeues_per_node" => 100,
          # Maximum total node executions across entire workflow run
          # Ultimate safeguard against runaway workflows
          "max_total_node_executions" => 1000,
          # Whether to abort or warn when limits are approached (80% threshold)
          "warn_on_approach" => true
        }
      }

      update_column(:configuration, default_config)
    end

    def update_related_schedules
      if paused? || archived?
        workflow_schedules.where(is_active: true).update_all(
          is_active: false,
          status: "disabled"
        )
      end
    end

    def only_one_active_version_per_workflow
      return unless is_active?
      return unless account_id && name

      existing_active = self.class.where(
        account_id: account_id,
        name: name,
        is_active: true
      ).where.not(id: id).exists?

      if existing_active
        errors.add(:is_active, "only one version of '#{name}' can be active at a time")
      end
    end

    def validate_workflow_structure
      # Skip validation during bulk node updates - wait for explicit validation
      return if @bulk_updating_nodes

      return unless workflow_nodes.loaded? || workflow_nodes.any?

      # Validate at least one start node
      if start_nodes.empty?
        errors.add(:base, "Workflow must have at least one node marked as a start node")
      end

      errors.add(:base, "Workflow contains circular dependencies") if has_circular_dependencies?
    end

    def validate_template_requirements
      return unless is_template?

      errors.add(:template_category, "must be present for templates") if template_category.blank?
      errors.add(:description, "must be present for templates") if description.blank?
    end

    def validate_configuration_format
      return if configuration.blank?

      unless configuration.is_a?(Hash)
        errors.add(:configuration, "must be a hash")
        return
      end

      # Validate execution_mode if present
      if configuration["execution_mode"].present?
        valid_modes = %w[sequential parallel conditional batch]
        unless valid_modes.include?(configuration["execution_mode"])
          errors.add(:configuration, "invalid execution_mode")
        end
      end

      # Validate max_execution_time if present
      if configuration["max_execution_time"].present?
        max_time = configuration["max_execution_time"].to_i
        if max_time <= 0
          errors.add(:configuration, "max_execution_time must be positive")
        end
      end
    end
  end
end
