# frozen_string_literal: true

module Ai
  class AgentExecution < ApplicationRecord
    # Concerns
    include Auditable

    # Associations
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id"
    belongs_to :account
    belongs_to :user
    belongs_to :provider, class_name: "Ai::Provider", foreign_key: "ai_provider_id"
    belongs_to :parent_execution, class_name: "Ai::AgentExecution", foreign_key: "parent_execution_id", optional: true
    has_many :child_executions, class_name: "Ai::AgentExecution", foreign_key: "parent_execution_id", dependent: :nullify

    # Validations
    validates :execution_id, presence: true, uniqueness: true
    validates :status, inclusion: { in: %w[pending running completed failed cancelled] }
    validates :input_parameters, presence: true
    validates :duration_ms, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    validates :tokens_used, numericality: { greater_than_or_equal_to: 0 }
    validates :cost_usd, numericality: { greater_than_or_equal_to: 0 }
    validates :webhook_attempts, numericality: { greater_than_or_equal_to: 0 }
    validate :completed_execution_has_duration
    validate :failed_execution_has_error

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :running, -> { where(status: "running") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :finished, -> { where(status: %w[completed failed cancelled]) }
    scope :successful, -> { where(status: "completed") }
    scope :recent, -> { order(created_at: :desc) }
    scope :for_agent, ->(agent) { where(ai_agent_id: agent.is_a?(Ai::Agent) ? agent.id : agent) }
    scope :for_user, ->(user) { where(user: user) }
    scope :with_webhooks, -> { where.not(webhook_url: nil) }
    scope :webhook_pending, -> { where(webhook_status: [ "pending", "failed" ]) }
    scope :today, -> { where(created_at: Date.current.beginning_of_day..Date.current.end_of_day) }
    scope :this_week, -> { where(created_at: 1.week.ago..Time.current) }
    scope :this_month, -> { where(created_at: 1.month.ago..Time.current) }

    # Callbacks
    before_validation :set_execution_id, on: :create
    after_update :trigger_webhook, if: :saved_change_to_status?
    after_update :propagate_cost_to_budget, if: -> { saved_change_to_cost_usd? && cost_usd.present? && cost_usd > 0 }
    after_update :trigger_trust_evaluation, if: -> { saved_change_to_status? && %w[completed failed].include?(status) }

    # Methods
    def pending?
      status == "pending"
    end

    def running?
      status == "running"
    end

    def completed?
      status == "completed"
    end

    def failed?
      status == "failed"
    end

    def cancelled?
      status == "cancelled"
    end

    def finished?
      %w[completed failed cancelled].include?(status)
    end

    def successful?
      status == "completed"
    end

    def start_execution!
      raise ArgumentError, "Execution already started" unless pending?

      update!(
        status: "running",
        started_at: Time.current
      )
    end

    def complete_execution!(output_data, metrics = {})
      raise ArgumentError, "Execution not running" unless running?

      now = Time.current
      duration = started_at ? ((now - started_at) * 1000).round : nil

      update!(
        status: "completed",
        output_data: output_data,
        completed_at: now,
        duration_ms: duration,
        performance_metrics: metrics
      )
    end

    def fail_execution!(error_message, error_details = {})
      raise ArgumentError, "Execution already finished" if finished?

      update!(
        status: "failed",
        error_message: error_message&.truncate(1000),
        error_details: error_details,
        completed_at: Time.current,
        duration_ms: started_at ? ((Time.current - started_at) * 1000).round : nil
      )
    end

    def cancel_execution!(reason = "Cancelled by user")
      raise ArgumentError, "Cannot cancel finished execution" if finished?

      update!(
        status: "cancelled",
        error_message: reason,
        completed_at: Time.current,
        duration_ms: started_at ? ((Time.current - started_at) * 1000).round : nil
      )
    end

    def record_token_usage!(tokens, cost = nil)
      update!(
        tokens_used: tokens,
        cost_usd: cost || calculate_cost(tokens)
      )
    end

    def execution_time
      return nil unless started_at

      end_time = completed_at || Time.current
      ((end_time - started_at) * 1000).round
    end

    def execution_summary
      {
        id: execution_id,
        status: status,
        agent: agent.name,
        provider: provider.name,
        duration_ms: duration_ms,
        tokens_used: tokens_used,
        cost_usd: cost_usd,
        created_at: created_at,
        completed_at: completed_at,
        has_output: output_data.present?,
        has_error: error_message.present?
      }
    end

    def child_execution_summary
      child_executions.map(&:execution_summary)
    end

    def total_cost_with_children
      cost_usd + child_executions.sum(:cost_usd)
    end

    def total_tokens_with_children
      tokens_used + child_executions.sum(:tokens_used)
    end

    def webhook_delivery_status
      return "no_webhook" unless webhook_url.present?
      return "pending" if webhook_status.blank? || webhook_status == "pending"
      return "delivered" if webhook_status == "success"
      return "failed" if webhook_attempts >= 3

      "retrying"
    end

    def retry_webhook!
      return false unless webhook_url.present?
      return false if webhook_attempts >= 3

      AiWebhookDeliveryJob.perform_later(id)
      true
    end

    def to_param
      execution_id
    end

    private

    def set_execution_id
      self.execution_id ||= SecureRandom.uuid
    end

    def completed_execution_has_duration
      return unless completed? && started_at.present? && duration_ms.blank?

      errors.add(:duration_ms, "must be present for completed executions")
    end

    def failed_execution_has_error
      return unless failed? && error_message.blank?

      errors.add(:error_message, "must be present for failed executions")
    end

    def calculate_cost(tokens)
      pricing = provider.configuration&.dig("pricing") || {}
      input_rate = pricing["input_per_token"]&.to_f
      output_rate = pricing["output_per_token"]&.to_f

      if input_rate || output_rate
        input_tokens = token_usage&.dig("input")&.to_i || tokens
        output_tokens = token_usage&.dig("output")&.to_i || 0
        (input_tokens * (input_rate || 0)) + (output_tokens * (output_rate || 0))
      else
        cost_per_1k = pricing["cost_per_1k_tokens"]&.to_f || 0
        (tokens / 1000.0) * cost_per_1k
      end
    end

    def trigger_webhook
      return unless webhook_url.present?
      return unless finished?

      AiWebhookDeliveryJob.perform_later(id)
    end

    def propagate_cost_to_budget
      budget = Ai::AgentBudget.where(agent_id: ai_agent_id, account_id: account_id).active.first
      return unless budget

      cost_cents = (cost_usd * 100).round
      budget.debit!(cost_cents, execution: self, metadata: {
        provider: provider&.name,
        model: agent&.model,
        tokens: tokens_used
      })
    rescue StandardError => e
      Rails.logger.error("[AgentExecution] Cost propagation failed for execution #{id}: #{e.message}")
    end

    def trigger_trust_evaluation
      Ai::Autonomy::TrustEngineService.new(account: account).evaluate(agent: agent, execution: self)
    rescue StandardError => e
      Rails.logger.error("[AgentExecution] Trust evaluation failed for execution #{id}: #{e.message}")
    end
  end
end
