# frozen_string_literal: true

# AiTaskReviewProcessJob - Processes task reviews asynchronously
# Handles both blocking and shadow review modes without blocking the orchestrator
class AiTaskReviewProcessJob < BaseJob
  queue_as :ai_orchestration
  sidekiq_options retry: 2

  def execute(args = {})
    @account_id = args[:account_id] || args['account_id']
    @task_id = args[:task_id] || args['task_id']
    @team_id = args[:team_id] || args['team_id']
    @review_mode = args[:review_mode] || args['review_mode'] || 'shadow'

    raise ArgumentError, "account_id is required" unless @account_id
    raise ArgumentError, "task_id is required" unless @task_id
    raise ArgumentError, "team_id is required" unless @team_id

    # Create review via backend API
    review = create_review

    logger.info "[AiTaskReviewProcessJob] Review created for task #{@task_id} (mode: #{@review_mode})"
    review
  end

  private

  def create_review
    response = api_client.post(
      "/api/v1/ai/teams/#{@team_id}/reviews",
      {
        account_id: @account_id,
        task_id: @task_id,
        review_mode: @review_mode
      }
    )

    raise "Review creation failed: #{response['error']}" unless response['success']

    response['data']
  rescue StandardError => e
    logger.error "[AiTaskReviewProcessJob] Failed to create review: #{e.message}"
    report_failure(e)
    raise
  end

  def report_failure(error)
    api_client.post(
      "/api/v1/internal/team_tasks/#{@task_id}/review_failed",
      {
        error: error.message,
        job_id: jid,
        failed_at: Time.current.iso8601
      }
    )
  rescue StandardError
    # Ignore reporting failures
  end
end
