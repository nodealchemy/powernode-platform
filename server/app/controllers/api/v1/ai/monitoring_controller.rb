# frozen_string_literal: true

# Consolidated Monitoring Controller - Phase 3 Controller Consolidation
#
# This controller consolidates monitoring-related controllers into a single
# RESTful resource controller following the AI Orchestration Redesign pattern.
#
# Consolidates:
# - MonitoringController (status, health, metrics, alerts)
# - CircuitBreakersController (circuit breaker management)
# - AiHealthController (comprehensive health checks)
#
# Architecture:
# - Primary resource: Monitoring Dashboard
# - Integrates with UnifiedMonitoringService (Phase 1)
# - Circuit breaker management
# - Real-time metrics broadcasting
# - Comprehensive health checking
#
module Api
  module V1
    module Ai
      class MonitoringController < ApplicationController
        include AuditLogging

        # Authentication and permission handling
        before_action :validate_permissions
        before_action :set_time_range, only: [:dashboard, :metrics, :health]
        before_action :set_components, only: [:dashboard, :metrics]

        # =============================================================================
        # DASHBOARD & METRICS - PRIMARY RESOURCE
        # =============================================================================

        # GET /api/v1/ai/monitoring/dashboard
        def dashboard
          account = current_account
          service = UnifiedMonitoringService.new(account: account)
          dashboard_data = service.get_dashboard(
            time_range: @time_range,
            components: @components
          )

          render_success({
            dashboard: dashboard_data,
            generated_at: Time.current.iso8601
          })

          log_audit_event('ai.monitoring.dashboard', account) if account
        end

        # GET /api/v1/ai/monitoring/metrics
        def metrics
          service = UnifiedMonitoringService.new(account: current_user.account)

          # Collect specific component metrics
          metrics_data = {}
          @components.each do |component|
            metrics_data[component] = service.collect_component_metrics(component, @time_range)
          end

          render_success({
            metrics: metrics_data,
            time_range_seconds: @time_range.to_i,
            timestamp: Time.current.iso8601
          })
        end

        # GET /api/v1/ai/monitoring/overview
        def overview
          service = UnifiedMonitoringService.new(account: current_user.account)

          overview_data = service.get_system_overview
          health_score = service.calculate_health_score

          render_success({
            overview: overview_data,
            health_score: health_score,
            health_status: determine_health_status(health_score),
            timestamp: Time.current.iso8601
          })
        end

        # =============================================================================
        # HEALTH CHECKS
        # =============================================================================

        # GET /api/v1/ai/monitoring/health
        def health
          health_data = {
            timestamp: Time.current.iso8601,
            time_range_seconds: @time_range.to_i,
            system: check_system_health,
            database: check_database_health,
            redis: check_redis_health,
            providers: check_provider_health,
            workers: check_worker_health,
            circuit_breakers: circuit_breaker_summary
          }

          # Calculate overall health score
          health_score = calculate_overall_health_score(health_data)
          health_data[:health_score] = health_score
          health_data[:status] = determine_health_status(health_score)

          render_success(health_data)

          log_audit_event('ai.monitoring.health_check', current_user.account,
            health_score: health_score,
            status: health_data[:status]
          )
        end

        # GET /api/v1/ai/monitoring/health/detailed
        def health_detailed
          detailed_data = {
            timestamp: Time.current.iso8601,
            services: {
              database: detailed_database_health,
              redis: detailed_redis_health,
              providers: detailed_provider_health,
              workflows: detailed_workflow_health,
              agents: detailed_agent_health,
              workers: detailed_worker_health
            },
            recent_activity: recent_activity_summary,
            error_analysis: recent_error_analysis,
            performance_metrics: performance_metrics,
            resource_metrics: resource_metrics
          }

          render_success(detailed_data)
        end

        # GET /api/v1/ai/monitoring/health/connectivity
        def health_connectivity
          connectivity_data = {
            timestamp: Time.current.iso8601,
            database: test_database_connection,
            redis: test_redis_connection,
            providers: test_provider_connections,
            workers: test_worker_connectivity,
            external_services: test_external_services
          }

          render_success(connectivity_data)
        end

        # =============================================================================
        # ALERTS
        # =============================================================================

        # GET /api/v1/ai/monitoring/alerts
        def alerts
          service = UnifiedMonitoringService.new(account: current_user.account)

          filters = {
            severity: params[:severity],
            type: params[:alert_type],
            status: params[:status] || 'active'
          }.compact

          alerts_data = service.get_alerts(filters)

          render_success({
            alerts: alerts_data,
            timestamp: Time.current.iso8601
          })

          log_audit_event('ai.monitoring.alerts_view', current_user.account,
            filters: filters,
            alert_count: alerts_data[:total_alerts]
          )
        end

        # POST /api/v1/ai/monitoring/alerts/check
        def alerts_check
          service = UnifiedMonitoringService.new(account: current_user.account)
          triggered_alerts = service.check_and_trigger_alerts

          render_success({
            alerts_checked: true,
            triggered_alerts: triggered_alerts,
            count: triggered_alerts.count,
            timestamp: Time.current.iso8601
          })

          log_audit_event('ai.monitoring.alerts_check', current_user.account,
            triggered_count: triggered_alerts.count
          )
        end

        # =============================================================================
        # CIRCUIT BREAKERS
        # =============================================================================

        # GET /api/v1/ai/monitoring/circuit_breakers
        def circuit_breakers_index
          states = AiWorkflowCircuitBreakerManager.all_states
          summary = AiWorkflowCircuitBreakerManager.health_summary

          render_success({
            circuit_breakers: states,
            summary: summary,
            timestamp: Time.current.iso8601
          })
        end

        # GET /api/v1/ai/monitoring/circuit_breakers/:service_name
        def circuit_breaker_show
          service_name = params[:service_name]
          breaker = AiWorkflowCircuitBreakerManager.get_breaker(service_name)

          if breaker
            render_success({
              service_name: service_name,
              stats: breaker.stats,
              timestamp: Time.current.iso8601
            })
          else
            render_error('Circuit breaker not found', status: :not_found)
          end
        end

        # POST /api/v1/ai/monitoring/circuit_breakers/:service_name/reset
        def circuit_breaker_reset
          service_name = params[:service_name]
          breaker = AiWorkflowCircuitBreakerManager.get_or_create_breaker(service_name)
          breaker.reset!

          render_success({
            message: "Circuit breaker reset for #{service_name}",
            service_name: service_name,
            state: breaker.stats
          })

          log_audit_event('ai.monitoring.circuit_breaker.reset', current_user.account,
            service_name: service_name
          )
        end

        # POST /api/v1/ai/monitoring/circuit_breakers/:service_name/open
        def circuit_breaker_open
          service_name = params[:service_name]
          breaker = AiWorkflowCircuitBreakerManager.get_or_create_breaker(service_name)
          breaker.open!

          render_success({
            message: "Circuit breaker opened for #{service_name}",
            service_name: service_name,
            state: breaker.stats
          })

          log_audit_event('ai.monitoring.circuit_breaker.open', current_user.account,
            service_name: service_name
          )
        end

        # POST /api/v1/ai/monitoring/circuit_breakers/:service_name/close
        def circuit_breaker_close
          service_name = params[:service_name]
          breaker = AiWorkflowCircuitBreakerManager.get_or_create_breaker(service_name)
          breaker.close!

          render_success({
            message: "Circuit breaker closed for #{service_name}",
            service_name: service_name,
            state: breaker.stats
          })

          log_audit_event('ai.monitoring.circuit_breaker.close', current_user.account,
            service_name: service_name
          )
        end

        # POST /api/v1/ai/monitoring/circuit_breakers/reset_all
        def circuit_breakers_reset_all
          AiWorkflowCircuitBreakerManager.reset_all!
          summary = AiWorkflowCircuitBreakerManager.health_summary

          render_success({
            message: 'All circuit breakers reset',
            summary: summary,
            timestamp: Time.current.iso8601
          })

          log_audit_event('ai.monitoring.circuit_breakers.reset_all', current_user.account)
        end

        # GET /api/v1/ai/monitoring/circuit_breakers/category/:category
        def circuit_breakers_category
          category = params[:category]
          states = AiWorkflowCircuitBreakerManager.category_states(category)

          render_success({
            category: category,
            circuit_breakers: states,
            count: states.length,
            timestamp: Time.current.iso8601
          })
        end

        # POST /api/v1/ai/monitoring/circuit_breakers/category/:category/reset
        def circuit_breakers_category_reset
          category = params[:category]
          AiWorkflowCircuitBreakerManager.reset_category!(category)
          states = AiWorkflowCircuitBreakerManager.category_states(category)

          render_success({
            message: "Circuit breakers reset for category: #{category}",
            category: category,
            circuit_breakers: states
          })

          log_audit_event('ai.monitoring.circuit_breakers.category_reset', current_user.account,
            category: category
          )
        end

        # GET /api/v1/ai/monitoring/circuit_breakers/monitor
        def circuit_breakers_monitor
          summary = AiWorkflowCircuitBreakerManager.monitor_and_alert

          render_success({
            monitored_at: Time.current.iso8601,
            summary: summary,
            alerts_triggered: summary[:unhealthy] > 0 || summary[:degraded] > 0
          })
        end

        # =============================================================================
        # REAL-TIME MONITORING
        # =============================================================================

        # POST /api/v1/ai/monitoring/broadcast
        def broadcast_metrics
          # This endpoint is called by worker jobs to trigger real-time broadcasting
          # Require explicit account_id parameter (no fallback to current_user)
          unless params[:account_id].present?
            render_error('Missing account_id parameter', status: :bad_request)
            return
          end

          account_id = params[:account_id]

          account = Account.find(account_id)
          service = UnifiedMonitoringService.new(account: account)

          # Generate real-time metrics
          metrics = service.get_dashboard(time_range: 1.hour, components: %w[system providers agents workflows])

          # Broadcast via WebSocket
          ActionCable.server.broadcast(
            "ai_orchestration_#{account_id}",
            {
              type: 'system_metrics_update',
              metrics: metrics,
              timestamp: Time.current.iso8601
            }
          )

          render_success({
            message: 'Metrics broadcasted successfully',
            account_id: account_id,
            timestamp: Time.current.iso8601
          })
        rescue ActiveRecord::RecordNotFound
          render_error('Account not found', status: :not_found)
        rescue StandardError => e
          Rails.logger.error "Failed to broadcast metrics: #{e.message}"
          render_error("Failed to broadcast metrics: #{e.message}", status: :internal_server_error)
        end

        # POST /api/v1/ai/monitoring/start
        def start_monitoring
          account_id = current_user.account_id

          begin
            # Schedule the monitoring health check job
            AiMonitoringHealthCheckJob.perform_async(account_id)

            render_success({
              message: 'Real-time monitoring started',
              account_id: account_id,
              timestamp: Time.current.iso8601
            })

            log_audit_event('ai.monitoring.start', current_user.account)
          rescue StandardError => e
            Rails.logger.error "Failed to start monitoring: #{e.message}"
            render_error("Failed to start monitoring: #{e.message}", status: :internal_server_error)
          end
        end

        # POST /api/v1/ai/monitoring/stop
        def stop_monitoring
          # Note: In a real implementation, track and cancel specific monitoring jobs
          render_success({
            message: 'Monitoring stop requested',
            account_id: current_user.account_id,
            timestamp: Time.current.iso8601
          })

          log_audit_event('ai.monitoring.stop', current_user.account)
        end

        private

        # =============================================================================
        # AUTHORIZATION
        # =============================================================================

        def validate_permissions
          # Skip for workers
          return if current_worker

          case action_name
          when 'dashboard', 'metrics', 'overview', 'health', 'health_detailed', 'health_connectivity'
            require_permission('ai.monitoring.read')
          when 'alerts', 'alerts_check'
            require_permission('ai.monitoring.read')
          when 'circuit_breakers_index', 'circuit_breaker_show', 'circuit_breakers_category', 'circuit_breakers_monitor'
            require_permission('ai.monitoring.read')
          when 'circuit_breaker_reset', 'circuit_breaker_open', 'circuit_breaker_close'
            require_permission('ai.monitoring.manage')
          when 'circuit_breakers_reset_all', 'circuit_breakers_category_reset'
            require_permission('ai.monitoring.manage')
          when 'broadcast_metrics', 'start_monitoring', 'stop_monitoring'
            require_permission('ai.monitoring.manage')
          end
        end

        # Get account from either current user or worker
        def current_account
          current_worker&.account || current_user&.account
        end

        # =============================================================================
        # PARAMETER HANDLING
        # =============================================================================

        def set_time_range
          range_param = params[:time_range]&.to_i || 3600 # Default 1 hour

          @time_range = case range_param
                       when 0..3600 then range_param.seconds
                       when 3601..86400 then range_param.seconds
                       when 86401..604800 then range_param.seconds
                       else 1.hour
                       end
        end

        def set_components
          # Default to all components if not specified
          @components = if params[:components].present?
                         params[:components].split(',').map(&:strip) & UnifiedMonitoringService::COMPONENTS
                       else
                         UnifiedMonitoringService::COMPONENTS
                       end
        end

        # =============================================================================
        # HEALTH CHECK HELPERS
        # =============================================================================

        def check_system_health
          {
            status: 'healthy',
            uptime: estimate_system_uptime,
            active_workflows: AiWorkflow.where(is_active: true).count,
            active_agents: AiAgent.where(status: 'active').count,
            running_executions: AiWorkflowRun.where(status: %w[initializing running waiting_approval]).count
          }
        end

        def check_database_health
          ActiveRecord::Base.connection.execute('SELECT 1')

          pool_stat = ActiveRecord::Base.connection_pool.stat
          {
            status: 'healthy',
            connection: 'active',
            connection_pool: {
              size: pool_stat[:size],
              connections: pool_stat[:connections],
              busy: pool_stat[:busy],
              idle: pool_stat[:idle],
              available: pool_stat[:idle]
            }
          }
        rescue StandardError => e
          {
            status: 'unhealthy',
            error: e.message
          }
        end

        def check_redis_health
          redis = Redis.new
          redis.ping

          info = redis.info
          {
            status: 'healthy',
            used_memory: info['used_memory_human'],
            connected_clients: info['connected_clients']&.to_i || 0
          }
        rescue StandardError => e
          {
            status: 'unhealthy',
            error: e.message
          }
        end

        def check_provider_health
          providers = current_user.account.ai_providers.where(is_active: true)

          {
            total_providers: providers.count,
            healthy_providers: providers.count { |p| provider_is_healthy?(p) },
            providers: providers.map { |p| provider_health_summary(p) }
          }
        end

        def check_worker_health
          recent_completions = AiWorkflowRun.where('completed_at >= ?', 10.minutes.ago).count
          recent_starts = AiWorkflowRun.where('created_at >= ?', 10.minutes.ago).count

          {
            status: recent_completions > 0 || recent_starts == 0 ? 'healthy' : 'degraded',
            recent_completions: recent_completions,
            recent_starts: recent_starts,
            estimated_backlog: [recent_starts - recent_completions, 0].max,
            last_activity: last_worker_activity_time
          }
        end

        def circuit_breaker_summary
          AiWorkflowCircuitBreakerManager.health_summary
        end

        def provider_is_healthy?(provider)
          recent_executions = AiAgentExecution.where(ai_agent: AiAgent.where(ai_provider: provider))
                                             .where('created_at >= ?', 5.minutes.ago)

          return true if recent_executions.empty?

          success_count = recent_executions.where(status: 'completed').count
          success_rate = (success_count.to_f / recent_executions.count * 100).round(2)
          success_rate >= 95.0
        end

        def provider_health_summary(provider)
          {
            id: provider.id,
            name: provider.name,
            provider_type: provider.provider_type,
            status: provider.is_active ? 'active' : 'inactive',
            has_credentials: provider.ai_provider_credentials.where(is_active: true).exists?,
            is_healthy: provider_is_healthy?(provider)
          }
        end

        # =============================================================================
        # DETAILED HEALTH CHECKS
        # =============================================================================

        def detailed_database_health
          pool_stat = ActiveRecord::Base.connection_pool.stat
          {
            status: 'healthy',
            connection_pool: {
              size: pool_stat[:size],
              connections: pool_stat[:connections],
              busy: pool_stat[:busy],
              idle: pool_stat[:idle],
              available: pool_stat[:idle]
            },
            table_counts: {
              ai_providers: AiProvider.count,
              ai_workflows: AiWorkflow.count,
              ai_agents: AiAgent.count,
              ai_workflow_runs_today: AiWorkflowRun.where('created_at >= ?', Date.current).count,
              ai_conversations_today: AiConversation.where('created_at >= ?', Date.current).count
            }
          }
        rescue StandardError => e
          {
            status: 'unhealthy',
            error: e.message
          }
        end

        def detailed_redis_health
          redis = Redis.new
          info = redis.info

          {
            status: 'healthy',
            version: info['redis_version'],
            used_memory: info['used_memory_human'],
            used_memory_peak: info['used_memory_peak_human'],
            connected_clients: info['connected_clients']&.to_i || 0,
            uptime_days: info['uptime_in_days']&.to_i || 0
          }
        rescue StandardError => e
          {
            status: 'unhealthy',
            error: e.message
          }
        end

        def detailed_provider_health
          current_user.account.ai_providers.where(is_active: true).map do |provider|
            {
              id: provider.id,
              name: provider.name,
              provider_type: provider.provider_type,
              status: provider.is_active ? 'active' : 'inactive',
              credentials_count: provider.ai_provider_credentials.where(is_active: true).count,
              recent_executions: AiAgentExecution.where(ai_agent: AiAgent.where(ai_provider: provider))
                                                .where('created_at >= ?', 24.hours.ago)
                                                .count
            }
          end
        end

        def detailed_workflow_health
          workflows = current_user.account.ai_workflows

          {
            total_workflows: workflows.count,
            active_workflows: workflows.where(is_active: true).count,
            running_executions: AiWorkflowRun.where(ai_workflow: workflows)
                                            .where(status: %w[initializing running waiting_approval])
                                            .count,
            recent_runs: {
              last_hour: AiWorkflowRun.where(ai_workflow: workflows).where('created_at >= ?', 1.hour.ago).count,
              last_24h: AiWorkflowRun.where(ai_workflow: workflows).where('created_at >= ?', 24.hours.ago).count
            },
            success_rate: calculate_workflow_success_rate(workflows)
          }
        end

        def detailed_agent_health
          agents = current_user.account.ai_agents

          {
            total_agents: agents.count,
            active_agents: agents.where(status: 'active').count,
            recent_executions: {
              last_hour: AiAgentExecution.where(ai_agent: agents).where('created_at >= ?', 1.hour.ago).count,
              last_24h: AiAgentExecution.where(ai_agent: agents).where('created_at >= ?', 24.hours.ago).count
            }
          }
        end

        def detailed_worker_health
          {
            recent_activity: {
              workflow_runs: AiWorkflowRun.where('created_at >= ?', 1.hour.ago).count,
              completed_runs: AiWorkflowRun.where(status: 'completed').where('completed_at >= ?', 1.hour.ago).count,
              failed_runs: AiWorkflowRun.where(status: 'failed').where('completed_at >= ?', 1.hour.ago).count
            },
            queue_health: {
              processing_rate: AiWorkflowRun.where('completed_at >= ?', 10.minutes.ago).count,
              creation_rate: AiWorkflowRun.where('created_at >= ?', 10.minutes.ago).count
            }
          }
        end

        # =============================================================================
        # CONNECTIVITY TESTS
        # =============================================================================

        def test_database_connection
          start_time = Time.current
          ActiveRecord::Base.connection.execute('SELECT 1')
          response_time = ((Time.current - start_time) * 1000).round(2)

          {
            status: 'healthy',
            response_time_ms: response_time
          }
        rescue StandardError => e
          {
            status: 'unhealthy',
            error: e.message
          }
        end

        def test_redis_connection
          redis = Redis.new
          redis.ping

          {
            status: 'connected'
          }
        rescue StandardError => e
          {
            status: 'disconnected',
            error: e.message
          }
        end

        def test_provider_connections
          providers = current_user.account.ai_providers.where(is_active: true)

          providers.map do |provider|
            {
              provider_id: provider.id,
              name: provider.name,
              type: provider.provider_type,
              has_credentials: provider.ai_provider_credentials.where(is_active: true).exists?,
              status: provider.is_active ? 'configured' : 'inactive'
            }
          end
        end

        def test_worker_connectivity
          {
            last_activity: last_worker_activity_time,
            recent_completions: AiWorkflowRun.where('completed_at >= ?', 5.minutes.ago).count,
            pending_jobs: AiWorkflowRun.where(status: %w[initializing running waiting_approval]).count
          }
        end

        def test_external_services
          {
            redis: test_redis_connection,
            database: test_database_connection
          }
        end

        # =============================================================================
        # ANALYTICS & METRICS
        # =============================================================================

        def recent_activity_summary
          {
            last_hour: {
              workflow_runs: AiWorkflowRun.where('created_at >= ?', 1.hour.ago).count,
              completed_runs: AiWorkflowRun.where('created_at >= ? AND status = ?', 1.hour.ago, 'completed').count,
              failed_runs: AiWorkflowRun.where('created_at >= ? AND status = ?', 1.hour.ago, 'failed').count
            },
            last_24h: {
              workflow_runs: AiWorkflowRun.where('created_at >= ?', 24.hours.ago).count,
              completed_runs: AiWorkflowRun.where('created_at >= ? AND status = ?', 24.hours.ago, 'completed').count,
              failed_runs: AiWorkflowRun.where('created_at >= ? AND status = ?', 24.hours.ago, 'failed').count
            }
          }
        end

        def recent_error_analysis
          failed_runs = AiWorkflowRun.where('created_at >= ? AND status = ?', 24.hours.ago, 'failed')
                                     .includes(:ai_workflow)
                                     .limit(10)

          {
            total_failures: failed_runs.count,
            recent_failures: failed_runs.map do |run|
              {
                workflow_name: run.ai_workflow.name,
                failed_at: run.completed_at,
                error_summary: run.error_details.is_a?(Hash) ? run.error_details['error_message'] : 'Unknown error'
              }
            end
          }
        end

        def performance_metrics
          {
            average_execution_time: calculate_average_execution_time,
            throughput: {
              workflows_per_hour: AiWorkflowRun.where('created_at >= ?', 1.hour.ago).count,
              conversations_per_hour: AiConversation.where('created_at >= ?', 1.hour.ago).count
            },
            resource_usage: {
              active_conversations: AiConversation.where('updated_at >= ?', 1.hour.ago).count,
              running_workflows: AiWorkflowRun.where(status: %w[initializing running waiting_approval]).count,
              database_connections: ActiveRecord::Base.connection_pool.connections.size
            }
          }
        end

        def resource_metrics
          pool_stat = ActiveRecord::Base.connection_pool.stat
          {
            database: {
              connections: pool_stat[:connections],
              available: pool_stat[:idle]
            },
            redis: check_redis_health,
            active_records: {
              active_workflows: AiWorkflowRun.where(status: %w[initializing running waiting_approval]).count,
              active_conversations: AiConversation.where('updated_at >= ?', 1.hour.ago).count
            }
          }
        end

        # =============================================================================
        # CALCULATION HELPERS
        # =============================================================================

        def calculate_overall_health_score(health_data)
          scores = []

          # Database health (25%)
          scores << (health_data[:database][:status] == 'healthy' ? 100 : 0) * 0.25

          # Redis health (25%)
          scores << (health_data[:redis][:status] == 'healthy' ? 100 : 0) * 0.25

          # Provider health (25%)
          provider_score = if health_data[:providers][:total_providers] > 0
                            (health_data[:providers][:healthy_providers].to_f / health_data[:providers][:total_providers] * 100)
                          else
                            100
                          end
          scores << (provider_score * 0.25)

          # Worker health (25%)
          worker_score = health_data[:workers][:status] == 'healthy' ? 100 : 50
          scores << (worker_score * 0.25)

          scores.sum.round
        end

        def determine_health_status(health_score)
          case health_score
          when 80..100 then 'healthy'
          when 50..79 then 'degraded'
          when 20..49 then 'unhealthy'
          else 'critical'
          end
        end

        def calculate_workflow_success_rate(workflows)
          runs = AiWorkflowRun.where(ai_workflow: workflows).where('created_at >= ?', 24.hours.ago)
          total = runs.count
          successful = runs.where(status: 'completed').count

          total > 0 ? (successful.to_f / total * 100).round(2) : 0
        end

        def calculate_average_execution_time
          completed_runs = AiWorkflowRun.where(status: 'completed')
                                        .where('completed_at >= ?', 24.hours.ago)
                                        .where.not(duration_ms: nil)

          return 0 if completed_runs.empty?

          (completed_runs.average(:duration_ms) || 0).round(2)
        end

        def estimate_system_uptime
          oldest_active = AiWorkflowRun.where(status: %w[initializing running waiting_approval])
                                       .order(:created_at)
                                       .first&.created_at

          return 0 unless oldest_active

          (Time.current - oldest_active).to_i
        end

        def last_worker_activity_time
          recent_completion = AiWorkflowRun.where(status: %w[completed failed])
                                           .order(completed_at: :desc)
                                           .first&.completed_at

          recent_message = AiMessage.where(role: 'assistant')
                                   .order(created_at: :desc)
                                   .first&.created_at

          [recent_completion, recent_message].compact.max
        end
      end
    end
  end
end
