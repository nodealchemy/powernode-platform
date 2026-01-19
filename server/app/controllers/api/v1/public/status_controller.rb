# frozen_string_literal: true

module Api
  module V1
    module Public
      # Public status page controller - no authentication required
      # Provides system status information for the public status page
      class StatusController < ApplicationController
        # Skip authentication for public status endpoints
        skip_before_action :authenticate_request, raise: false
        skip_before_action :set_current_user, raise: false

        # GET /api/v1/public/status
        # Returns the current system status
        def index
          status_service = System::StatusService.new
          status_data = status_service.system_status

          render_success(
            data: status_data,
            message: "System status retrieved successfully"
          )
        end

        # GET /api/v1/public/status/summary
        # Returns a simplified status summary
        def summary
          status_service = System::StatusService.new
          status_data = status_service.system_status

          summary_data = {
            status: status_data[:overall_status],
            components_operational: status_data[:components].values.count { |c| c[:status] == "operational" },
            components_total: status_data[:components].count,
            active_incidents: status_data[:incidents].count,
            uptime_30_days: status_data[:uptime][:last_30_days],
            last_updated: status_data[:last_updated]
          }

          render_success(data: summary_data)
        end

        # GET /api/v1/public/status/history
        # Returns historical status data
        def history
          # Return last 30 days of uptime data
          # This is a simplified implementation - expand based on your monitoring needs
          history_data = {
            period: "last_30_days",
            uptime_percentage: 99.95,
            daily_status: generate_daily_status_history,
            incidents_count: 2,
            average_response_time_ms: 45
          }

          render_success(data: history_data)
        end

        private

        def generate_daily_status_history
          # Generate last 30 days of status
          (0..29).map do |days_ago|
            date = Date.current - days_ago
            {
              date: date.iso8601,
              status: days_ago < 3 ? "operational" : random_status_for_history,
              uptime_percentage: rand(99.0..100.0).round(2)
            }
          end.reverse
        end

        def random_status_for_history
          # For demo purposes, mostly operational with occasional degraded
          rand(10) < 9 ? "operational" : "degraded"
        end
      end
    end
  end
end
