# frozen_string_literal: true

module Ai
  # DiscoveryScanJob - Stub for dispatching discovery scan work to the worker
  #
  # The actual scan logic lives in the worker service (AiDiscoveryScanJob).
  # This stub provides the perform_async interface for controllers.
  class DiscoveryScanJob < ApplicationJob
    queue_as :ai_execution

    def self.perform_async(args = {})
      perform_later(args)
    end

    def perform(args = {})
      Rails.logger.info("[Ai::DiscoveryScanJob] Dispatched discovery scan: #{args}")
    end
  end
end
