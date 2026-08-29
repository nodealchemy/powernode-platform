# frozen_string_literal: true

module Ai
  module Tools
    class GovernanceTool < BaseTool
      # SECURITY (IMP-6fbfeff384fa): authorization here is per ACTION, not per
      # tool. REQUIRED_PERMISSION was inherited as nil from BaseTool, and
      # McpPlatformToolRegistrar#enforce_permission! opens with
      # `return if required.nil?` — ABOVE the authentication raise and the
      # has_permission? raise. Every action was
      # therefore reachable by any MCP caller with no check at all, including
      # resolve_governance_report, whose REST twin requires ai.governance.manage.
      #
      # Floor: Api::V1::Ai::GovernanceReportsController gates its READ_ACTIONS
      # (index, show, summary, collusion_indicators, collusion_summary) on this,
      # and list/get/dashboard are exactly those reads.
      REQUIRED_PERMISSION = "ai.governance.read"

      # Each entry names the permission the REST twin of that action requires.
      ACTION_PERMISSIONS = {
        # PUT /api/v1/ai/governance_reports/:id/resolve — the controller's sole
        # WRITE_ACTION (governance_reports_controller.rb:11,14). This is the
        # reported hole: resolvable over MCP with no permission at all.
        "resolve_governance_report" => "ai.governance.manage",

        # No user-facing REST twin: the only endpoints that run these are
        # Api::V1::Internal::Ai::GovernanceController#scan_all / #detect_collusion,
        # which are mTLS worker endpoints with no permission string, invoked by
        # AiGovernanceScanJob / AiCollusionDetectionJob. So parity is silent and
        # the choice is ours — and they are WRITES that CREATE the very records
        # resolve_governance_report mutates (MonitorService#create_report, and
        # detect_collusion! writes an Ai::CollusionIndicator plus a
        # "collusion_suspicion" report naming other agents). Leaving them at the
        # read floor would let a member-tier caller manufacture supervisory
        # evidence about agents it can only read. The family's write bar is
        # manage, so these sit with resolve rather than with the reads.
        "governance_scan" => "ai.governance.manage",
        "detect_collusion" => "ai.governance.manage"

        # list_governance_reports, get_governance_report and governance_dashboard
        # stay at the floor on purpose: their twins are the controller's READ_ACTIONS,
        # gated on ai.governance.read (member tier holds it — permissions.rb:677-678).
      }.freeze

      # Advertisement is deliberately NOT overridden (unlike AgentAutonomyTool,
      # whose escalate/report_issue are an agent's only route to a human). The
      # floor is a member-tier permission, so BaseTool.permitted? re-arming
      # narrows this tool's advertisement only in an account where NO user can
      # read governance at all — where withholding it is the correct answer.

      def self.definition
        { name: "governance", description: "Agent governance monitoring, scanning, and collusion detection", parameters: { type: "object", properties: {} } }
      end

      def self.action_definitions
        {
          "governance_scan" => {
            description: "Run a governance scan on a specific agent or team",
            parameters: {
              agent_id: { type: "string", required: false, description: "Agent to scan" },
              team_id: { type: "string", required: false, description: "Team to scan" }
            }
          },
          "list_governance_reports" => {
            description: "List governance reports with optional filters",
            parameters: {
              status: { type: "string", required: false, description: "Filter by status" },
              severity: { type: "string", required: false, description: "Filter by severity" },
              agent_id: { type: "string", required: false, description: "Filter by agent" },
              limit: { type: "integer", required: false, description: "Max results" }
            }
          },
          "get_governance_report" => {
            description: "Get detailed governance report",
            parameters: {
              report_id: { type: "string", required: true, description: "Report ID" }
            }
          },
          "resolve_governance_report" => {
            description: "Resolve a governance report with a status and notes",
            parameters: {
              report_id: { type: "string", required: true, description: "Report ID" },
              resolution_status: { type: "string", required: true, description: "Resolution: confirmed, dismissed, remediated" },
              notes: { type: "string", required: false, description: "Resolution notes" }
            }
          },
          "detect_collusion" => {
            description: "Run collusion detection across active agents",
            parameters: {}
          },
          "governance_dashboard" => {
            description: "Get governance dashboard with summary metrics",
            parameters: {}
          }
        }
      end

      def call(params)
        action = params[:action].to_s

        unless action_permitted?(action)
          # Logged as well as returned: the tool's own idiom is an error result,
          # but a bare result is invisible — on the agent path it becomes an
          # ordinary tool message, so a caller repeatedly attempting a resolve it
          # cannot hold would leave no trace. The floor denial one layer up
          # raises and is logged by the registrar; this is the matching record
          # for the per-action denial.
          Rails.logger.warn(
            "[GovernanceTool] Refused action for insufficient permission: " \
            "action=#{action} requires=#{required_perm_for(action)} user=#{user&.id}"
          )
          return error_result("permission denied: #{required_perm_for(action)} required")
        end

        case action
        when "governance_scan" then governance_scan(params)
        when "list_governance_reports" then list_governance_reports(params)
        when "get_governance_report" then get_governance_report(params)
        when "resolve_governance_report" then resolve_governance_report(params)
        when "detect_collusion" then detect_collusion(params)
        when "governance_dashboard" then governance_dashboard(params)
        else error_result("Unknown action: #{action}")
        end
      end

      private

      # === Per-action permission gating (IMP-6fbfeff384fa) ===
      #
      # Keyed on the action that RUNS, never on the name that was invoked: a
      # user principal is deliberately NOT pinned to the invoked tool name
      # (McpPlatformToolRegistrar#action_pinned_to_name?), so a name-keyed check
      # is bypassable by supplying a sibling :action.

      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      # Two bypasses, both EXPLICIT, matching the sibling tools' ladder:
      #
      #   internal?            in-process system callers that opted in with
      #                        `internal: true`. Never inferred from a nil user —
      #                        an MCP instance principal also arrives with none
      #                        (IMP-9030413bc292).
      #   instance_authorized? an mTLS node principal whose SPECIFIC tool name
      #                        already cleared Mcp::Principal#may_invoke?, and
      #                        whose action the registrar then pins to that same
      #                        name. Without this arm every such call is
      #                        hard-denied (BUG-R).
      #
      # A principal that cannot answer has_permission? is refused rather than
      # waved through: REQUIRED_PERMISSION is no longer nil, so the registrar has
      # already asked the question of anything that gets this far.
      def action_permitted?(action)
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        # Compared against true rather than used for truthiness: nothing on the
        # MCP path coerces a permission answer, and a truthy non-boolean must not
        # read as a grant.
        user.has_permission?(required_perm_for(action)) == true
      end

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
