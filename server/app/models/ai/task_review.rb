# frozen_string_literal: true

module Ai
  class TaskReview < ApplicationRecord
    self.table_name = "ai_task_reviews"

    # ==========================================
    # Constants
    # ==========================================
    STATUSES = %w[pending in_progress approved rejected revision_requested].freeze
    REVIEW_MODES = %w[blocking shadow].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :team_task, class_name: "Ai::TeamTask"
    belongs_to :reviewer_role, class_name: "Ai::TeamRole", optional: true
    belongs_to :reviewer_agent, class_name: "Ai::Agent", optional: true

    # ==========================================
    # Validations
    # ==========================================
    validates :review_id, presence: true, uniqueness: true
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :review_mode, presence: true, inclusion: { in: REVIEW_MODES }

    # ==========================================
    # Scopes
    # ==========================================
    scope :pending, -> { where(status: "pending") }
    scope :in_progress, -> { where(status: "in_progress") }
    scope :approved, -> { where(status: "approved") }
    scope :rejected, -> { where(status: "rejected") }
    scope :revision_requested, -> { where(status: "revision_requested") }
    scope :blocking, -> { where(review_mode: "blocking") }
    scope :shadow, -> { where(review_mode: "shadow") }
    scope :for_task, ->(task_id) { where(team_task_id: task_id) }

    # ==========================================
    # Callbacks
    # ==========================================
    before_validation :generate_review_id, on: :create

    # ==========================================
    # Status Transitions
    # ==========================================

    def start!
      raise "Cannot start review in '#{status}' state" unless status == "pending"

      update!(status: "in_progress")
    end

    def approve!(notes: nil)
      raise "Cannot approve review in '#{status}' state" unless status == "in_progress"

      update!(
        status: "approved",
        approval_notes: notes,
        review_duration_ms: calculate_duration
      )
    end

    def reject!(reason:)
      raise "Cannot reject review in '#{status}' state" unless status.in?(%w[pending in_progress])

      update!(
        status: "rejected",
        rejection_reason: reason,
        review_duration_ms: calculate_duration
      )
    end

    def request_revision!(reason:)
      raise "Cannot request revision in '#{status}' state" unless status == "in_progress"

      update!(
        status: "revision_requested",
        rejection_reason: reason,
        revision_count: revision_count + 1,
        review_duration_ms: calculate_duration
      )
    end

    # ==========================================
    # Finding Management
    # ==========================================

    def add_finding(category:, severity:, description:, suggestion: nil)
      self.findings ||= []
      self.findings << {
        "category" => category,
        "severity" => severity,
        "description" => description,
        "suggestion" => suggestion
      }
      save!
    end

    # Static completeness scanning
    def self.check_completeness(output)
      output_text = output.to_json
      has_todos = output_text.match?(/TODO|FIXME|HACK|XXX/i)
      has_stubs = output_text.match?(/stub|placeholder|not.?implemented/i)
      has_empty = output_text.match?(/pass\b|\.\.\.|raise NotImplementedError/)

      issue_count = [has_todos, has_stubs, has_empty].count(true)
      completeness_score = 1.0 - (issue_count * 0.25)

      {
        has_todos: has_todos,
        has_stubs: has_stubs,
        has_empty_implementations: has_empty,
        completeness_score: [completeness_score, 0.0].max
      }
    end

    private

    def generate_review_id
      return if review_id.present?

      self.review_id = "rev_#{SecureRandom.hex(12)}"
    end

    def calculate_duration
      return nil unless created_at

      ((Time.current - created_at) * 1000).to_i
    end
  end
end
