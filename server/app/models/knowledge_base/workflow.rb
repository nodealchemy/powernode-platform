# frozen_string_literal: true

module KnowledgeBase
  class Workflow < ApplicationRecord
    # Authentication

    # Concerns
    include Auditable

    # Associations
    belongs_to :article, class_name: "KnowledgeBase::Article"
    belongs_to :user

    # Validations
    validates :workflow_type, inclusion: { in: %w[review approval translation update] }
    validates :status, inclusion: { in: %w[pending in_progress completed cancelled] }
    validates :notes, length: { maximum: 1000 }

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :in_progress, -> { where(status: "in_progress") }
    scope :completed, -> { where(status: "completed") }
    scope :overdue, -> { where("due_date < ? AND status NOT IN (?)", Time.current, %w[completed cancelled]) }
    scope :by_type, ->(type) { where(workflow_type: type) }
    scope :assigned_to, ->(user_id) { where(user_id: user_id) }

    # Callbacks
    before_save :set_completion_date, if: -> { status_changed?(to: "completed") }

    # Methods
    def pending?
      status == "pending"
    end

    def in_progress?
      status == "in_progress"
    end

    def completed?
      status == "completed"
    end

    def cancelled?
      status == "cancelled"
    end

    def overdue?
      due_date.present? && due_date < Time.current && !completed? && !cancelled?
    end

    def start!
      update!(status: "in_progress", workflow_data: workflow_data.merge(started_at: Time.current))
    end

    def complete!(notes: nil)
      update_data = { status: "completed" }
      update_data[:notes] = notes if notes.present?
      update!(update_data)
    end

    def cancel!(reason: nil)
      workflow_data[:cancelled_reason] = reason if reason.present?
      update!(status: "cancelled", workflow_data: workflow_data)
    end

    def review?
      workflow_type == "review"
    end

    def approval?
      workflow_type == "approval"
    end

    def translation?
      workflow_type == "translation"
    end

    def update_workflow?
      workflow_type == "update"
    end

    def days_until_due
      return nil unless due_date.present?
      (due_date.to_date - Date.current).to_i
    end

    def duration_in_progress
      return nil unless in_progress? || completed?

      started_at = workflow_data["started_at"]&.to_time
      return nil unless started_at

      end_time = completed? ? updated_at : Time.current
      ((end_time - started_at) / 1.hour).round(1)
    end

    private

    def set_completion_date
      self.workflow_data = workflow_data.merge(completed_at: Time.current)
    end
  end
end

# Backward compatibility alias
KnowledgeBaseWorkflow = KnowledgeBase::Workflow
