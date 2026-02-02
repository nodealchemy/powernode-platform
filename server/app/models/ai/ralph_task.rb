# frozen_string_literal: true

module Ai
  class RalphTask < ApplicationRecord
    # ==================== Concerns ====================
    include Auditable

    # ==================== Constants ====================
    STATUSES = %w[pending in_progress passed failed blocked skipped].freeze
    TERMINAL_STATUSES = %w[passed failed skipped].freeze

    # Execution type enumeration - determines which type of executor handles this task
    EXECUTION_TYPES = %w[agent workflow pipeline a2a_task container human community].freeze

    # Capability match strategies for executor selection
    CAPABILITY_STRATEGIES = %w[all any weighted].freeze

    # ==================== Associations ====================
    belongs_to :ralph_loop, class_name: "Ai::RalphLoop"

    has_many :ralph_iterations, class_name: "Ai::RalphIteration",
             foreign_key: "ralph_task_id", dependent: :nullify

    # Polymorphic executor association - links to the actual executor instance
    belongs_to :executor, polymorphic: true, optional: true

    # Tracks the last executor used (for retry/fallback scenarios)
    belongs_to :last_executor, polymorphic: true, optional: true

    # ==================== Validations ====================
    validates :task_key, presence: true
    validates :task_key, uniqueness: { scope: :ralph_loop_id }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :priority, numericality: { only_integer: true }, allow_nil: true
    validates :execution_type, inclusion: { in: EXECUTION_TYPES }
    validates :capability_match_strategy, inclusion: { in: CAPABILITY_STRATEGIES }

    # ==================== Scopes ====================
    scope :pending, -> { where(status: "pending") }
    scope :in_progress, -> { where(status: "in_progress") }
    scope :passed, -> { where(status: "passed") }
    scope :failed, -> { where(status: "failed") }
    scope :blocked, -> { where(status: "blocked") }
    scope :skipped, -> { where(status: "skipped") }
    scope :terminal, -> { where(status: TERMINAL_STATUSES) }
    scope :active, -> { where(status: %w[pending in_progress blocked]) }
    scope :by_priority, -> { order(priority: :desc, position: :asc) }
    scope :ordered, -> { order(position: :asc, priority: :desc) }

    # ==================== Callbacks ====================
    before_validation :set_position, on: :create

    # ==================== State Machine Methods ====================

    def start!
      raise InvalidTransitionError, "Cannot start task in #{status} status" unless can_start?

      update!(status: "in_progress")
    end

    def pass!(iteration_number: nil)
      raise InvalidTransitionError, "Cannot pass task in #{status} status" unless can_pass?

      update!(
        status: "passed",
        iteration_completed_at: Time.current,
        completed_in_iteration: iteration_number,
        error_message: nil,
        error_code: nil
      )

      unblock_dependent_tasks
    end

    def fail!(error_message: nil, error_code: nil)
      raise InvalidTransitionError, "Cannot fail task in #{status} status" unless can_fail?

      update!(
        status: "failed",
        iteration_completed_at: Time.current,
        error_message: error_message,
        error_code: error_code
      )
    end

    def block!(reason: nil)
      raise InvalidTransitionError, "Cannot block task in #{status} status" unless can_block?

      update!(
        status: "blocked",
        error_message: reason
      )
    end

    def skip!(reason: nil)
      raise InvalidTransitionError, "Cannot skip task in #{status} status" unless can_skip?

      update!(
        status: "skipped",
        iteration_completed_at: Time.current,
        error_message: reason
      )

      unblock_dependent_tasks
    end

    def reset!
      update!(
        status: "pending",
        iteration_completed_at: nil,
        completed_in_iteration: nil,
        error_message: nil,
        error_code: nil
      )
    end

    # ==================== State Checks ====================

    def can_start?
      status == "pending" && dependencies_satisfied?
    end

    def can_pass?
      status == "in_progress"
    end

    def can_fail?
      status == "in_progress"
    end

    def can_block?
      status.in?(%w[pending in_progress])
    end

    def can_skip?
      status.in?(%w[pending blocked])
    end

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def in_progress?
      status == "in_progress"
    end

    # ==================== Dependency Management ====================

    def dependencies_satisfied?
      return true if dependencies.blank?

      dependency_tasks = ralph_loop.ralph_tasks.where(task_key: dependencies)
      dependency_tasks.all? { |t| t.status.in?(%w[passed skipped]) }
    end

    def blocking_dependencies
      return [] if dependencies.blank?

      ralph_loop.ralph_tasks
                .where(task_key: dependencies)
                .where.not(status: %w[passed skipped])
                .pluck(:task_key)
    end

    def dependent_tasks
      ralph_loop.ralph_tasks.select do |task|
        task.dependencies&.include?(task_key)
      end
    end

    def unblock_dependent_tasks
      dependent_tasks.each do |task|
        next unless task.status == "blocked" && task.dependencies_satisfied?

        task.update!(status: "pending")
      end
    end

    # ==================== Executor Selection ====================

    # Find matching executor based on execution_type and required_capabilities
    def find_matching_executor
      case execution_type
      when "agent"
        find_matching_agent
      when "workflow"
        find_matching_workflow
      when "a2a_task"
        find_via_a2a_discovery
      when "community"
        find_community_agent
      when "pipeline"
        find_matching_pipeline
      when "container"
        find_matching_container
      when "human"
        find_human_reviewer
      else
        executor # Use pre-assigned executor
      end
    end

    # Increment execution attempts when starting execution
    def record_execution_attempt!(new_executor = nil)
      attrs = { execution_attempts: execution_attempts + 1 }
      if new_executor
        attrs[:last_executor_type] = new_executor.class.name
        attrs[:last_executor_id] = new_executor.id
      end
      update!(attrs)
    end

    # Check if fallback executor is configured
    def has_fallback?
      delegation_config["fallback_executor_type"].present?
    end

    # Get fallback executor configuration
    def fallback_config
      {
        executor_type: delegation_config["fallback_executor_type"],
        executor_id: delegation_config["fallback_executor_id"]
      }
    end

    # Check if delegation to specific agent is allowed
    def delegation_allowed_for?(agent_id)
      allowed = delegation_config["allowed_agents"]
      return true if allowed.blank? # No restrictions
      allowed.include?(agent_id.to_s)
    end

    # Get timeout for task execution
    def execution_timeout
      delegation_config["timeout_seconds"] || 3600
    end

    # ==================== Summary Methods ====================

    def task_summary
      {
        id: id,
        task_key: task_key,
        description: description&.truncate(200),
        status: status,
        priority: priority,
        position: position,
        dependencies: dependencies,
        dependencies_satisfied: dependencies_satisfied?,
        completed_in_iteration: completed_in_iteration,
        iteration_completed_at: iteration_completed_at&.iso8601,
        execution_type: execution_type,
        executor_type: executor_type,
        executor_id: executor_id,
        execution_attempts: execution_attempts
      }
    end

    def task_details
      task_summary.merge(
        description: description,
        acceptance_criteria: acceptance_criteria,
        error_message: error_message,
        error_code: error_code,
        metadata: metadata,
        blocking_dependencies: blocking_dependencies,
        iterations_count: ralph_iterations.count,
        required_capabilities: required_capabilities,
        capability_match_strategy: capability_match_strategy,
        delegation_config: delegation_config,
        created_at: created_at.iso8601,
        updated_at: updated_at.iso8601
      )
    end

    # ==================== Custom Errors ====================

    class InvalidTransitionError < StandardError; end

    private

    def set_position
      return if position.present?

      max_position = ralph_loop.ralph_tasks.maximum(:position) || 0
      self.position = max_position + 1
    end

    # ==================== Executor Finders ====================

    def find_matching_agent
      scope = ralph_loop.account.ai_agents.where(status: "active")

      case capability_match_strategy
      when "all"
        # Agent must have ALL required capabilities
        required_capabilities.each do |cap|
          scope = scope.where("capabilities @> ?", [ cap ].to_json)
        end
      when "any"
        # Agent must have ANY required capability
        return scope.first if required_capabilities.blank?
        scope = scope.where("capabilities ?| array[:caps]", caps: required_capabilities)
      when "weighted"
        # Score agents by capability overlap and return best match
        return score_agents_by_capabilities(scope).first
      end

      scope.first
    end

    def find_matching_workflow
      scope = ralph_loop.account.ai_workflows.where(status: "active")

      # Match workflows by tags/categories that align with required capabilities
      return scope.first if required_capabilities.blank?

      scope.where("tags && ARRAY[?]::varchar[]", required_capabilities).first || scope.first
    end

    def find_matching_pipeline
      scope = ralph_loop.account.devops_pipelines

      # Match pipelines by type or tags
      return scope.first if required_capabilities.blank?

      scope.where("tags && ARRAY[?]::varchar[]", required_capabilities).first || scope.first
    end

    def find_matching_container
      # Find container template that matches capabilities
      scope = Mcp::ContainerTemplate.where(status: "active")

      return scope.first if required_capabilities.blank?

      scope.where("tags && ARRAY[?]::varchar[]", required_capabilities).first || scope.first
    end

    def find_via_a2a_discovery
      # Use A2A agent discovery to find matching agent
      agent_cards = Ai::AgentCard.joins(:agent)
                                  .where(ai_agents: { account_id: ralph_loop.account_id, status: "active" })

      return agent_cards.first&.agent if required_capabilities.blank?

      # Find agent card with matching skills
      matching_card = agent_cards.find do |card|
        skills = card.capabilities&.dig("skills") || []
        case capability_match_strategy
        when "all"
          (required_capabilities - skills).empty?
        when "any"
          (required_capabilities & skills).any?
        else
          true
        end
      end

      matching_card&.agent
    end

    def find_community_agent
      scope = CommunityAgent.where(status: "active", visibility: %w[public unlisted])

      return scope.order(reputation_score: :desc).first if required_capabilities.blank?

      # Match community agents by their skills
      scope.where("capabilities->'skills' ?| array[:caps]", caps: required_capabilities)
           .order(reputation_score: :desc)
           .first
    end

    def find_human_reviewer
      # Find user with appropriate permissions for review
      # Default to account owner or first admin
      ralph_loop.account.users.joins(:roles)
                .where(roles: { name: %w[owner admin] })
                .first
    end

    def score_agents_by_capabilities(scope)
      return scope if required_capabilities.blank?

      # Order by number of matching capabilities
      scope.select("ai_agents.*, (
        SELECT COUNT(*)
        FROM jsonb_array_elements_text(capabilities) AS cap
        WHERE cap = ANY(ARRAY[#{required_capabilities.map { |c| "'#{c}'" }.join(',')}]::text[])
      ) AS capability_score")
           .order("capability_score DESC")
    end
  end
end
