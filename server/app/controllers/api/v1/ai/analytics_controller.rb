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
# - Delegates to Ai::Analytics::* services for business logic
#
module Api
  module V1
    module Ai
      class AnalyticsController < ApplicationController
        include AuditLogging

        before_action :validate_permissions
        before_action :set_time_range, only: %i[dashboard overview metrics cost_analysis performance_analysis insights recommendations workflow_analytics agent_analytics export]
        before_action :set_account_scope

        # =============================================================================
        # DASHBOARD & OVERVIEW
        # =============================================================================

        # GET /api/v1/ai/analytics/dashboard
        def dashboard
          render_success({
            dashboard: dashboard_service.generate,
            time_range: time_range_info,
            generated_at: Time.current.iso8601
          })

          log_audit_event("ai.analytics.dashboard", current_user.account) if current_user
        end

        # GET /api/v1/ai/analytics/overview
        def overview
          render_success({
            overview: {
              summary: dashboard_service.generate_summary_metrics,
              trends: dashboard_service.generate_trend_data,
              highlights: dashboard_service.generate_highlights,
              quick_stats: dashboard_service.generate_quick_stats
            },
            timestamp: Time.current.iso8601
          })
        end

        # =============================================================================
        # METRICS & ANALYTICS
        # =============================================================================

        # GET /api/v1/ai/analytics/metrics
        def metrics
          render_success({
            metrics: metrics_service.all_metrics,
            time_range_seconds: @time_range.to_i,
            timestamp: Time.current.iso8601
          })
        end

        # GET /api/v1/ai/analytics/real_time
        def real_time
          render_success({
            metrics: dashboard_service.real_time_metrics,
            updated_at: Time.current.iso8601,
            refresh_interval: 30
          })
        end

        # GET /api/v1/ai/analytics/cost_analysis
        def cost_analysis
          render_success({
            cost_analysis: cost_service.full_analysis,
            time_range: time_range_info,
            timestamp: Time.current.iso8601
          })

          log_audit_event("ai.analytics.cost_analysis", current_user.account) if current_user
        end

        # GET /api/v1/ai/analytics/performance_analysis
        def performance_analysis
          render_success({
            performance_analysis: performance_service.full_analysis,
            time_range: time_range_info,
            timestamp: Time.current.iso8601
          })
        end

        # =============================================================================
        # INSIGHTS & RECOMMENDATIONS
        # =============================================================================

        # GET /api/v1/ai/analytics/insights
        def insights
          render_success({
            insights: generate_aggregated_insights,
            generated_at: Time.current.iso8601,
            time_range: time_range_info
          })

          log_audit_event("ai.analytics.insights", current_user.account) if current_user
        end

        # GET /api/v1/ai/analytics/recommendations
        def recommendations
          render_success({
            recommendations: generate_optimization_recommendations,
            generated_at: Time.current.iso8601,
            time_range: time_range_info
          })
        end

        # =============================================================================
        # WORKFLOW/AGENT-SPECIFIC ANALYTICS
        # =============================================================================

        # GET /api/v1/ai/analytics/workflows/:workflow_id
        def workflow_analytics
          workflow = current_user.account.ai_workflows.find(params[:workflow_id])

          render_success({
            workflow_analytics: metrics_service.workflow_specific_metrics(workflow),
            time_range: time_range_info,
            timestamp: Time.current.iso8601
          })
        rescue ActiveRecord::RecordNotFound
          render_error("Workflow not found", status: :not_found)
        end

        # GET /api/v1/ai/analytics/agents/:agent_id
        def agent_analytics
          agent = current_user.account.ai_agents.find(params[:agent_id])

          render_success({
            agent_analytics: metrics_service.agent_specific_metrics(agent),
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

          render_success({ report: serialize_report_request_detail(report) })
        rescue ActiveRecord::RecordNotFound
          render_error("Report not found", status: :not_found)
        end

        # POST /api/v1/ai/analytics/reports
        def report_create
          report_params = params.require(:report).permit(:template_id, parameters: {})

          report = ReportRequest.create!(
            account: current_user.account,
            user: current_user,
            report_type: report_params[:template_id],
            status: "pending",
            parameters: report_params[:parameters] || {},
            requested_at: Time.current
          )

          GenerateReportJob.perform_later(report.id)

          log_audit_event("ai.analytics.report.create", report,
                          metadata: { template_id: report_params[:template_id] })

          render_success({ report: serialize_report_request(report) }, status: :created)
        rescue StandardError => e
          Rails.logger.error "Failed to create report: #{e.message}"
          render_error("Failed to create report: #{e.message}", status: :unprocessable_content)
        end

        # DELETE /api/v1/ai/analytics/reports/:id
        def report_cancel
          report = current_user.account.report_requests.find(params[:id])

          return render_error("Cannot cancel completed report", status: :unprocessable_content) if report.status == "completed"
          return render_error("Report already cancelled or failed", status: :unprocessable_content) if report.status == "failed"

          report.update!(status: "failed")

          log_audit_event("ai.analytics.report.cancel", report)
          render_success({ message: "Report cancelled successfully", report: serialize_report_request(report) })
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
          expanded_path = File.expand_path(report.file_path)
          unless expanded_path.start_with?(reports_base)
            Rails.logger.error "Attempted access to file outside reports directory: #{report.file_path}"
            return render_error("Invalid report file path", status: :forbidden)
          end

          if report.file_path && File.exist?(report.file_path)
            send_file report.file_path,
                      filename: report.generate_filename,
                      type: content_type_for_file(report.file_path),
                      disposition: "attachment"

            log_audit_event("ai.analytics.report.download", report, metadata: { file_path: report.file_path })
          else
            render_error("Report file not found", status: :not_found)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Report not found", status: :not_found)
        end

        # GET /api/v1/ai/analytics/reports/templates
        def report_templates
          render_success({ templates: report_service.available_reports })
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

          report_data = generate_report_for_export(export_type)
          exported = report_service.export(report: report_data, format: format.to_sym)

          log_audit_event("ai.analytics.export", current_user.account,
                          metadata: { format: format, export_type: export_type }) if current_user

          case format
          when "json"
            render_success(report_data)
          when "csv", "xlsx"
            send_data exported,
                      filename: "analytics_#{export_type}_#{Date.current.strftime('%Y%m%d')}.#{format}",
                      type: format == "csv" ? "text/csv" : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                      disposition: "attachment"
          end
        rescue StandardError => e
          Rails.logger.error "Analytics export failed: #{e.message}"
          render_error("Export failed", status: :internal_server_error)
        end

        private

        # =============================================================================
        # SERVICE ACCESSORS
        # =============================================================================

        def dashboard_service
          @dashboard_service ||= ::Ai::Analytics::DashboardService.new(
            account: account_for_analytics,
            time_range: @time_range
          )
        end

        def metrics_service
          @metrics_service ||= ::Ai::Analytics::MetricsService.new(
            account: account_for_analytics,
            time_range: @time_range
          )
        end

        def cost_service
          @cost_service ||= ::Ai::Analytics::CostAnalysisService.new(
            account: account_for_analytics,
            time_range: @time_range
          )
        end

        def performance_service
          @performance_service ||= ::Ai::Analytics::PerformanceAnalysisService.new(
            account: account_for_analytics,
            time_range: @time_range
          )
        end

        def report_service
          @report_service ||= ::Ai::Analytics::ReportService.new(
            account: account_for_analytics,
            user: current_user,
            time_range: @time_range
          )
        end

        def account_for_analytics
          @account_scope || current_user&.account
        end

        # =============================================================================
        # AUTHORIZATION
        # =============================================================================

        def validate_permissions
          return if current_worker

          case action_name
          when "dashboard", "overview", "metrics", "real_time",
               "cost_analysis", "performance_analysis",
               "insights", "recommendations",
               "workflow_analytics", "agent_analytics",
               "reports_index", "report_show", "report_templates"
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
          @time_range = case params[:time_range]
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
          if current_worker
            @account_scope = current_worker.account
            return
          end

          if current_user.has_permission?("ai.analytics.global") && params[:account_id].blank?
            @account_scope = nil
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
        # INSIGHTS (aggregated from multiple services)
        # =============================================================================

        def generate_aggregated_insights
          cache_key = "ai:analytics:insights:#{account_for_analytics&.id}:#{@time_range.to_i}"

          Rails.cache.fetch(cache_key, expires_in: 1.hour) do
            {
              performance_insights: performance_service.analyze_performance_trends,
              cost_insights: cost_service.full_analysis.slice(:cost_trend, :optimization_potential, :anomalies),
              usage_insights: {
                summary: dashboard_service.generate_summary_metrics,
                trends: dashboard_service.generate_trend_data
              },
              recommendations: generate_optimization_recommendations
            }
          end
        end

        # =============================================================================
        # RECOMMENDATIONS (uses multiple services)
        # =============================================================================

        def generate_optimization_recommendations
          recommendations = []

          # Cost optimization from cost service
          savings = cost_service.estimate_cost_savings
          if savings[:opportunities].any?
            savings[:opportunities].first(3).each do |opp|
              recommendations << {
                type: "cost_optimization",
                priority: "high",
                title: opp[:recommendation],
                description: "Potential savings: $#{opp[:potential_savings]}",
                action: opp[:recommendation],
                potential_savings: opp[:potential_savings]
              }
            end
          end

          # Performance optimization from performance service
          bottlenecks = performance_service.identify_bottlenecks
          if bottlenecks[:bottlenecks].any?
            recommendations << {
              type: "performance_optimization",
              priority: "medium",
              title: "Optimize Slow Workflows",
              description: "#{bottlenecks[:bottlenecks].size} potential bottlenecks identified",
              action: "Review and optimize slow-running workflows",
              affected_workflows: bottlenecks[:bottlenecks].first(3)
            }
          end

          # Reliability from performance service
          error_analysis = performance_service.analyze_error_rates
          if error_analysis[:error_rate] > 5.0
            recommendations << {
              type: "reliability_improvement",
              priority: "high",
              title: "Reduce Error Rate",
              description: "Current error rate is #{error_analysis[:error_rate].round(1)}% (target: <5%)",
              action: "Implement better error handling and retry mechanisms",
              current_error_rate: error_analysis[:error_rate]
            }
          end

          recommendations
        end

        # =============================================================================
        # EXPORT HELPERS
        # =============================================================================

        def generate_report_for_export(export_type)
          case export_type
          when "dashboard"
            report_service.generate(type: :executive_summary)
          when "cost_analysis"
            report_service.generate(type: :cost_analysis)
          when "performance"
            report_service.generate(type: :performance_analysis)
          else
            report_service.generate(type: :executive_summary)
          end
        end

        def content_type_for_file(file_path)
          case File.extname(file_path).downcase
          when ".pdf" then "application/pdf"
          when ".csv" then "text/csv"
          when ".xlsx" then "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          when ".json" then "application/json"
          else "application/octet-stream"
          end
        end

        # =============================================================================
        # SERIALIZATION
        # =============================================================================

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

        def pagination_data(collection)
          {
            current_page: collection.current_page,
            per_page: collection.limit_value,
            total_pages: collection.total_pages,
            total_count: collection.total_count
          }
        end
      end
    end
  end
end
