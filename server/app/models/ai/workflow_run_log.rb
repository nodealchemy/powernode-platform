# frozen_string_literal: true

module Ai
  class WorkflowRunLog < ApplicationRecord
    # Associations
    belongs_to :workflow_run, class_name: "Ai::WorkflowRun", foreign_key: "ai_workflow_run_id"
    belongs_to :node_execution, class_name: "Ai::WorkflowNodeExecution",
               foreign_key: "ai_workflow_node_execution_id", optional: true

    # Validations
    validates :log_level, presence: true, inclusion: {
      in: %w[debug info warn error fatal],
      message: "must be a valid log level"
    }
    validates :event_type, presence: true, inclusion: {
      in: %w[
        workflow_started workflow_completed workflow_failed workflow_cancelled
        node_started node_completed node_failed node_cancelled node_skipped
        variable_updated condition_evaluated error_handled retry_attempted
        approval_requested approval_granted approval_denied
        webhook_sent api_called data_transformed
        cost_added timeout_detected
        ai_agent_execution_queued api_call_queued webhook_queued
        condition_evaluation_queued loop_execution_queued transform_execution_queued
        sub_workflow_queued merge_execution_queued split_execution_queued
        delay_scheduled node_retry_scheduled
        webhook_started webhook_sending webhook_response_received webhook_completed webhook_failed
        condition_evaluation_started condition_evaluation_completed condition_evaluation_error
        node_execution_error delay_execution_started delay_execution_completed
        approval_notification_sent merge_execution_started merge_execution_completed
        split_execution_started split_execution_completed api_call_started
        api_request_sent api_response_received api_call_completed api_call_failed
        human_approval_started human_approval_initiated approval_request_created
        approval_email_sent approval_in_app_sent
      ],
      message: "must be a valid event type"
    }
    validates :message, presence: true
    validates :logged_at, presence: true

    # JSON columns
    attribute :context_data, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }

    # Scopes
    scope :by_level, ->(level) { where(log_level: level) }
    scope :debug, -> { where(log_level: "debug") }
    scope :info, -> { where(log_level: "info") }
    scope :warnings, -> { where(log_level: "warn") }
    scope :errors, -> { where(log_level: "error") }
    scope :fatal, -> { where(log_level: "fatal") }
    scope :by_event_type, ->(type) { where(event_type: type) }
    scope :for_node, ->(node_id) { where(node_id: node_id) }
    scope :recent, -> { order(logged_at: :desc) }
    scope :in_time_range, ->(start_time, end_time) { where(logged_at: start_time..end_time) }
    scope :with_errors, -> { where(log_level: %w[error fatal]) }

    # Callbacks
    before_validation :set_logged_at, if: -> { logged_at.blank? }

    def debug?
      log_level == "debug"
    end

    def info?
      log_level == "info"
    end

    def warning?
      log_level == "warn"
    end

    def error?
      log_level == "error"
    end

    def fatal?
      log_level == "fatal"
    end

    def has_error?
      %w[error fatal].include?(log_level)
    end

    def workflow_event?
      event_type.start_with?("workflow_")
    end

    def node_event?
      event_type.start_with?("node_")
    end

    def system_event?
      %w[cost_added timeout_detected variable_updated].include?(event_type)
    end

    def user_action_event?
      %w[approval_granted approval_denied].include?(event_type)
    end

    def context_value(key)
      context_data[key.to_s] || context_data[key.to_sym]
    end

    def metadata_value(key)
      metadata[key.to_s] || metadata[key.to_sym]
    end

    def formatted_message
      timestamp = logged_at.strftime("%Y-%m-%d %H:%M:%S")
      level_badge = log_level.upcase.ljust(5)
      node_info = node_id ? "[#{node_id}] " : ""

      "[#{timestamp}] #{level_badge} #{node_info}#{message}"
    end

    def summary
      {
        id: id,
        level: log_level,
        event_type: event_type,
        message: message,
        node_id: node_id,
        source: source,
        logged_at: logged_at,
        has_context: context_data.present?,
        has_metadata: metadata.present?
      }
    end

    def self.search_by_message(query)
      where("message ILIKE ?", "%#{query}%")
    end

    def self.for_time_period(period)
      case period.to_s
      when "hour"
        where("logged_at >= ?", 1.hour.ago)
      when "day"
        where("logged_at >= ?", 1.day.ago)
      when "week"
        where("logged_at >= ?", 1.week.ago)
      when "month"
        where("logged_at >= ?", 1.month.ago)
      else
        where("logged_at >= ?", 1.day.ago)
      end
    end

    private

    def set_logged_at
      self.logged_at = Time.current
    end
  end
end
