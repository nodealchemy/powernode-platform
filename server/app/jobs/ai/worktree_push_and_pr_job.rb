# frozen_string_literal: true

module Ai
  class WorktreePushAndPrJob < ApplicationJob
    queue_as :ai_execution

    def perform(session_id, options = {})
      session = Ai::WorktreeSession.find(session_id)

      unless session.status == "completed"
        Rails.logger.warn("[WorktreePushAndPrJob] Session #{session_id} not completed (status: #{session.status}), skipping")
        return
      end

      config = session.configuration || {}
      repository_path = config["repository_path"] || Rails.root.to_s
      gitea_repository = config["gitea_repository"]

      unless gitea_repository.present?
        Rails.logger.info("[WorktreePushAndPrJob] No gitea_repository configured for session #{session_id}, skipping PR creation")
        return
      end

      service = Ai::Git::GiteaIntegrationService.new(
        repository_path: repository_path,
        gitea_repository: gitea_repository
      )

      title = options["title"] || "AI Session: #{session.description || session.id}"
      body = options["body"]

      result = service.finalize_session_with_pr(
        session: session,
        title: title,
        body: body
      )

      if result[:success]
        Rails.logger.info("[WorktreePushAndPrJob] Created PR ##{result[:pr_number]} for session #{session_id}: #{result[:pr_url]}")

        session.update(
          metadata: (session.metadata || {}).merge(
            "pr_number" => result[:pr_number],
            "pr_url" => result[:pr_url],
            "pr_created_at" => Time.current.iso8601
          )
        )
      else
        Rails.logger.error("[WorktreePushAndPrJob] Failed to create PR for session #{session_id}: #{result[:error]}")
      end
    rescue ActiveRecord::RecordNotFound
      Rails.logger.error("[WorktreePushAndPrJob] Session #{session_id} not found")
    rescue StandardError => e
      Rails.logger.error("[WorktreePushAndPrJob] Error processing session #{session_id}: #{e.message}")
      raise # Re-raise for job retry
    end
  end
end
