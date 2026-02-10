# frozen_string_literal: true

module Ai
  class MarketplaceModeration < ApplicationRecord
    self.table_name = "ai_marketplace_moderations"

    # Associations
    belongs_to :agent_template, class_name: "Ai::AgentTemplate"
    belongs_to :submitted_by, class_name: "User"
    belongs_to :reviewed_by, class_name: "User", optional: true

    # Validations
    validates :status, presence: true, inclusion: { in: %w[pending in_review approved rejected revision_requested] }
    validates :review_type, presence: true, inclusion: { in: %w[initial update reinstatement appeal] }
    validates :submitted_at, presence: true
    validates :rejection_reason, presence: true, if: -> { status == "rejected" }

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :in_review, -> { where(status: "in_review") }
    scope :approved, -> { where(status: "approved") }
    scope :rejected, -> { where(status: "rejected") }
    scope :needs_revision, -> { where(status: "revision_requested") }
    scope :recent, -> { order(submitted_at: :desc) }
    scope :actionable, -> { where(status: %w[pending in_review]) }

    # Callbacks
    before_validation :set_submitted_at, on: :create

    # Instance methods
    def pending?
      status == "pending"
    end

    def in_review?
      status == "in_review"
    end

    def approved?
      status == "approved"
    end

    def rejected?
      status == "rejected"
    end

    def needs_revision?
      status == "revision_requested"
    end

    def start_review!(reviewer)
      return false unless pending?

      update!(
        status: "in_review",
        reviewed_by: reviewer
      )
    end

    def approve!(reviewer, notes: nil)
      return false unless in_review? || pending?

      transaction do
        update!(
          status: "approved",
          reviewed_by: reviewer,
          reviewed_at: Time.current,
          review_notes: notes
        )

        # Publish the template
        agent_template.update!(status: "published")
      end

      true
    end

    def reject!(reviewer, reason:, notes: nil)
      return false unless in_review? || pending?

      transaction do
        update!(
          status: "rejected",
          reviewed_by: reviewer,
          reviewed_at: Time.current,
          rejection_reason: reason,
          review_notes: notes
        )

        # Update template status
        agent_template.update!(status: "rejected")
      end

      true
    end

    def request_revision!(reviewer, notes:)
      return false unless in_review? || pending?

      update!(
        status: "revision_requested",
        reviewed_by: reviewer,
        reviewed_at: Time.current,
        review_notes: notes
      )
    end

    def submit_revision!(notes: nil)
      return false unless needs_revision?

      update!(
        status: "pending",
        submission_notes: notes,
        submitted_at: Time.current,
        revision_number: revision_number + 1,
        reviewed_by: nil,
        reviewed_at: nil,
        review_notes: nil
      )
    end

    def run_automated_checks!
      results = {}

      # Check template completeness
      results[:has_description] = agent_template.description.present?
      results[:has_features] = agent_template.features.present?
      results[:has_sample_prompts] = agent_template.sample_prompts.present?

      # Check pricing validity
      results[:valid_pricing] = agent_template.free? || agent_template.price_usd.present?

      # Check source agent exists and is valid
      results[:valid_source_agent] = agent_template.source_agent&.active?

      # Overall pass/fail
      passed = results.values.all?

      update!(
        passed_automated_checks: passed,
        automated_check_results: results,
        automated_checks_at: Time.current
      )

      passed
    end

    def summary
      {
        id: id,
        template_id: agent_template_id,
        template_name: agent_template.name,
        status: status,
        review_type: review_type,
        revision_number: revision_number,
        submitted_at: submitted_at,
        submitted_by: submitted_by.name,
        reviewed_at: reviewed_at,
        reviewed_by: reviewed_by&.name,
        passed_automated_checks: passed_automated_checks,
        rejection_reason: rejection_reason
      }
    end

    private

    def set_submitted_at
      self.submitted_at ||= Time.current
    end
  end
end
