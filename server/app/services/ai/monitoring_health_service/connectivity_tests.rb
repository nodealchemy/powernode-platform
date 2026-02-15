# frozen_string_literal: true

module Ai
  class MonitoringHealthService
    module ConnectivityTests
      extend ActiveSupport::Concern

      # Get connectivity test results
      # @return [Hash] Connectivity data
      def connectivity_check
        {
          timestamp: Time.current.iso8601,
          database: test_database_connection,
          redis: test_redis_connection,
          providers: test_provider_connections,
          workers: test_worker_connectivity,
          external_services: test_external_services
        }
      end

      def test_database_connection
        start_time = Time.current
        ActiveRecord::Base.connection.execute("SELECT 1")
        response_time = ((Time.current - start_time) * 1000).round(2)

        {
          status: "healthy",
          response_time_ms: response_time
        }
      rescue StandardError => e
        {
          status: "unhealthy",
          error: e.message
        }
      end

      def test_redis_connection
        redis = Redis.new
        redis.ping

        {
          status: "connected"
        }
      rescue StandardError => e
        {
          status: "disconnected",
          error: e.message
        }
      end

      def test_provider_connections
        account.ai_providers.where(is_active: true).map do |provider|
          {
            provider_id: provider.id,
            name: provider.name,
            type: provider.provider_type,
            has_credentials: provider.provider_credentials.where(is_active: true).exists?,
            status: provider.is_active ? "configured" : "inactive"
          }
        end
      end

      def test_worker_connectivity
        {
          last_activity: last_worker_activity_time,
          recent_completions: ::Ai::WorkflowRun.where("completed_at >= ?", 5.minutes.ago).count,
          pending_jobs: ::Ai::WorkflowRun.where(status: %w[initializing running waiting_approval]).count
        }
      end

      def test_external_services
        {
          redis: test_redis_connection,
          database: test_database_connection
        }
      end
    end
  end
end
