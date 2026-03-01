# frozen_string_literal: true

module Api
  module V1
    module Ai
      class AnalyticsReportsController < ApplicationController
        include AuditLogging

        before_action :validate_permissions
        before_action :set_account_scope

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

        private

        def report_service
          @report_service ||= ::Ai::Analytics::ReportService.new(
            account: account_for_analytics, user: current_user, time_range: 30.days
          )
        end

        def account_for_analytics
          @account_scope || current_user&.account
        end

        def validate_permissions
          return if current_worker

          case action_name
          when "reports_index", "report_show", "report_templates"
            require_permission("ai.analytics.read")
          when "report_create"
            require_permission("ai.analytics.create")
          when "report_cancel"
            require_permission("ai.analytics.manage")
          when "report_download"
            require_permission("ai.analytics.export")
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

        def content_type_for_file(file_path)
          case File.extname(file_path).downcase
          when ".pdf" then "application/pdf"
          when ".csv" then "text/csv"
          when ".xlsx" then "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          when ".json" then "application/json"
          else "application/octet-stream"
          end
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
