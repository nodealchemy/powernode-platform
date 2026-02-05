# frozen_string_literal: true

module Ai
  class ReviewWorkflowService
    attr_reader :account

    def initialize(account:)
      @account = account
    end

    # Called after task completion. Checks review_config, finds reviewer, creates review.
    def on_task_completed(task)
      team = task.team_execution&.agent_team
      return unless team

      config = team.review_config || {}
      return unless config["auto_review_enabled"]
      return unless reviewable?(task, config)

      reviewer_role = find_reviewer_role(team, config)
      return unless reviewer_role

      review_mode = config["review_mode"] || "blocking"
      create_review(task: task, reviewer_role: reviewer_role, mode: review_mode)
    end

    # Creates TaskReview and routes to reviewer
    def create_review(task:, reviewer_role:, mode:)
      review = Ai::TaskReview.create!(
        account: account,
        team_task: task,
        reviewer_role: reviewer_role,
        reviewer_agent: reviewer_role.ai_agent,
        status: "pending",
        review_mode: mode,
        completeness_checks: self.class.check_completeness(task.output_data || {}),
        metadata: {
          "task_type" => task.task_type,
          "team_id" => task.team_execution&.agent_team_id
        }
      )

      if mode == "blocking"
        task.update!(status: "waiting") if task.status == "completed"
      end

      review.start!
      review
    end

    # Processes review result
    def process_review(review, result:, notes: nil)
      case result
      when "approve"
        review.approve!(notes: notes)
        on_review_approved(review)
      when "reject"
        review.reject!(reason: notes || "Rejected by reviewer")
        on_review_rejected(review)
      when "revision"
        review.request_revision!(reason: notes || "Revision requested")
        on_revision_requested(review)
      else
        raise ArgumentError, "Invalid review action: #{result}. Must be 'approve', 'reject', or 'revision'"
      end

      review
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
        "has_todos" => has_todos,
        "has_stubs" => has_stubs,
        "has_empty_implementations" => has_empty,
        "completeness_score" => [completeness_score, 0.0].max
      }
    end

    # List reviews for a task
    def list_reviews(task_id)
      account.ai_task_reviews.where(team_task_id: task_id).order(created_at: :desc)
    end

    # Get a review by ID
    def get_review(review_id)
      account.ai_task_reviews.find_by!(review_id: review_id)
    end

    private

    def reviewable?(task, config)
      review_types = config["review_task_types"] || ["execution"]
      review_types.include?(task.task_type)
    end

    def find_reviewer_role(team, config)
      reviewer_type = config["reviewer_role_type"] || "reviewer"
      team.ai_team_roles.find_by(role_type: reviewer_type)
    end

    def on_review_approved(review)
      task = review.team_task
      return unless review.review_mode == "blocking"

      task.update!(status: "completed") if task.status == "waiting"
    end

    def on_review_rejected(review)
      task = review.team_task
      return unless review.review_mode == "blocking"

      task.update!(
        status: "failed",
        failure_reason: "Rejected by reviewer: #{review.rejection_reason}"
      )
    end

    def on_revision_requested(review)
      team = review.team_task.team_execution&.agent_team
      config = team&.review_config || {}
      max_revisions = config["max_revisions"] || 3

      if review.revision_count >= max_revisions
        review.reject!(reason: "Max revisions (#{max_revisions}) exceeded")
        on_review_rejected(review)
        return
      end

      task = review.team_task
      return unless review.review_mode == "blocking"

      task.update!(
        status: "assigned",
        output_data: (task.output_data || {}).merge(
          "revision_feedback" => review.rejection_reason,
          "revision_number" => review.revision_count
        )
      )
    end
  end
end
