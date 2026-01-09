# frozen_string_literal: true

# Consolidated Analytics Controller - Phase 3 Controller Consolidation
#
# This controller consolidates analytics and reporting controllers into a single
# RESTful resource controller following the AI Orchestration Redesign pattern.
#
# Consolidates:
# - AnalyticsController (AI-specific analytics and insights)
# - ReportsController (report generation and management)
# - WorkflowAnalyticsController (workflow-specific analytics)
#
# Architecture:
# - Primary resource: Analytics Dashboard
# - Nested resources: Reports, Insights, Recommendations
# - Integrates with ::Ai::AnalyticsInsightsService
# - Report generation and scheduling
#
module Api
  module V1
    module Ai
      class AnalyticsController < ApplicationController
        include AuditLogging

        # Authentication and permission handling
        before_action :validate_permissions
        before_action :set_time_range, only: [ :dashboard, :overview, :metrics, :cost_analysis, :performance_analysis, :insights, :recommendations, :workflow_analytics, :agent_analytics, :export ]
        before_action :set_account_scope

        # =============================================================================
        # DASHBOARD & OVERVIEW
        # =============================================================================

        # GET /api/v1/ai/analytics/dashboard
        def dashboard
          analytics_data = generate_dashboard_analytics

          render_success({
            dashboard: analytics_data,
            time_range: {
              start: @time_range.ago.iso8601,
              end: Time.current.iso8601,
              period: params[:time_range] || "30d"
            },
            generated_at: Time.current.iso8601
          })

          log_audit_event("ai.analytics.dashboard", current_user.account) if current_user
        end

        # GET /api/v1/ai/analytics/overview
        def overview
          overview_data = {
            summary: generate_summary_metrics,
            trends: generate_trend_data,
            highlights: generate_highlights,
            quick_stats: generate_quick_stats
          }

          render_success({
            overview: overview_data,
            timestamp: Time.current.iso8601
          })
        end

        # =============================================================================
        # METRICS & ANALYTICS
        # =============================================================================

        # GET /api/v1/ai/analytics/metrics
        def metrics
          metrics_data = {
            workflows: workflow_metrics,
            agents: agent_metrics,
            providers: provider_metrics,
            executions: execution_metrics,
            performance: performance_metrics_data
          }

          render_success({
            metrics: metrics_data,
            time_range_seconds: @time_range.to_i,
            timestamp: Time.current.iso8601
          })
        end

        # GET /api/v1/ai/analytics/real_time
        def real_time
          metrics = generate_real_time_metrics

          render_success({
            metrics: metrics,
            updated_at: Time.current.iso8601,
            refresh_interval: 30 # seconds
          })
        end

        # GET /api/v1/ai/analytics/cost_analysis
        def cost_analysis
          cost_data = {
            total_cost: calculate_total_cost,
            cost_trend: calculate_cost_trend,
            cost_by_provider: cost_breakdown_by_provider,
            cost_by_agent: cost_breakdown_by_agent,
            cost_by_workflow: cost_breakdown_by_workflow,
            optimization_potential: estimate_cost_savings,
            budget_forecast: generate_budget_forecast
          }

          render_success({
            cost_analysis: cost_data,
            time_range: time_range_info,
            timestamp: Time.current.iso8601
          })

          log_audit_event("ai.analytics.cost_analysis", current_user.account) if current_user
        end

        # GET /api/v1/ai/analytics/performance_analysis
        def performance_analysis
          performance_data = {
            response_times: analyze_response_times,
            success_rates: analyze_success_rates,
            throughput: analyze_throughput,
            error_rates: analyze_error_rates,
            resource_utilization: analyze_resource_utilization,
            bottlenecks: identify_bottlenecks
          }

          render_success({
            performance_analysis: performance_data,
            time_range: time_range_info,
            timestamp: Time.current.iso8601
          })
        end

        # =============================================================================
        # INSIGHTS & RECOMMENDATIONS
        # =============================================================================

        # GET /api/v1/ai/analytics/insights
        def insights
          account = @account_scope || current_user&.account
          analytics_service = ::Ai::AnalyticsInsightsService.new(
            account: account,
            time_range: @time_range
          )

          insights_data = analytics_service.generate_insights

          render_success({
            insights: insights_data,
            generated_at: Time.current.iso8601,
            time_range: time_range_info
          })

          log_audit_event("ai.analytics.insights", current_user.account) if current_user
        end

        # GET /api/v1/ai/analytics/recommendations
        def recommendations
          recommendations_data = generate_optimization_recommendations

          render_success({
            recommendations: recommendations_data,
            generated_at: Time.current.iso8601,
            time_range: time_range_info
          })
        end

        # =============================================================================
        # WORKFLOW-SPECIFIC ANALYTICS
        # =============================================================================

        # GET /api/v1/ai/analytics/workflows/:workflow_id
        def workflow_analytics
          workflow = current_user.account.ai_workflows.find(params[:workflow_id])

          analytics_data = {
            workflow: serialize_workflow_summary(workflow),
            runs: analyze_workflow_runs(workflow),
            performance: analyze_workflow_performance(workflow),
            costs: analyze_workflow_costs(workflow),
            success_rate: calculate_workflow_success_rate(workflow),
            average_duration: calculate_workflow_average_duration(workflow),
            node_performance: analyze_node_performance(workflow)
          }

          render_success({
            workflow_analytics: analytics_data,
            time_range: time_range_info,
            timestamp: Time.current.iso8601
          })
        rescue ActiveRecord::RecordNotFound
          render_error("Workflow not found", status: :not_found)
        end

        # GET /api/v1/ai/analytics/agents/:agent_id
        def agent_analytics
          agent = current_user.account.ai_agents.find(params[:agent_id])

          analytics_data = {
            agent: serialize_agent_summary(agent),
            executions: analyze_agent_executions(agent),
            performance: analyze_agent_performance(agent),
            costs: analyze_agent_costs(agent),
            success_rate: calculate_agent_success_rate(agent),
            average_response_time: calculate_agent_average_response_time(agent)
          }

          render_success({
            agent_analytics: analytics_data,
            time_range: time_range_info,
            timestamp: Time.current.iso8601
          })
        rescue ActiveRecord::RecordNotFound
          render_error("Agent not found", status: :not_found)
        end

        # =============================================================================
        # REPORTS - GENERATION & MANAGEMENT
        # =============================================================================

        # GET /api/v1/ai/analytics/reports
        def reports_index
          page = params[:page]&.to_i || 1
          per_page = [ params[:per_page]&.to_i || 20, 100 ].min

          reports = ReportRequest.where(account: @account_scope)
                                .order(created_at: :desc)
                                .page(page)
                                .per(per_page)

          render_success({
            reports: reports.map { |r| serialize_report_request(r) },
            pagination: pagination_data(reports)
          })
        end

        # GET /api/v1/ai/analytics/reports/:id
        def report_show
          report = current_user.account.report_requests.find(params[:id])

          render_success({
            report: serialize_report_request_detail(report)
          })
        rescue ActiveRecord::RecordNotFound
          render_error("Report not found", status: :not_found)
        end

        # POST /api/v1/ai/analytics/reports
        def report_create
          report_params = params.require(:report).permit(
            :template_id, parameters: {}
          )

          report = ReportRequest.create!(
            account: current_user.account,
            user: current_user,
            report_type: report_params[:template_id],
            status: "pending",
            parameters: report_params[:parameters] || {},
            requested_at: Time.current
          )

          # Queue background job (lives in worker service)
          GenerateReportJob.perform_later(report.id)

          # Log audit event BEFORE rendering
          log_audit_event("ai.analytics.report.create", report,
            metadata: { template_id: report_params[:template_id] }
          )

          render_success({
            report: serialize_report_request(report)
          }, status: :created)
        rescue StandardError => e
          Rails.logger.error "Failed to create report: #{e.message}"
          render_error("Failed to create report: #{e.message}", status: :unprocessable_content)
        end

        # DELETE /api/v1/ai/analytics/reports/:id
        def report_cancel
          report = current_user.account.report_requests.find(params[:id])

          if report.status == "completed"
            return render_error("Cannot cancel completed report", status: :unprocessable_content)
          end

          if report.status == "failed"
            return render_error("Report already cancelled or failed", status: :unprocessable_content)
          end

          # Mark as failed since 'cancelled' is not in the status constraint
          report.update!(status: "failed")

          render_success({
            message: "Report cancelled successfully",
            report: serialize_report_request(report)
          })

          log_audit_event("ai.analytics.report.cancel", report)
        rescue ActiveRecord::RecordNotFound
          render_error("Report not found", status: :not_found)
        end

        # GET /api/v1/ai/analytics/reports/:id/download
        def report_download
          report = current_user.account.report_requests.find(params[:id])

          unless report.status == "completed" && report.file_path
            return render_error("Report not ready for download", status: :unprocessable_content)
          end

          # Security: Validate file path is within allowed reports directory
          reports_base = Rails.root.join("tmp", "reports").to_s
          # Use File.expand_path to resolve path without requiring file to exist
          expanded_path = File.expand_path(report.file_path)
          unless expanded_path.start_with?(reports_base)
            Rails.logger.error "Attempted access to file outside reports directory: #{report.file_path}"
            return render_error("Invalid report file path", status: :forbidden)
          end

          if report.file_path && File.exist?(report.file_path)
            # Generate filename from report type and timestamp
            filename = report.generate_filename

            # Infer content type from file extension
            content_type = case File.extname(report.file_path).downcase
            when ".pdf" then "application/pdf"
            when ".csv" then "text/csv"
            when ".xlsx" then "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            when ".json" then "application/json"
            else "application/octet-stream"
            end

            send_file report.file_path,
                      filename: filename,
                      type: content_type,
                      disposition: "attachment"
          else
            render_error("Report file not found", status: :not_found)
          end

          log_audit_event("ai.analytics.report.download", report,
            metadata: { file_path: report.file_path }
          )
        rescue ActiveRecord::RecordNotFound
          render_error("Report not found", status: :not_found)
        end

        # GET /api/v1/ai/analytics/reports/templates
        def report_templates
          templates = [
            {
              id: "ai_performance",
              name: "AI Performance Report",
              description: "Comprehensive AI performance analysis with response times and success rates",
              category: "performance",
              formats: [ "pdf", "csv" ],
              parameters: []
            },
            {
              id: "cost_optimization",
              name: "Cost Optimization Report",
              description: "AI cost analysis with optimization recommendations",
              category: "cost",
              formats: [ "pdf", "csv" ],
              parameters: []
            },
            {
              id: "workflow_analytics",
              name: "Workflow Analytics Report",
              description: "Detailed workflow execution analytics and insights",
              category: "workflows",
              formats: [ "pdf", "csv", "xlsx" ],
              parameters: [
                {
                  name: "workflow_id",
                  type: "select",
                  label: "Workflow",
                  required: false
                }
              ]
            },
            {
              id: "agent_performance",
              name: "Agent Performance Report",
              description: "AI agent performance metrics and comparisons",
              category: "agents",
              formats: [ "pdf", "csv" ],
              parameters: []
            },
            {
              id: "executive_summary",
              name: "Executive Summary",
              description: "High-level AI orchestration metrics for executives",
              category: "executive",
              formats: [ "pdf" ],
              parameters: []
            }
          ]

          render_success({
            templates: templates
          })
        end

        # =============================================================================
        # EXPORT
        # =============================================================================

        # POST /api/v1/ai/analytics/export
        def export
          format = params[:format] || "json"
          export_type = params[:export_type] || "dashboard"

          unless %w[json csv xlsx].include?(format)
            return render_error("Invalid export format", status: :bad_request)
          end

          exported_data = generate_export_data(export_type, format)

          # Log audit event BEFORE rendering
          log_audit_event("ai.analytics.export", current_user.account,
            metadata: { format: format, export_type: export_type }
          ) if current_user

          case format
          when "json"
            render_success(exported_data)
          when "csv"
            send_data exported_data,
                      filename: "analytics_#{export_type}_#{Date.current.strftime('%Y%m%d')}.csv",
                      type: "text/csv",
                      disposition: "attachment"
          when "xlsx"
            send_data exported_data,
                      filename: "analytics_#{export_type}_#{Date.current.strftime('%Y%m%d')}.xlsx",
                      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                      disposition: "attachment"
          end
        rescue StandardError => e
          Rails.logger.error "Analytics export failed: #{e.message}"
          render_error("Export failed", status: :internal_server_error)
        end

        private

        # =============================================================================
        # AUTHORIZATION
        # =============================================================================

        def validate_permissions
          # Skip for workers
          return if current_worker

          case action_name
          when "dashboard", "overview", "metrics", "real_time"
            require_permission("ai.analytics.read")
          when "cost_analysis", "performance_analysis"
            require_permission("ai.analytics.read")
          when "insights", "recommendations"
            require_permission("ai.analytics.read")
          when "workflow_analytics", "agent_analytics"
            require_permission("ai.analytics.read")
          when "reports_index", "report_show", "report_templates"
            require_permission("ai.analytics.read")
          when "report_create"
            require_permission("ai.analytics.create")
          when "report_cancel"
            require_permission("ai.analytics.manage")
          when "report_download", "export"
            require_permission("ai.analytics.export")
          end
        end

        # =============================================================================
        # PARAMETER HANDLING
        # =============================================================================

        def set_time_range
          range_param = params[:time_range]

          @time_range = case range_param
          when "1h" then 1.hour
          when "24h", "1d" then 1.day
          when "7d", "1w" then 1.week
          when "30d", "1m" then 30.days
          when "90d", "3m" then 90.days
          when "1y" then 1.year
          else 30.days
          end
        end

        def set_account_scope
          # Workers use their own account scope
          if current_worker
            @account_scope = current_worker.account # nil for system workers (global access)
            return
          end

          # Global analytics permission allows cross-account analytics
          if current_user.has_permission?("ai.analytics.global") && params[:account_id].blank?
            @account_scope = nil # Global analytics
          elsif params[:account_id].present? && current_user.has_permission?("ai.analytics.global")
            @account_scope = Account.find(params[:account_id])
          else
            @account_scope = current_user.account
          end
        end

        def time_range_info
          {
            start: @time_range.ago.iso8601,
            end: Time.current.iso8601,
            period: params[:time_range] || "30d",
            seconds: @time_range.to_i
          }
        end

        # =============================================================================
        # DASHBOARD ANALYTICS
        # =============================================================================

        def generate_dashboard_analytics
          {
            summary: generate_summary_metrics,
            workflows: workflow_dashboard_metrics,
            agents: agent_dashboard_metrics,
            providers: provider_dashboard_metrics,
            costs: cost_dashboard_metrics,
            performance: performance_dashboard_metrics,
            trends: generate_trend_data
          }
        end

        def generate_summary_metrics
          account = @account_scope || current_user&.account
          workflows = account.ai_workflows
          agents = account.ai_agents
          runs = ::Ai::WorkflowRun.where(workflow: workflows)
                             .where("created_at >= ?", @time_range.ago)

          {
            total_workflows: workflows.count,
            active_workflows: workflows.where(is_active: true).count,
            total_agents: agents.count,
            total_executions: runs.count,
            successful_executions: runs.where(status: "completed").count,
            failed_executions: runs.where(status: "failed").count,
            success_rate: calculate_success_rate(runs),
            total_cost: runs.sum(:total_cost) || 0.0,
            average_execution_time: runs.where(status: "completed").average(:duration_ms)&.to_f || 0
          }
        end

        def generate_quick_stats
          account = @account_scope || current_user&.account
          workflows = account.ai_workflows
          runs = ::Ai::WorkflowRun.where(workflow: workflows)
                             .where("created_at >= ?", 24.hours.ago)

          {
            executions_24h: runs.count,
            success_rate_24h: calculate_success_rate(runs),
            cost_24h: runs.sum(:total_cost) || 0.0,
            active_runs: ::Ai::WorkflowRun.where(workflow: workflows)
                                     .where(status: %w[initializing running waiting_approval])
                                     .count
          }
        end

        def generate_trend_data
          account = @account_scope || current_user&.account
          daily_metrics = []
          (0..29).each do |days_ago|
            date = days_ago.days.ago.to_date
            runs = ::Ai::WorkflowRun.where(workflow: account.ai_workflows)
                               .where("DATE(created_at) = ?", date)

            daily_metrics << {
              date: date.iso8601,
              executions: runs.count,
              successful: runs.where(status: "completed").count,
              failed: runs.where(status: "failed").count,
              cost: runs.sum(:total_cost) || 0.0
            }
          end

          daily_metrics.reverse
        end

        def generate_highlights
          account = @account_scope || current_user&.account
          workflows = account.ai_workflows
          runs = ::Ai::WorkflowRun.where(workflow: workflows)
                             .where("created_at >= ?", @time_range.ago)

          highlights = []

          # High success rate
          success_rate = calculate_success_rate(runs)
          if success_rate >= 95
            highlights << {
              type: "positive",
              title: "Excellent Success Rate",
              description: "#{success_rate.round(1)}% of executions completed successfully",
              metric: success_rate
            }
          end

          # Cost efficiency
          avg_cost = runs.average(:total_cost)&.to_f || 0
          if avg_cost < 0.10
            highlights << {
              type: "positive",
              title: "Cost Efficient",
              description: "Average execution cost: $#{avg_cost.round(4)}",
              metric: avg_cost
            }
          end

          # Performance
          avg_time = runs.where(status: "completed").average(:duration_ms)&.to_f || 0
          if avg_time < 30000 # 30 seconds
            highlights << {
              type: "positive",
              title: "Fast Execution",
              description: "Average execution time: #{(avg_time / 1000).round(1)}s",
              metric: avg_time
            }
          end

          highlights
        end

        # =============================================================================
        # METRICS HELPERS
        # =============================================================================

        def workflow_metrics
          account = @account_scope || current_user&.account
          workflows = account.ai_workflows
          {
            total: workflows.count,
            active: workflows.where(is_active: true).count,
            inactive: workflows.where(is_active: false).count
          }
        end

        def agent_metrics
          account = @account_scope || current_user&.account
          agents = account.ai_agents
          {
            total: agents.count,
            active: agents.where(status: "active").count,
            by_provider: agents.group(:ai_provider_id).count
          }
        end

        def provider_metrics
          account = @account_scope || current_user&.account
          providers = account.ai_providers
          {
            total: providers.count,
            active: providers.where(is_active: true).count
          }
        end

        def execution_metrics
          account = @account_scope || current_user&.account
          runs = ::Ai::WorkflowRun.where(workflow: account.ai_workflows)
                             .where("created_at >= ?", @time_range.ago)

          {
            total: runs.count,
            completed: runs.where(status: "completed").count,
            failed: runs.where(status: "failed").count,
            running: runs.where(status: %w[initializing running waiting_approval]).count,
            success_rate: calculate_success_rate(runs)
          }
        end

        def performance_metrics_data
          account = @account_scope || current_user&.account
          runs = ::Ai::WorkflowRun.where(workflow: account.ai_workflows)
                             .where("created_at >= ?", @time_range.ago)
                             .where(status: "completed")

          {
            average_duration_ms: runs.average(:duration_ms)&.to_f || 0,
            median_duration_ms: calculate_median_duration(runs),
            p95_duration_ms: calculate_p95_duration(runs)
          }
        end

        def workflow_dashboard_metrics
          account = @account_scope || current_user&.account
          workflows = account.ai_workflows.limit(10)

          workflows.map do |workflow|
            runs = workflow.runs.where("created_at >= ?", @time_range.ago)
            {
              id: workflow.id,
              name: workflow.name,
              executions: runs.count,
              success_rate: calculate_success_rate(runs),
              average_duration: runs.where(status: "completed").average(:duration_ms)&.to_f || 0,
              total_cost: runs.sum(:total_cost) || 0.0
            }
          end
        end

        def agent_dashboard_metrics
          account = @account_scope || current_user&.account
          agents = account.ai_agents.limit(10)

          agents.map do |agent|
            executions = agent.executions.where("created_at >= ?", @time_range.ago)
            {
              id: agent.id,
              name: agent.name,
              executions: executions.count,
              success_rate: calculate_success_rate(executions),
              average_response_time: executions.where(status: "completed").average(:duration_ms)&.to_f || 0,
              total_cost: executions.sum(:cost_usd) || 0.0
            }
          end
        end

        def provider_dashboard_metrics
          account = @account_scope || current_user&.account
          providers = account.ai_providers

          providers.map do |provider|
            executions = ::Ai::AgentExecution.where(ai_agent: ::Ai::Agent.where(provider: provider))
                                        .where("created_at >= ?", @time_range.ago)

            {
              id: provider.id,
              name: provider.name,
              provider_type: provider.provider_type,
              executions: executions.count,
              success_rate: calculate_success_rate(executions),
              total_cost: executions.sum(:cost_usd) || 0.0
            }
          end
        end

        def cost_dashboard_metrics
          account = @account_scope || current_user&.account
          runs = ::Ai::WorkflowRun.where(workflow: account.ai_workflows)
                             .where("created_at >= ?", @time_range.ago)

          {
            total_cost: runs.sum(:total_cost) || 0.0,
            average_cost_per_execution: runs.average(:total_cost)&.to_f || 0,
            cost_trend: calculate_cost_trend_simple(runs)
          }
        end

        def performance_dashboard_metrics
          account = @account_scope || current_user&.account
          runs = ::Ai::WorkflowRun.where(workflow: account.ai_workflows)
                             .where("created_at >= ?", @time_range.ago)

          {
            success_rate: calculate_success_rate(runs),
            average_duration: runs.where(status: "completed").average(:duration_ms)&.to_f || 0,
            throughput: runs.count.to_f / (@time_range.to_f / 1.hour)
          }
        end

        # =============================================================================
        # REAL-TIME METRICS
        # =============================================================================

        def generate_real_time_metrics
          account = @account_scope || current_user&.account
          workflows = account.ai_workflows
          runs = ::Ai::WorkflowRun.where(workflow: workflows)
                             .where("created_at >= ?", 1.hour.ago)

          {
            active_executions: ::Ai::WorkflowRun.where(workflow: workflows)
                                           .where(status: %w[initializing running waiting_approval])
                                           .count,
            recent_executions: runs.count,
            success_rate: calculate_success_rate(runs),
            average_response_time: runs.where(status: "completed").average(:duration_ms)&.to_f || 0,
            cost_last_hour: runs.sum(:total_cost) || 0.0,
            errors_last_hour: runs.where(status: "failed").count
          }
        end

        # =============================================================================
        # COST ANALYSIS
        # =============================================================================

        def calculate_total_cost
          account = @account_scope || current_user&.account
          (::Ai::WorkflowRun.where(workflow: account.ai_workflows)
                       .where("created_at >= ?", @time_range.ago)
                       .sum(:total_cost) || 0.0).to_f
        end

        def calculate_cost_trend
          account = @account_scope || current_user&.account
          # Calculate daily costs
          daily_costs = []
          (0..29).each do |days_ago|
            date = days_ago.days.ago.to_date
            cost = ::Ai::WorkflowRun.where(workflow: account.ai_workflows)
                               .where("DATE(created_at) = ?", date)
                               .sum(:total_cost) || 0.0

            daily_costs << {
              date: date.iso8601,
              cost: cost
            }
          end

          daily_costs.reverse
        end

        def cost_breakdown_by_provider
          account = @account_scope || current_user&.account
          ::Ai::AgentExecution.joins(agent: :provider)
                         .where(ai_agents: { account_id: account.id })
                         .where("ai_agent_executions.created_at >= ?", @time_range.ago)
                         .group("ai_providers.id", "ai_providers.name")
                         .sum(:cost_usd)
                         .map { |k, v| { provider: k[1], cost: v } }
        end

        def cost_breakdown_by_agent
          account = @account_scope || current_user&.account
          ::Ai::AgentExecution.joins(:agent)
                         .where(ai_agents: { account_id: account.id })
                         .where("ai_agent_executions.created_at >= ?", @time_range.ago)
                         .group("ai_agents.id", "ai_agents.name")
                         .sum(:cost_usd)
                         .map { |k, v| { agent: k[1], cost: v } }
                         .sort_by { |h| -h[:cost] }
                         .first(10)
        end

        def cost_breakdown_by_workflow
          account = @account_scope || current_user&.account
          ::Ai::WorkflowRun.joins(:workflow)
                      .where(ai_workflows: { account_id: account.id })
                      .where("ai_workflow_runs.created_at >= ?", @time_range.ago)
                      .group("ai_workflows.id", "ai_workflows.name")
                      .sum(:total_cost)
                      .map { |k, v| { workflow: k[1], cost: v } }
                      .sort_by { |h| -h[:cost] }
                      .first(10)
        end

        def estimate_cost_savings
          # Estimate potential savings from optimization
          total_cost = calculate_total_cost
          {
            current_cost: total_cost,
            potential_savings: total_cost * 0.20, # Estimate 20% savings
            optimization_areas: [
              "Provider selection optimization",
              "Caching frequently used results",
              "Batch processing similar requests"
            ]
          }
        end

        def generate_budget_forecast
          daily_average = calculate_total_cost / (@time_range.to_f / 1.day)

          {
            daily_average: daily_average,
            weekly_forecast: daily_average * 7,
            monthly_forecast: daily_average * 30,
            yearly_forecast: daily_average * 365
          }
        end

        # =============================================================================
        # PERFORMANCE ANALYSIS
        # =============================================================================

        def analyze_response_times
          account = @account_scope || current_user&.account
          runs = ::Ai::WorkflowRun.where(workflow: account.ai_workflows)
                             .where("created_at >= ?", @time_range.ago)
                             .where(status: "completed")

          {
            average_ms: runs.average(:duration_ms)&.to_f || 0,
            median_ms: calculate_median_duration(runs),
            p95_ms: calculate_p95_duration(runs),
            min_ms: runs.minimum(:duration_ms) || 0,
            max_ms: runs.maximum(:duration_ms) || 0
          }
        end

        def analyze_success_rates
          account = @account_scope || current_user&.account
          runs = ::Ai::WorkflowRun.where(workflow: account.ai_workflows)
                             .where("created_at >= ?", @time_range.ago)

          total = runs.count
          successful = runs.where(status: "completed").count

          {
            overall_rate: calculate_success_rate(runs),
            total_executions: total,
            successful_executions: successful,
            failed_executions: total - successful
          }
        end

        def analyze_throughput
          account = @account_scope || current_user&.account
          runs = ::Ai::WorkflowRun.where(workflow: account.ai_workflows)
                             .where("created_at >= ?", @time_range.ago)

          hours = @time_range.to_f / 1.hour

          {
            total_executions: runs.count,
            executions_per_hour: runs.count.to_f / hours,
            executions_per_day: runs.count.to_f / (hours / 24)
          }
        end

        def analyze_error_rates
          account = @account_scope || current_user&.account
          runs = ::Ai::WorkflowRun.where(workflow: account.ai_workflows)
                             .where("created_at >= ?", @time_range.ago)

          total = runs.count
          failed = runs.where(status: "failed").count

          {
            error_rate: total > 0 ? (failed.to_f / total * 100).round(2) : 0,
            total_errors: failed,
            common_errors: identify_common_errors(runs)
          }
        end

        def analyze_resource_utilization
          account = @account_scope || current_user&.account
          {
            active_workflows: account.ai_workflows.where(is_active: true).count,
            active_agents: account.ai_agents.where(status: "active").count,
            running_executions: ::Ai::WorkflowRun.where(workflow: account.ai_workflows)
                                            .where(status: %w[initializing running waiting_approval])
                                            .count
          }
        end

        def identify_bottlenecks
          account = @account_scope || current_user&.account
          # Identify slow workflows
          slow_workflows = ::Ai::WorkflowRun.joins(:workflow)
                                       .where(ai_workflows: { account_id: account.id })
                                       .where("ai_workflow_runs.created_at >= ?", @time_range.ago)
                                       .where(status: "completed")
                                       .group("ai_workflows.id", "ai_workflows.name")
                                       .average(:duration_ms)
                                       .select { |_, avg| avg.to_f > 60000 } # > 1 minute
                                       .map { |k, v| { workflow: k[1], average_duration_ms: v.to_f.round(2) } }

          {
            slow_workflows: slow_workflows,
            recommendations: slow_workflows.any? ? [ "Consider optimizing slow workflows", "Review parallel execution options" ] : []
          }
        end

        # =============================================================================
        # RECOMMENDATIONS
        # =============================================================================

        def generate_optimization_recommendations
          account = @account_scope || current_user&.account
          runs = ::Ai::WorkflowRun.where(workflow: account.ai_workflows)
                             .where("created_at >= ?", @time_range.ago)

          recommendations = []

          # Cost optimization
          expensive_workflows = cost_breakdown_by_workflow.select { |w| w[:cost].to_f > 10.0 }
          if expensive_workflows.any?
            recommendations << {
              type: "cost_optimization",
              priority: "high",
              title: "Optimize High-Cost Workflows",
              description: "#{expensive_workflows.size} workflows are generating high costs",
              action: "Review provider selection and optimize configurations",
              potential_savings: expensive_workflows.sum { |w| w[:cost].to_f } * 0.3,
              affected_workflows: expensive_workflows.first(3).map { |w| w[:workflow] }
            }
          end

          # Performance optimization
          slow_workflows = identify_bottlenecks[:slow_workflows]
          if slow_workflows.any?
            recommendations << {
              type: "performance_optimization",
              priority: "medium",
              title: "Optimize Slow Workflows",
              description: "#{slow_workflows.size} workflows have slow execution times",
              action: "Consider parallel execution and caching strategies",
              potential_improvement: "40-60% faster execution",
              affected_workflows: slow_workflows.first(3).map { |w| w[:workflow] }
            }
          end

          # Reliability improvement
          error_rate = analyze_error_rates[:error_rate]
          if error_rate > 5.0
            recommendations << {
              type: "reliability_improvement",
              priority: "high",
              title: "Reduce Error Rate",
              description: "Current error rate is #{error_rate.round(1)}% (target: <5%)",
              action: "Implement better error handling and retry mechanisms",
              potential_improvement: "Reduce error rate to under 3%",
              current_error_rate: error_rate
            }
          end

          recommendations
        end

        # =============================================================================
        # WORKFLOW/AGENT SPECIFIC ANALYTICS
        # =============================================================================

        def analyze_workflow_runs(workflow)
          runs = workflow.runs.where("created_at >= ?", @time_range.ago)

          {
            total: runs.count,
            completed: runs.where(status: "completed").count,
            failed: runs.where(status: "failed").count,
            running: runs.where(status: %w[initializing running waiting_approval]).count
          }
        end

        def analyze_workflow_performance(workflow)
          runs = workflow.runs.where("created_at >= ?", @time_range.ago)
                        .where(status: "completed")

          {
            average_duration_ms: runs.average(:duration_ms)&.to_f || 0,
            median_duration_ms: calculate_median_duration(runs),
            min_duration_ms: runs.minimum(:duration_ms) || 0,
            max_duration_ms: runs.maximum(:duration_ms) || 0
          }
        end

        def analyze_workflow_costs(workflow)
          runs = workflow.runs.where("created_at >= ?", @time_range.ago)

          {
            total_cost: runs.sum(:total_cost) || 0.0,
            average_cost: runs.average(:total_cost)&.to_f || 0,
            cost_trend: calculate_cost_trend_simple(runs)
          }
        end

        def calculate_workflow_success_rate(workflow)
          runs = workflow.runs.where("created_at >= ?", @time_range.ago)
          calculate_success_rate(runs)
        end

        def calculate_workflow_average_duration(workflow)
          workflow.runs.where("created_at >= ?", @time_range.ago)
                                  .where(status: "completed")
                                  .average(:duration_ms)&.to_f || 0
        end

        def analyze_node_performance(workflow)
          # Analyze individual node performance
          []
        end

        def analyze_agent_executions(agent)
          executions = agent.executions.where("created_at >= ?", @time_range.ago)

          {
            total: executions.count,
            completed: executions.where(status: "completed").count,
            failed: executions.where(status: "failed").count
          }
        end

        def analyze_agent_performance(agent)
          executions = agent.executions.where("created_at >= ?", @time_range.ago)
                                                .where(status: "completed")

          {
            average_response_time_ms: executions.average(:duration_ms)&.to_f || 0,
            median_response_time_ms: calculate_median_duration(executions)
          }
        end

        def analyze_agent_costs(agent)
          executions = agent.executions.where("created_at >= ?", @time_range.ago)

          {
            total_cost: executions.sum(:cost_usd) || 0.0,
            average_cost: executions.average(:cost_usd)&.to_f || 0
          }
        end

        def calculate_agent_success_rate(agent)
          executions = agent.executions.where("created_at >= ?", @time_range.ago)
          calculate_success_rate(executions)
        end

        def calculate_agent_average_response_time(agent)
          agent.executions.where("created_at >= ?", @time_range.ago)
                                  .where(status: "completed")
                                  .average(:duration_ms)&.to_f || 0
        end

        # =============================================================================
        # EXPORT
        # =============================================================================

        def generate_export_data(export_type, format)
          case export_type
          when "dashboard"
            data = generate_dashboard_analytics
          when "cost_analysis"
            data = {
              total_cost: calculate_total_cost,
              cost_trend: calculate_cost_trend,
              cost_by_provider: cost_breakdown_by_provider,
              cost_by_workflow: cost_breakdown_by_workflow
            }
          when "performance"
            data = {
              response_times: analyze_response_times,
              success_rates: analyze_success_rates,
              throughput: analyze_throughput
            }
          else
            data = generate_dashboard_analytics
          end

          case format
          when "json"
            data.to_json
          when "csv"
            generate_csv_export(data)
          when "xlsx"
            generate_xlsx_export(data)
          end
        end

        def generate_csv_export(data)
          require "csv"

          CSV.generate(headers: true) do |csv|
            csv << [ "Metric", "Value" ]
            flatten_hash(data).each do |key, value|
              csv << [ key, value ]
            end
          end
        end

        def generate_xlsx_export(_data)
          # Placeholder for Excel export
          "Excel export not yet implemented"
        end

        # =============================================================================
        # SERIALIZATION
        # =============================================================================

        def serialize_workflow_summary(workflow)
          {
            id: workflow.id,
            name: workflow.name,
            status: workflow.is_active ? "active" : "inactive",
            created_at: workflow.created_at.iso8601
          }
        end

        def serialize_agent_summary(agent)
          {
            id: agent.id,
            name: agent.name,
            status: agent.status,
            provider: agent.provider.name,
            created_at: agent.created_at.iso8601
          }
        end

        def serialize_report_request(report)
          {
            id: report.id,
            type: report.report_type,
            status: report.status,
            requested_at: report.created_at.iso8601,
            completed_at: report.completed_at&.iso8601
          }
        end

        def serialize_report_request_detail(report)
          serialize_report_request(report).merge(
            file_path: report.file_path,
            file_size_bytes: report.file_size_bytes,
            error_message: report.error_message,
            parameters: report.parameters
          )
        end

        # =============================================================================
        # CALCULATION HELPERS
        # =============================================================================

        def calculate_success_rate(collection)
          total = collection.count
          return 0.0 if total.zero?

          successful = collection.where(status: "completed").count
          (successful.to_f / total * 100).round(2)
        end

        def calculate_median_duration(runs)
          durations = runs.pluck(:duration_ms).compact.sort
          return 0 if durations.empty?

          mid = durations.length / 2
          durations.length.odd? ? durations[mid] : (durations[mid - 1] + durations[mid]) / 2.0
        end

        def calculate_p95_duration(runs)
          durations = runs.pluck(:duration_ms).compact.sort
          return 0 if durations.empty?

          index = (durations.length * 0.95).ceil - 1
          durations[index]
        end

        def calculate_cost_trend_simple(runs)
          if runs.count > 10
            recent = runs.order(created_at: :desc).limit(runs.count / 2).sum(:total_cost)
            older = runs.order(created_at: :asc).limit(runs.count / 2).sum(:total_cost)

            return "stable" if recent == older
            recent > older ? "increasing" : "decreasing"
          else
            "stable"
          end
        end

        def identify_common_errors(runs)
          runs.where(status: "failed")
              .group(:error_details)
              .count
              .sort_by { |_, count| -count }
              .first(5)
              .map { |error, count| { error: error, count: count } }
        end

        def pagination_data(collection)
          {
            current_page: collection.current_page,
            per_page: collection.limit_value,
            total_pages: collection.total_pages,
            total_count: collection.total_count
          }
        end

        def flatten_hash(hash, parent_key = "", result = {})
          hash.each do |key, value|
            new_key = parent_key.empty? ? key.to_s : "#{parent_key}.#{key}"
            if value.is_a?(Hash)
              flatten_hash(value, new_key, result)
            else
              result[new_key] = value
            end
          end
          result
        end
      end
    end
  end
end
