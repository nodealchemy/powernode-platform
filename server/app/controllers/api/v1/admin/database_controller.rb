# frozen_string_literal: true

module Api
  module V1
    module Admin
      # DatabaseController - Database monitoring and health endpoints
      # Used by worker service and admin dashboard for database health monitoring
      class DatabaseController < ApplicationController
        skip_before_action :authenticate_request
        before_action :require_admin_or_worker_token

        # GET /api/v1/admin/database/pool_stats
        # Returns database connection pool statistics
        def pool_stats
          pool = ActiveRecord::Base.connection_pool
          stats = pool.stat

          render_success({
            size: pool.size,
            checked_out: stats[:busy],
            checked_in: stats[:idle],
            dead: stats[:dead],
            waiting: stats[:waiting],
            num_waiting: stats[:num_waiting] || 0
          })
        end

        # GET /api/v1/admin/database/ping
        # Simple database health check
        def ping
          start_time = Time.current
          ActiveRecord::Base.connection.execute("SELECT 1")
          response_time_ms = ((Time.current - start_time) * 1000).round(2)

          render_success({
            status: "ok",
            response_time_ms: response_time_ms,
            timestamp: Time.current.iso8601
          })
        rescue StandardError => e
          render_error("Database ping failed: #{e.message}", :service_unavailable)
        end

        # GET /api/v1/admin/database/health
        # Comprehensive database health check
        def health
          pool = ActiveRecord::Base.connection_pool
          stats = pool.stat

          health_status = {
            status: "healthy",
            checks: {
              connection: check_connection,
              pool_utilization: check_pool_utilization(stats, pool.size),
              response_time: check_response_time
            },
            timestamp: Time.current.iso8601
          }

          # Determine overall health
          if health_status[:checks].values.any? { |check| check[:status] == "critical" }
            health_status[:status] = "critical"
          elsif health_status[:checks].values.any? { |check| check[:status] == "warning" }
            health_status[:status] = "warning"
          end

          render_success(health_status)
        end

        private

        def require_admin_or_worker_token
          # Allow worker service token authentication
          return if worker_token_valid?

          # Otherwise try JWT authentication and require admin permission
          authenticate_request
          return if performed?

          require_permission("system.admin")
        end

        def worker_token_valid?
          auth_header = request.headers["Authorization"]
          return false unless auth_header&.start_with?("Bearer ")

          token = auth_header.split(" ").last
          begin
            payload = Security::JwtService.decode(token)
            return false unless payload[:type] == "worker"
            worker = ::Worker.find_by(id: payload[:sub])
            worker&.active? || false
          rescue StandardError
            false
          end
        end

        def check_connection
          ActiveRecord::Base.connection.active?
          { status: "healthy", message: "Connection active" }
        rescue StandardError => e
          { status: "critical", message: "Connection failed: #{e.message}" }
        end

        def check_pool_utilization(stats, pool_size)
          utilization_pct = (stats[:busy].to_f / pool_size * 100).round(1)

          status = if utilization_pct > 90
                     "critical"
          elsif utilization_pct > 75
                     "warning"
          else
                     "healthy"
          end

          {
            status: status,
            utilization_percentage: utilization_pct,
            busy: stats[:busy],
            idle: stats[:idle],
            dead: stats[:dead]
          }
        end

        def check_response_time
          start_time = Time.current
          ActiveRecord::Base.connection.execute("SELECT 1")
          response_time_ms = ((Time.current - start_time) * 1000).round(2)

          status = if response_time_ms > 1000
                     "critical"
          elsif response_time_ms > 500
                     "warning"
          else
                     "healthy"
          end

          { status: status, response_time_ms: response_time_ms }
        rescue StandardError => e
          { status: "critical", error: e.message }
        end
      end
    end
  end
end
