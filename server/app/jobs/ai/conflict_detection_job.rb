# frozen_string_literal: true

module Ai
  class ConflictDetectionJob < ApplicationJob
    queue_as :ai_execution

    def perform(session_id)
      session = Ai::WorktreeSession.find(session_id)
      return if session.terminal?

      service = Ai::Git::ConflictDetectionService.new(session: session)
      service.detect
    rescue StandardError => e
      Rails.logger.error "[ConflictDetection] Job failed for session #{session_id}: #{e.message}"
    end
  end
end
