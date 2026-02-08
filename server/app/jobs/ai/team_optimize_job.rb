# frozen_string_literal: true

module Ai
  # TeamOptimizeJob - Stub for dispatching team optimization work to the worker
  #
  # The actual optimization logic lives in the worker service (AiTeamOptimizeJob).
  # This stub provides the perform_async interface for controllers.
  class TeamOptimizeJob < ApplicationJob
    queue_as :ai_execution

    def self.perform_async(args = {})
      perform_later(args)
    end

    def perform(args = {})
      Rails.logger.info("[Ai::TeamOptimizeJob] Dispatched team optimization: #{args}")
    end
  end
end
