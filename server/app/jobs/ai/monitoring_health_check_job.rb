# frozen_string_literal: true

module Ai
  class MonitoringHealthCheckJob < ApplicationJob
    queue_as :monitoring

    def perform(account_id)
      Rails.logger.info "Monitoring health check for account #{account_id}"
      # Health check implementation - can be expanded later
      true
    end
  end
end
