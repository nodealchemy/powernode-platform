# frozen_string_literal: true

module Ai
  module Tools
    class CoordinationTool < BaseTool
      # SECURITY (IMP-6fbfeff384fa): authorization here is per ACTION, not per
      # tool. REQUIRED_PERMISSION was inherited as nil from BaseTool, and
      # McpPlatformToolRegistrar#enforce_permission! opens with
      # `return if required.nil?` — ABOVE the authentication raise and the
      # has_permission? raise. Every action was
      # therefore reachable by any MCP caller with no check at all, including
      # recruit_agent and optimize_team, which rewrite team membership.
      #
      # Floor: ai.agents.read, the baseline AI-surface read. It is NOT any
      # action's twin — it is the least-privileged permission every legitimate
      # caller of this tool holds, which is what the registrar needs since it
      # must decide before the action is resolved. A floor of ai.manage would
      # lock out the member-tier caller who legitimately holds ai.teams.manage
      # (permissions.rb:740) but not ai.manage; there is no ordering between
      # those two, so the floor has to sit under both.
      REQUIRED_PERMISSION = "ai.agents.read"

      # Each entry names the permission the REST twin of that action requires.
      ACTION_PERMISSIONS = {
        # GET /api/v1/ai/coordination/{signals,pressure_fields} →
        # Api::V1::Ai::CoordinationDashboardController#validate_permissions,
        # blanket ai.manage (coordination_dashboard_controller.rb:7,86-92). It
        # serves the same account-scoped rows these actions return, so the
        # disclosure is identical whichever path reads them.
        "perceive_signals" => "ai.manage",
        "perceive_pressure" => "ai.manage",

        # measure_pressure is here for the same DISCLOSURE reason, not because it
        # writes: it returns the field itself (pressure_value, threshold,
        # dimensions), which is exactly what the dashboard's pressure_fields read
        # serves under ai.manage. Leaving it at the floor would hand a caller
        # refused perceive_pressure the same rows one artifact_ref at a time.
        "measure_pressure" => "ai.manage",

        # POST /api/v1/ai/agent_teams/:id/members and .../optimize →
        # #authorize_teams_access! (agent_teams_controller.rb:21,237). Note this
        # tool is STRICTLY more powerful than the REST twin at the same
        # permission: REST #optimize only enqueues AiTeamOptimizeJob, which
        # RECOMMENDS actions, while SelfOrganizingTeamService#
        # optimize_team_composition! mutates the team synchronously. Parity is a
        # lower bound, so the twin's permission is the minimum, not a licence.
        "optimize_team" => "ai.teams.manage",
        "recruit_agent" => "ai.teams.manage"

        # emit_signal and reinforce_signal stay at the floor on purpose. Nothing
        # outside this tool writes an Ai::StigmergicSignal — the only related
        # REST route is the mTLS worker's bulk decay — so parity says nothing
        # about them, and they are an agent's own coordination voice: tightening
        # them would leave agents able to read the substrate but not participate
        # in it. The resulting asymmetry (writes at the floor, reads at
        # ai.manage) is imposed by the twin that exists, not chosen. Their return
        # values are the caller's own write echoed back (signal_id, key, the
        # resulting strength), not a view of the substrate, which is what keeps
        # them on the write side of the measure_pressure line above.
      }.freeze

      # Advertisement is deliberately NOT overridden (unlike AgentAutonomyTool,
      # whose escalate/report_issue are an agent's only route to a human). The
      # floor is a member-tier permission, so BaseTool.permitted? re-arming
      # narrows advertisement only in an account where NO user can read agents.

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "emit_signal", mutating: true
      declare_action "measure_pressure", mutating: true
      declare_action "optimize_team", mutating: true
      declare_action "perceive_pressure", mutating: true
      declare_action "perceive_signals", mutating: true
      declare_action "recruit_agent", mutating: true
      declare_action "reinforce_signal", mutating: true

      def self.definition
        {
          name: "coordination",
          description: "Stigmergic coordination, pressure fields, and team self-organization tools",
          parameters: { type: "object", properties: {} }
        }
      end

      def self.action_definitions
        {
          "emit_signal" => {
            description: "Emit a stigmergic signal (pheromone, pressure, beacon, warning, discovery) for decentralized coordination",
            parameters: {
              signal_type: { type: "string", required: true, description: "Signal type: pheromone, pressure, beacon, warning, discovery" },
              signal_key: { type: "string", required: true, description: "Namespaced signal key" },
              strength: { type: "number", required: false, description: "Signal strength 0-1 (default 1.0)" },
              decay_rate: { type: "number", required: false, description: "Decay rate per cycle (default 0.05)" },
              payload: { type: "object", required: false, description: "Signal payload data" },
              ttl_seconds: { type: "integer", required: false, description: "Time-to-live in seconds" }
            }
          },
          "perceive_signals" => {
            description: "Perceive active stigmergic signals, optionally filtered by type",
            parameters: {
              signal_types: { type: "array", required: false, description: "Filter by signal types" },
              limit: { type: "integer", required: false, description: "Max signals to return (default 20)" }
            }
          },
          "reinforce_signal" => {
            description: "Reinforce an existing stigmergic signal (ant-trail reinforcement pattern)",
            parameters: {
              signal_id: { type: "string", required: true, description: "Signal ID to reinforce" },
              strength_delta: { type: "number", required: false, description: "Reinforcement amount (default 0.1)" }
            }
          },
          "measure_pressure" => {
            description: "Measure a pressure field on an artifact (code_quality, test_coverage, etc.)",
            parameters: {
              artifact_ref: { type: "string", required: true, description: "Artifact reference (e.g., file path, module name)" },
              artifact_type: { type: "string", required: false, description: "Artifact type (e.g., file, module, service)" },
              field_type: { type: "string", required: true, description: "Field type: code_quality, test_coverage, doc_readability, security_posture, performance, dependency_health" }
            }
          },
          "perceive_pressure" => {
            description: "Perceive actionable pressure fields sorted by highest pressure",
            parameters: {
              team_id: { type: "string", required: false, description: "Filter by team context" },
              limit: { type: "integer", required: false, description: "Max fields to return (default 10)" }
            }
          },
          "optimize_team" => {
            description: "Run full team composition optimization (gap detection, leader emergence, member rebalancing)",
            parameters: {
              team_id: { type: "string", required: true, description: "Team ID to optimize" }
            }
          },
          "recruit_agent" => {
            description: "Recruit an agent into a team to fill a capability gap",
            parameters: {
              team_id: { type: "string", required: true, description: "Team ID to recruit into" },
              capability: { type: "string", required: true, description: "Required capability" }
            }
          }
        }
      end

      def call(params)
        action = params[:action].to_s

        unless action_permitted?(action)
          Rails.logger.warn(
            "[CoordinationTool] Refused action for insufficient permission: " \
            "action=#{action} requires=#{required_perm_for(action)} user=#{user&.id}"
          )
          return error_result("permission denied: #{required_perm_for(action)} required")
        end

        case action
        when "emit_signal" then emit_signal(params)
        when "perceive_signals" then perceive_signals(params)
        when "reinforce_signal" then reinforce_signal(params)
        when "measure_pressure" then measure_pressure(params)
        when "perceive_pressure" then perceive_pressure(params)
        when "optimize_team" then optimize_team(params)
        when "recruit_agent" then recruit_agent(params)
        else
          error_result("Unknown action: #{action}")
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
      def action_permitted?(action)
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        # Compared against true rather than used for truthiness: nothing on the
        # MCP path coerces a permission answer, and a truthy non-boolean must not
        # read as a grant.
        user.has_permission?(required_perm_for(action)) == true
      end

      def emit_signal(params)
        service = Ai::Coordination::StigmergicSignalService.new(account: account)
        ttl = params["ttl_seconds"] ? params["ttl_seconds"].to_i.seconds : nil
        signal = service.emit!(
          signal_type: params["signal_type"],
          signal_key: params["signal_key"],
          agent: agent,
          strength: (params["strength"] || 1.0).to_f,
          decay_rate: (params["decay_rate"] || 0.05).to_f,
          payload: params["payload"] || {},
          ttl: ttl
        )
        success_result({ signal_id: signal.id, signal_key: signal.signal_key, strength: signal.strength })
      rescue StandardError => e
        error_result("Failed to emit signal: #{e.message}")
      end

      def perceive_signals(params)
        service = Ai::Coordination::StigmergicSignalService.new(account: account)
        signals = service.perceive(
          agent: agent,
          signal_types: params["signal_types"],
          limit: (params["limit"] || 20).to_i
        )
        success_result({ signals: signals.map { |s| s.as_json(only: [:id, :signal_type, :signal_key, :strength, :payload, :perceive_count]) }, count: signals.size })
      rescue StandardError => e
        error_result("Failed to perceive signals: #{e.message}")
      end

      def reinforce_signal(params)
        service = Ai::Coordination::StigmergicSignalService.new(account: account)
        signal = service.reinforce!(
          signal_id: params["signal_id"],
          agent: agent,
          strength_delta: (params["strength_delta"] || 0.1).to_f
        )
        return error_result("Signal not found") unless signal
        success_result({ signal_id: signal.id, new_strength: signal.strength })
      rescue StandardError => e
        error_result("Failed to reinforce signal: #{e.message}")
      end

      def measure_pressure(params)
        service = Ai::Coordination::PressureFieldService.new(account: account)
        field = service.measure!(
          artifact_ref: params["artifact_ref"],
          artifact_type: params["artifact_type"],
          field_type: params["field_type"]
        )
        return error_result("Measurement failed") unless field
        success_result(field.as_json(only: [:id, :field_type, :artifact_ref, :pressure_value, :threshold, :dimensions, :last_measured_at]))
      rescue StandardError => e
        error_result("Failed to measure pressure: #{e.message}")
      end

      def perceive_pressure(params)
        service = Ai::Coordination::PressureFieldService.new(account: account)
        fields = service.perceive(
          agent: agent,
          team_id: params["team_id"],
          limit: (params["limit"] || 10).to_i
        )
        success_result({ fields: fields, count: fields.size })
      rescue StandardError => e
        error_result("Failed to perceive pressure: #{e.message}")
      end

      def optimize_team(params)
        team = Ai::AgentTeam.find_by(id: params["team_id"], account: account)
        return error_result("Team not found") unless team

        service = Ai::Coordination::SelfOrganizingTeamService.new(account: account)
        result = service.optimize_team_composition!(team: team)
        success_result(result)
      rescue StandardError => e
        error_result("Failed to optimize team: #{e.message}")
      end

      def recruit_agent(params)
        team = Ai::AgentTeam.find_by(id: params["team_id"], account: account)
        return error_result("Team not found") unless team

        # capability is declared required:true, but execute_tool does no schema
        # validation, so a call without one arrives here. It has to surface as an
        # ERROR: success_result would report a malformed call as a successful one
        # to a caller branching on :success, since "recruited: false" is also how
        # the legitimate no-candidate outcome is reported.
        capability = params["capability"].to_s.strip
        return error_result("capability is required") if capability.empty?

        service = Ai::Coordination::SelfOrganizingTeamService.new(account: account)
        result = service.recruit_member!(team: team, capability: capability)
        success_result(result)
      rescue StandardError => e
        error_result("Failed to recruit agent: #{e.message}")
      end
    end
  end
end
