# frozen_string_literal: true

module Ai
  class WorkflowRun < ApplicationRecord
    # Concerns
    include Ai::WorkflowRun::StateManagement
    include Ai::WorkflowRun::ProgressTracking
    include Ai::WorkflowRun::VariableManagement
    include Ai::WorkflowRun::CostTracking
    include Ai::WorkflowRun::RunLogging
    include Ai::WorkflowRun::Broadcasting

    # Associations
    belongs_to :workflow, class_name: "Ai::Workflow", foreign_key: "ai_workflow_id"
    belongs_to :account
    belongs_to :triggered_by_user, class_name: "User", optional: true
    belongs_to :trigger, class_name: "Ai::WorkflowTrigger", foreign_key: "ai_workflow_trigger_id", optional: true

    has_many :node_executions, class_name: "Ai::WorkflowNodeExecution",
             foreign_key: "ai_workflow_run_id", dependent: :destroy

    # Backward compatibility alias for MCP services
    alias_method :workflow_node_executions, :node_executions

    # Backward compatibility method for workflow_id
    def workflow_id
      ai_workflow_id
    end
    has_many :run_logs, class_name: "Ai::WorkflowRunLog",
             foreign_key: "ai_workflow_run_id", dependent: :destroy
    has_many :checkpoints, class_name: "Ai::WorkflowCheckpoint",
             foreign_key: "ai_workflow_run_id", dependent: :destroy
    has_many :agent_messages, class_name: "Ai::AgentMessage",
             foreign_key: "ai_workflow_run_id", dependent: :destroy
    has_many :shared_context_pools, class_name: "Ai::SharedContextPool",
             foreign_key: "ai_workflow_run_id", dependent: :destroy
    has_many :compensations, class_name: "Ai::WorkflowCompensation",
             foreign_key: "ai_workflow_run_id", dependent: :destroy

    # Validations
    validates :run_id, presence: true, uniqueness: true
    validates :status, presence: true, inclusion: {
      in: %w[initializing running completed failed cancelled waiting_approval],
      message: "must be a valid run status"
    }
    validates :trigger_type, presence: true, inclusion: {
      in: %w[manual webhook schedule event api_call],
      message: "must be a valid trigger type"
    }
    validates :total_nodes, numericality: { greater_than_or_equal_to: 0 }
    validates :completed_nodes, numericality: { greater_than_or_equal_to: 0 }
    validates :failed_nodes, numericality: { greater_than_or_equal_to: 0 }
    validates :total_cost, numericality: { greater_than_or_equal_to: 0 }
    validate :validate_node_progress_consistency
    validate :validate_execution_times

    # JSON columns
    attribute :input_variables, :json, default: -> { {} }
    attribute :output_variables, :json, default: -> { {} }
    attribute :runtime_context, :json, default: -> { {} }
    attribute :error_details, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }

    # Scopes
    scope :active, -> { where(status: %w[initializing running waiting_approval]) }
    scope :running, -> { where(status: "running") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :finished, -> { where(status: %w[completed failed cancelled]) }
    scope :stale, -> { where(status: %w[initializing running]).where("created_at < ?", 30.minutes.ago) }
    scope :find_by_partial_id, ->(partial_id) { where("id::text LIKE ?", "%#{sanitize_sql_like(partial_id)}%") }
    scope :recent, -> { order(created_at: :desc) }
    scope :by_trigger_type, ->(type) { where(trigger_type: type) }
    scope :by_status, ->(status) { where(status: status) }
    scope :for_workflow, ->(workflow_id) { where(ai_workflow_id: workflow_id) }
    scope :for_user, ->(user_id) { where(triggered_by_user_id: user_id) }
    scope :with_cost, -> { where("total_cost > 0") }

    # Callbacks
    before_validation :generate_run_id, on: :create
    before_validation :set_initial_values, on: :create
    after_create :log_workflow_started
    after_create :schedule_timeout_check
    after_update :log_status_changes, if: :saved_change_to_status?
    after_update :calculate_duration, if: :saved_change_to_completed_at?
    after_update :copy_variables_to_output, if: -> { saved_change_to_status? && status == "completed" }

    # Accessor methods for data stored in metadata
    def trigger_context
      metadata["trigger_context"] || {}
    end

    def trigger_context=(context)
      self.metadata = (metadata || {}).merge("trigger_context" => context)
    end

    # Node execution management
    def create_node_execution(workflow_node, input_data = {})
      existing_execution = node_executions.find_by(node_id: workflow_node.node_id)

      if existing_execution
        Rails.logger.info "Node execution already exists for node #{workflow_node.node_id} in run #{run_id}, returning existing execution"
        return existing_execution
      end

      node_executions.create!(
        node: workflow_node,
        node_id: workflow_node.node_id,
        node_type: workflow_node.node_type,
        input_data: input_data,
        configuration_snapshot: workflow_node.configuration,
        execution_id: SecureRandom.uuid,
        max_retries: workflow_node.retry_count || 0,
        metadata: {
          "created_for_run" => run_id,
          "workflow_version" => workflow.version
        }
      )
    end

    def get_node_execution(node_id)
      node_executions.find_by(node_id: node_id)
    end

    def node_execution_status(node_id)
      execution = get_node_execution(node_id)
      execution&.status || "not_started"
    end

    # Run summary and analysis
    def execution_summary
      {
        run_id: run_id,
        workflow_name: workflow.name,
        status: status,
        trigger_type: trigger_type,
        progress: execution_progress,
        duration_seconds: execution_duration_seconds,
        cost: {
          total: total_cost,
          breakdown: cost_breakdown
        },
        timestamps: {
          created: created_at,
          started: started_at,
          completed: completed_at,
          cancelled: cancelled_at
        },
        node_summary: node_execution_summary,
        error_summary: error_details.present? ? error_details : nil
      }
    end

    def node_execution_summary
      executions = node_executions.includes(:node)

      {
        total: executions.count,
        by_status: executions.group(:status).count,
        by_type: executions.joins(:node).group("ai_workflow_nodes.node_type").count,
        average_duration: executions.where(status: "completed").average(:duration_ms)&.to_i || 0,
        total_cost: executions.sum(:cost)
      }
    end

    private

    def copy_variables_to_output
      if runtime_context["variables"].present? && output_variables.empty?
        update_column(:output_variables, runtime_context["variables"])
      end
    end

    def generate_run_id
      self.run_id = UUID7.generate if run_id.blank?
    end

    def set_initial_values
      return unless new_record?
      return unless workflow.present?

      self.total_nodes = workflow.workflow_nodes.count
      self.completed_nodes = 0
      self.failed_nodes = 0
      self.total_cost = 0.0

      if runtime_context.blank?
        self.runtime_context = {
          "variables" => {},
          "execution_context" => {
            "workflow_version" => workflow.version,
            "created_at" => Time.current.iso8601
          }
        }
      end
    end

    def validate_node_progress_consistency
      return unless total_nodes.present? && completed_nodes.present? && failed_nodes.present?

      if completed_nodes + failed_nodes > total_nodes
        errors.add(:base, "Sum of completed and failed nodes cannot exceed total nodes")
      end

      if completed_nodes < 0 || failed_nodes < 0
        errors.add(:base, "Node counts cannot be negative")
      end
    end

    def validate_execution_times
      if started_at.present? && completed_at.present? && completed_at < started_at
        errors.add(:completed_at, "must be after started_at")
      end

      if status == "completed" && completed_at.blank?
        errors.add(:completed_at, "can't be blank for completed runs")
      end

      if status == "failed" && completed_at.blank?
        errors.add(:completed_at, "can't be blank for failed runs")
      end

      if status == "failed" && (error_details.blank? || error_details.empty?)
        errors.add(:error_details, "can't be blank for failed runs")
      end

      if status == "cancelled" && cancelled_at.blank?
        errors.add(:cancelled_at, "can't be blank for cancelled runs")
      end
    end

    def log_workflow_started
      log_info("workflow_started", "Workflow run started: #{workflow.name}", {
        "workflow_id" => ai_workflow_id,
        "trigger_type" => trigger_type,
        "input_variables" => input_variables.keys
      })
    end

    def log_status_changes
      old_status = saved_change_to_status[0]
      new_status = saved_change_to_status[1]

      event_type = case new_status
      when "completed"
        "workflow_completed"
      when "failed"
        "workflow_failed"
      when "cancelled"
        "workflow_cancelled"
      when "running"
        "workflow_started"
      else
        "workflow_started"
      end

      log_info(event_type, "Workflow status changed from #{old_status} to #{new_status}", {
        "old_status" => old_status,
        "new_status" => new_status,
        "progress_percentage" => progress_percentage
      })
    end

    def calculate_duration
      return unless started_at && completed_at

      duration_seconds = completed_at - started_at
      calculated_duration_ms = [ duration_seconds * 1000, 0 ].max.to_i

      if duration_ms != calculated_duration_ms
        update_column(:duration_ms, calculated_duration_ms)
      end
    end

    def schedule_timeout_check
      return unless Rails.env.development? || Rails.env.production?

      begin
        WorkerJobService.new.make_worker_request("POST", "/api/v1/jobs", {
          "job_class" => "WorkflowTimeoutJob",
          "args" => [ run_id ],
          "queue" => "maintenance",
          "at" => 30.minutes.from_now.to_i
        })
      rescue StandardError => e
        Rails.logger.warn "Failed to schedule timeout job for workflow run #{run_id}: #{e.message}"
      end
    end

    def check_and_handle_timeout
      return unless active?

      if initializing? && created_at < 15.minutes.ago
        cancel_execution!("Automatic timeout - stuck in initializing state for #{((Time.current - created_at) / 60).round(1)} minutes")
        Rails.logger.warn "Auto-cancelled stuck initializing workflow: #{run_id}"
        return true
      end

      if running? && started_at && started_at < 45.minutes.ago && completed_nodes <= 1
        cancel_execution!("Automatic timeout - no progress for #{((Time.current - started_at) / 60).round(1)} minutes")
        Rails.logger.warn "Auto-cancelled stuck running workflow: #{run_id}"
        return true
      end

      false
    end

    def has_timeout_job?
      return false unless defined?(Sidekiq)

      begin
        scheduled_jobs = Sidekiq::ScheduledSet.new
        scheduled_jobs.any? { |job| job.klass == "WorkflowTimeoutJob" && job.args.include?(id) }
      rescue StandardError => e
        Rails.logger.error "Failed to check timeout job status: #{e.message}"
        false
      end
    end
  end
end
