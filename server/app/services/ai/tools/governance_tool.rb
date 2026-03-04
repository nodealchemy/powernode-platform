# frozen_string_literal: true

module Ai
  module Tools
    class GovernanceTool < BaseTool
      def self.definition
        { name: "governance", description: "Agent governance monitoring, scanning, and collusion detection", parameters: { type: "object", properties: {} } }
      end

      def self.action_definitions
        {
          "governance_scan" => {
            description: "Run a governance scan on a specific agent or team",
            parameters: { type: "object", properties: {
              agent_id: { type: "string", description: "Agent to scan" },
              team_id: { type: "string", description: "Team to scan" }
            } }
          },
          "list_governance_reports" => {
            description: "List governance reports with optional filters",
            parameters: { type: "object", properties: {
              status: { type: "string" }, severity: { type: "string" },
              agent_id: { type: "string" }, limit: { type: "integer" }
            } }
          },
          "get_governance_report" => {
            description: "Get detailed governance report",
            parameters: { type: "object", required: ["report_id"], properties: { report_id: { type: "string" } } }
          },
          "resolve_governance_report" => {
            description: "Resolve a governance report with a status and notes",
            parameters: { type: "object", required: ["report_id", "resolution_status"], properties: {
              report_id: { type: "string" },
              resolution_status: { type: "string", enum: %w[confirmed dismissed remediated] },
              notes: { type: "string" }
            } }
          },
          "detect_collusion" => {
            description: "Run collusion detection across active agents",
            parameters: { type: "object", properties: {} }
          },
          "governance_dashboard" => {
            description: "Get governance dashboard with summary metrics",
            parameters: { type: "object", properties: {} }
          }
        }
      end

      def call(params)
        case params[:action]
        when "governance_scan" then governance_scan(params)
        when "list_governance_reports" then list_governance_reports(params)
        when "get_governance_report" then get_governance_report(params)
        when "resolve_governance_report" then resolve_governance_report(params)
        when "detect_collusion" then detect_collusion(params)
        when "governance_dashboard" then governance_dashboard(params)
        else error_result("Unknown action: #{params[:action]}")
        end
      end

      private

      def governance_scan(params)
        service = Ai::Governance::MonitorService.new(account: account)
        reports = if params["agent_id"]
          agent = Ai::Agent.find_by(id: params["agent_id"], account: account)
          return error_result("Agent not found") unless agent
          service.scan_agent!(agent: agent, monitor: agent)
        elsif params["team_id"]
          team = Ai::AgentTeam.find_by(id: params["team_id"], account: account)
          return error_result("Team not found") unless team
          service.scan_team!(team: team, monitor: agent)
        else
          return error_result("Specify agent_id or team_id")
        end
        success_result({
          reports: reports.map { |r| r.as_json(only: [:id, :report_type, :severity, :status, :confidence_score]) },
          count: reports.size
        })
      rescue StandardError => e
        error_result("Governance scan failed: #{e.message}")
      end

      def list_governance_reports(params)
        scope = Ai::GovernanceReport.where(account: account)
        scope = scope.where(status: params["status"]) if params["status"]
        scope = scope.where(severity: params["severity"]) if params["severity"]
        scope = scope.for_agent(params["agent_id"]) if params["agent_id"]
        reports = scope.recent.limit((params["limit"] || 20).to_i)
        success_result({
          reports: reports.map { |r| r.as_json(only: [:id, :report_type, :severity, :status, :confidence_score, :subject_agent_id, :created_at]) },
          count: reports.size
        })
      rescue StandardError => e
        error_result("List reports failed: #{e.message}")
      end

      def get_governance_report(params)
        report = Ai::GovernanceReport.find_by(id: params["report_id"], account: account)
        return error_result("Report not found") unless report
        success_result(report.as_json(except: [:updated_at]))
      rescue StandardError => e
        error_result("Get report failed: #{e.message}")
      end

      def resolve_governance_report(params)
        report = Ai::GovernanceReport.find_by(id: params["report_id"], account: account)
        return error_result("Report not found") unless report
        report.resolve!(status: params["resolution_status"], remediation_notes: params["notes"])
        success_result({ report_id: report.id, status: report.status })
      rescue StandardError => e
        error_result("Resolve report failed: #{e.message}")
      end

      def detect_collusion(params)
        service = Ai::Governance::MonitorService.new(account: account)
        indicators = service.detect_collusion!
        success_result({
          indicators: indicators.map { |i| i.as_json(only: [:id, :indicator_type, :correlation_score, :agent_cluster]) },
          count: indicators.size
        })
      rescue StandardError => e
        error_result("Collusion detection failed: #{e.message}")
      end

      def governance_dashboard(params)
        open_reports = Ai::GovernanceReport.where(account: account).open_reports
        collusion = Ai::CollusionIndicator.where(account: account)
          .high_confidence
          .where("created_at >= ?", 30.days.ago)

        success_result({
          open_reports: open_reports.count,
          critical_reports: open_reports.critical.count,
          by_type: open_reports.group(:report_type).count,
          by_severity: open_reports.group(:severity).count,
          collusion_indicators: collusion.count,
          agents_under_investigation: open_reports.distinct.pluck(:subject_agent_id).compact.size
        })
      rescue StandardError => e
        error_result("Dashboard failed: #{e.message}")
      end
    end
  end
end
