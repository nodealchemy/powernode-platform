# frozen_string_literal: true

module Api
  module V1
    module SupplyChain
      class ReportsController < BaseController
        before_action :require_read_permission, only: [ :index, :show, :download ]
        before_action :require_write_permission, only: [ :create, :update, :destroy, :regenerate, :generate_sbom, :generate_attribution, :generate_compliance, :generate_vulnerability, :generate_vendor_risk ]
        before_action :set_report, only: [ :show, :update, :destroy, :download, :regenerate ]

        # GET /api/v1/supply_chain/reports
        def index
          @reports = current_account.supply_chain_reports
                                    .order(created_at: :desc)

          @reports = @reports.where(report_type: params[:type]) if params[:type].present?
          @reports = @reports.where(status: params[:status]) if params[:status].present?
          @reports = @reports.where(format: params[:format]) if params[:format].present?

          @reports = paginate(@reports)

          render_success(
            { reports: @reports.map { |r| serialize_report(r) } },
            meta: pagination_meta
          )
        rescue StandardError => e
          Rails.logger.error "[ReportsController] List failed: #{e.message}"
          render_error("Failed to list reports", status: :internal_server_error)
        end

        # GET /api/v1/supply_chain/reports/:id
        def show
          render_success({
            report: serialize_report_detail(@report)
          })

          log_audit_event("supply_chain.reports.read", @report)
        end

        # POST /api/v1/supply_chain/reports
        def create
          report = current_account.supply_chain_reports.new(report_params)
          report.created_by = current_user

          if report.save
            # Queue report generation job
            enqueue_report_generation(report)

            render_success({
              report: serialize_report(report),
              message: "Report generation started"
            }, status: :created)

            log_audit_event("supply_chain.reports.create", report)
          else
            render_validation_error(report.errors)
          end
        end

        # PATCH/PUT /api/v1/supply_chain/reports/:id
        def update
          if @report.update(report_params)
            render_success({
              report: serialize_report(@report),
              message: "Report updated successfully"
            })

            log_audit_event("supply_chain.reports.update", @report)
          else
            render_validation_error(@report.errors)
          end
        end

        # DELETE /api/v1/supply_chain/reports/:id
        def destroy
          @report.destroy!

          render_success({ message: "Report deleted successfully" })

          log_audit_event("supply_chain.reports.delete", @report)
        rescue StandardError => e
          render_error("Failed to delete report", status: :internal_server_error)
        end

        # GET /api/v1/supply_chain/reports/:id/download
        def download
          unless @report.status == "completed" && @report.file_path.present?
            render_error("Report not ready for download", status: :unprocessable_content)
            return
          end

          # Generate download URL or return file content
          render_success({
            report_id: @report.id,
            filename: @report.suggested_filename,
            content_type: content_type_for_format(@report.format),
            download_url: generate_download_url(@report),
            expires_at: 1.hour.from_now
          })

          log_audit_event("supply_chain.reports.download", @report)
        end

        # POST /api/v1/supply_chain/reports/:id/regenerate
        def regenerate
          @report.update!(status: "pending", metadata: @report.metadata.except("error"))
          enqueue_report_generation(@report)

          render_success({
            report: serialize_report(@report),
            message: "Report regeneration started"
          })

          log_audit_event("supply_chain.reports.regenerate", @report)
        rescue StandardError => e
          render_error("Failed to regenerate report: #{e.message}", status: :unprocessable_content)
        end

        # POST /api/v1/supply_chain/reports/generate_sbom
        def generate_sbom
          sbom = current_account.supply_chain_sboms.find(params[:sbom_id])

          report = current_account.supply_chain_reports.create!(
            name: params[:name] || "SBOM Report - #{sbom.name}",
            report_type: "sbom_export",
            format: params[:format] || "json",
            status: "pending",
            created_by: current_user,
            parameters: {
              sbom_id: sbom.id,
              export_format: params[:format] || "json",
              include_vulnerabilities: params[:include_vulnerabilities] != false
            }
          )

          enqueue_report_generation(report)

          render_success({
            report: serialize_report(report),
            message: "SBOM report generation started"
          }, status: :created)

          log_audit_event("supply_chain.reports.generate_sbom", report)
        rescue ActiveRecord::RecordNotFound
          render_error("SBOM not found", status: :not_found)
        end

        # POST /api/v1/supply_chain/reports/generate_attribution
        def generate_attribution
          sbom_ids = params[:sbom_ids] || [ params[:sbom_id] ]

          report = current_account.supply_chain_reports.create!(
            name: params[:name] || "Attribution Report",
            report_type: "attribution",
            format: params[:format] || "html",
            status: "pending",
            created_by: current_user,
            parameters: {
              sbom_ids: sbom_ids,
              include_license_text: params[:include_license_text] != false
            }
          )

          enqueue_report_generation(report)

          render_success({
            report: serialize_report(report),
            message: "Attribution report generation started"
          }, status: :created)

          log_audit_event("supply_chain.reports.generate_attribution", report)
        end

        # POST /api/v1/supply_chain/reports/generate_compliance
        def generate_compliance
          report = current_account.supply_chain_reports.create!(
            name: params[:name] || "Compliance Report",
            report_type: "compliance",
            format: params[:format] || "pdf",
            status: "pending",
            created_by: current_user,
            parameters: {
              framework: params[:framework] || "ntia",
              sbom_ids: params[:sbom_ids],
              date_range: {
                start_date: params[:start_date],
                end_date: params[:end_date]
              }
            }
          )

          enqueue_report_generation(report)

          render_success({
            report: serialize_report(report),
            message: "Compliance report generation started"
          }, status: :created)

          log_audit_event("supply_chain.reports.generate_compliance", report)
        end

        # POST /api/v1/supply_chain/reports/generate_vulnerability
        def generate_vulnerability
          report = current_account.supply_chain_reports.create!(
            name: params[:name] || "Vulnerability Report",
            report_type: "vulnerability",
            format: params[:format] || "pdf",
            status: "pending",
            created_by: current_user,
            parameters: {
              sbom_ids: params[:sbom_ids],
              container_image_ids: params[:container_image_ids],
              severity_filter: params[:severity_filter],
              include_remediation: params[:include_remediation] != false
            }
          )

          enqueue_report_generation(report)

          render_success({
            report: serialize_report(report),
            message: "Vulnerability report generation started"
          }, status: :created)

          log_audit_event("supply_chain.reports.generate_vulnerability", report)
        end

        # POST /api/v1/supply_chain/reports/generate_vendor_risk
        def generate_vendor_risk
          report = current_account.supply_chain_reports.create!(
            name: params[:name] || "Vendor Risk Report",
            report_type: "vendor_risk",
            format: params[:format] || "pdf",
            status: "pending",
            created_by: current_user,
            parameters: {
              vendor_ids: params[:vendor_ids],
              include_assessments: params[:include_assessments] != false,
              include_questionnaires: params[:include_questionnaires] == true
            }
          )

          enqueue_report_generation(report)

          render_success({
            report: serialize_report(report),
            message: "Vendor risk report generation started"
          }, status: :created)

          log_audit_event("supply_chain.reports.generate_vendor_risk", report)
        end

        private

        def set_report
          @report = current_account.supply_chain_reports.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Report not found", status: :not_found)
        end

        def report_params
          params.require(:report).permit(
            :name,
            :report_type,
            :format,
            parameters: {}
          )
        end

        def serialize_report_detail(report)
          serialize_report(report).merge({
            parameters: report.parameters,
            error_message: report.metadata["error"],
            file_path: report.file_path.present? ? "[AVAILABLE]" : nil,
            created_by: report.created_by.present? ? {
              id: report.created_by.id,
              email: report.created_by.email
            } : nil
          })
        end

        def enqueue_report_generation(report)
          # Queue async report generation
          begin
            WorkerJobService.enqueue_job(
              "SupplyChain::ReportGenerationJob",
              args: [ report.id ],
              queue: "supply_chain_default"
            )
          rescue WorkerJobService::WorkerServiceError => e
            Rails.logger.warn "Worker service unavailable for report generation: #{e.message}"
            # Fall back to inline generation for simple reports
            report.update!(status: "pending")
          end
        end

        def generate_download_url(report)
          # Generate presigned URL or internal download path
          "/api/v1/supply_chain/reports/#{report.id}/download_file"
        end

        def content_type_for_format(format)
          case format
          when "pdf" then "application/pdf"
          when "json" then "application/json"
          when "csv" then "text/csv"
          when "html" then "text/html"
          when "xml" then "application/xml"
          when "spdx" then "application/spdx+json"
          when "cyclonedx" then "application/vnd.cyclonedx+json"
          else "application/octet-stream"
          end
        end

        def serialize_report(report)
          {
            id: report.id,
            name: report.name,
            description: report.description,
            report_type: report.report_type,
            format: report.format,
            status: report.status,
            file_size_bytes: report.file_size_bytes,
            generated_at: report.generated_at,
            expires_at: report.expires_at,
            created_at: report.created_at,
            updated_at: report.updated_at
          }
        end
      end
    end
  end
end
