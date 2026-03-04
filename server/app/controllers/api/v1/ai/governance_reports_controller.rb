# frozen_string_literal: true

module Api
  module V1
    module Ai
      class GovernanceReportsController < ApplicationController
        before_action :validate_permissions

        # GET /api/v1/ai/governance_reports
        def index
          scope = current_account.ai_governance_reports.recent
          scope = scope.where(report_type: params[:report_type]) if params[:report_type].present?
          scope = scope.where(severity: params[:severity]) if params[:severity].present?
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.for_agent(params[:agent_id]) if params[:agent_id].present?

          reports = scope.includes(:subject_agent, :monitor_agent)
            .page(params[:page]).per(params[:per_page] || 20)

          render_success(
            items: reports.map { |r| serialize_report(r) },
            total: reports.total_count,
            page: reports.current_page,
            per_page: reports.limit_value
          )
        end

        # GET /api/v1/ai/governance_reports/:id
        def show
          report = current_account.ai_governance_reports.find_by(id: params[:id])
          return render_not_found("Governance report") unless report

          render_success(report: serialize_report(report, detailed: true))
        end

        # PUT /api/v1/ai/governance_reports/:id/resolve
        def resolve
          report = current_account.ai_governance_reports.find_by(id: params[:id])
          return render_not_found("Governance report") unless report

          report.resolve!(
            status: params[:resolution_status] || "remediated",
            remediation_notes: params[:notes]
          )

          render_success(report: serialize_report(report))
        rescue StandardError => e
          render_error("Failed to resolve report: #{e.message}", status: :unprocessable_content)
        end

        # GET /api/v1/ai/governance_reports/summary
        def summary
          reports = current_account.ai_governance_reports
          open_reports = reports.open_reports

          render_success(
            summary: {
              total: reports.count,
              open: open_reports.count,
              critical: reports.critical.count,
              by_type: reports.group(:report_type).count,
              by_severity: reports.group(:severity).count,
              by_status: reports.group(:status).count,
              auto_remediated: reports.where(auto_remediated: true).count
            }
          )
        end

        # GET /api/v1/ai/collusion_indicators
        def collusion_indicators
          scope = current_account.ai_collusion_indicators.recent
          scope = scope.by_type(params[:indicator_type]) if params[:indicator_type].present?
          scope = scope.high_confidence if params[:high_confidence] == "true"

          indicators = scope.page(params[:page]).per(params[:per_page] || 20)

          render_success(
            items: indicators.map { |i| serialize_collusion_indicator(i) },
            total: indicators.total_count,
            page: indicators.current_page,
            per_page: indicators.limit_value
          )
        end

        # GET /api/v1/ai/collusion_indicators/summary
        def collusion_summary
          indicators = current_account.ai_collusion_indicators

          render_success(
            summary: {
              total: indicators.count,
              high_confidence: indicators.high_confidence.count,
              by_type: indicators.group(:indicator_type).count,
              avg_correlation: indicators.average(:correlation_score)&.to_f&.round(3) || 0,
              recent_24h: indicators.where("created_at >= ?", 24.hours.ago).count
            }
          )
        end

        private

        def validate_permissions
          authorize_permission!("ai.manage")
        end

        def serialize_report(report, detailed: false)
          data = {
            id: report.id,
            report_type: report.report_type,
            severity: report.severity,
            status: report.status,
            confidence_score: report.confidence_score&.to_f,
            auto_remediated: report.auto_remediated,
            subject_agent: report.subject_agent ? { id: report.subject_agent.id, name: report.subject_agent.name } : nil,
            monitor_agent: report.monitor_agent ? { id: report.monitor_agent.id, name: report.monitor_agent.name } : nil,
            subject_team_id: report.subject_team_id,
            created_at: report.created_at.iso8601,
            updated_at: report.updated_at.iso8601
          }

          if detailed
            data[:evidence] = report.evidence
            data[:recommended_actions] = report.recommended_actions
          end

          data
        end

        def serialize_collusion_indicator(indicator)
          {
            id: indicator.id,
            indicator_type: indicator.indicator_type,
            agent_cluster: indicator.agent_cluster,
            correlation_score: indicator.correlation_score&.to_f,
            evidence_summary: indicator.evidence_summary,
            created_at: indicator.created_at.iso8601
          }
        end
      end
    end
  end
end
