# frozen_string_literal: true

module Ai
  class RalphIteration < ApplicationRecord
    # ==================== Concerns ====================
    include Auditable

    # ==================== Constants ====================
    STATUSES = %w[pending running completed failed skipped].freeze

    # ==================== Associations ====================
    belongs_to :ralph_loop, class_name: "Ai::RalphLoop"
    belongs_to :ralph_task, class_name: "Ai::RalphTask", optional: true

    # ==================== Validations ====================
    validates :iteration_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :iteration_number, uniqueness: { scope: :ralph_loop_id }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :tokens_input, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    validates :tokens_output, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

    # ==================== Scopes ====================
    scope :pending, -> { where(status: "pending") }
    scope :running, -> { where(status: "running") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :skipped, -> { where(status: "skipped") }
    scope :successful, -> { where(status: "completed", checks_passed: true) }
    scope :with_commits, -> { where.not(git_commit_sha: nil) }
    scope :by_iteration, -> { order(iteration_number: :asc) }
    scope :recent, -> { order(iteration_number: :desc) }

    # ==================== Callbacks ====================
    before_save :calculate_duration, if: -> { completed_at_changed? && completed_at.present? }
    after_save :update_loop_progress, if: :saved_change_to_status?

    # ==================== State Machine Methods ====================

    def start!
      raise InvalidTransitionError, "Cannot start iteration in #{status} status" unless can_start?

      update!(
        status: "running",
        started_at: Time.current
      )
    end

    def complete!(output:, checks_passed: nil, commit_sha: nil, learning: nil)
      raise InvalidTransitionError, "Cannot complete iteration in #{status} status" unless can_complete?

      attrs = {
        status: "completed",
        completed_at: Time.current,
        ai_output: output,
        checks_passed: checks_passed,
        git_commit_sha: commit_sha,
        learning_extracted: learning
      }

      update!(attrs)

      # Add learning to loop if extracted
      if learning.present?
        ralph_loop.add_learning(learning, context: { iteration: iteration_number, task_key: ralph_task&.task_key })
      end
    end

    def fail!(error_message:, error_code: nil, error_details: {})
      raise InvalidTransitionError, "Cannot fail iteration in #{status} status" unless can_fail?

      update!(
        status: "failed",
        completed_at: Time.current,
        error_message: error_message,
        error_code: error_code,
        error_details: error_details
      )
    end

    def skip!(reason: nil)
      raise InvalidTransitionError, "Cannot skip iteration in #{status} status" unless can_skip?

      update!(
        status: "skipped",
        completed_at: Time.current,
        error_message: reason
      )
    end

    # ==================== State Checks ====================

    def can_start?
      status == "pending"
    end

    def can_complete?
      status == "running"
    end

    def can_fail?
      status == "running"
    end

    def can_skip?
      status == "pending"
    end

    def terminal?
      status.in?(%w[completed failed skipped])
    end

    # ==================== Token & Cost Management ====================

    def total_tokens
      (tokens_input || 0) + (tokens_output || 0)
    end

    def record_token_usage(input:, output:, cost: nil)
      update!(
        tokens_input: input,
        tokens_output: output,
        cost: cost
      )
    end

    # ==================== Summary Methods ====================

    def iteration_summary
      {
        id: id,
        iteration_number: iteration_number,
        status: status,
        task_key: ralph_task&.task_key,
        checks_passed: checks_passed,
        git_commit_sha: git_commit_sha,
        duration_ms: duration_ms,
        started_at: started_at&.iso8601,
        completed_at: completed_at&.iso8601,
        total_tokens: total_tokens,
        cost: cost&.to_f
      }
    end

    def iteration_details
      iteration_summary.merge(
        ai_prompt: ai_prompt,
        ai_output: ai_output,
        ai_response_metadata: ai_response_metadata,
        check_results: check_results,
        error_message: error_message,
        error_code: error_code,
        error_details: error_details,
        learning_extracted: learning_extracted,
        git_branch: git_branch,
        created_at: created_at.iso8601
      )
    end

    # ==================== Custom Errors ====================

    class InvalidTransitionError < StandardError; end

    private

    def calculate_duration
      return unless started_at.present? && completed_at.present?

      self.duration_ms = ((completed_at - started_at) * 1000).to_i
    end

    def update_loop_progress
      return unless ralph_loop.present?

      ralph_loop.update_columns(
        current_iteration: [ ralph_loop.current_iteration, iteration_number ].max,
        updated_at: Time.current
      )
    end
  end
end
