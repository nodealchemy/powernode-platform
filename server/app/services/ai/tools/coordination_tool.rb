# frozen_string_literal: true

module Ai
  module Tools
    class CoordinationTool < BaseTool
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
              type: "object", required: ["signal_type", "signal_key"],
              properties: {
                signal_type: { type: "string", enum: %w[pheromone pressure beacon warning discovery] },
                signal_key: { type: "string", description: "Namespaced signal key" },
                strength: { type: "number", description: "Signal strength 0-1 (default 1.0)" },
                decay_rate: { type: "number", description: "Decay rate per cycle (default 0.05)" },
                payload: { type: "object", description: "Signal payload data" },
                ttl_seconds: { type: "integer", description: "Time-to-live in seconds" }
              }
            }
          },
          "perceive_signals" => {
            description: "Perceive active stigmergic signals, optionally filtered by type",
            parameters: {
              type: "object", properties: {
                signal_types: { type: "array", items: { type: "string" }, description: "Filter by signal types" },
                limit: { type: "integer", description: "Max signals to return (default 20)" }
              }
            }
          },
          "reinforce_signal" => {
            description: "Reinforce an existing stigmergic signal (ant-trail reinforcement pattern)",
            parameters: {
              type: "object", required: ["signal_id"],
              properties: {
                signal_id: { type: "string", description: "Signal ID to reinforce" },
                strength_delta: { type: "number", description: "Reinforcement amount (default 0.1)" }
              }
            }
          },
          "measure_pressure" => {
            description: "Measure a pressure field on an artifact (code_quality, test_coverage, etc.)",
            parameters: {
              type: "object", required: ["artifact_ref", "field_type"],
              properties: {
                artifact_ref: { type: "string", description: "Artifact reference (e.g., file path, module name)" },
                artifact_type: { type: "string", description: "Artifact type (e.g., file, module, service)" },
                field_type: { type: "string", enum: %w[code_quality test_coverage doc_readability security_posture performance dependency_health] }
              }
            }
          },
          "perceive_pressure" => {
            description: "Perceive actionable pressure fields sorted by highest pressure",
            parameters: {
              type: "object", properties: {
                team_id: { type: "string", description: "Filter by team context" },
                limit: { type: "integer", description: "Max fields to return (default 10)" }
              }
            }
          },
          "optimize_team" => {
            description: "Run full team composition optimization (gap detection, leader emergence, member rebalancing)",
            parameters: {
              type: "object", required: ["team_id"],
              properties: {
                team_id: { type: "string", description: "Team ID to optimize" }
              }
            }
          },
          "recruit_agent" => {
            description: "Recruit an agent into a team to fill a capability gap",
            parameters: {
              type: "object", required: ["team_id", "capability"],
              properties: {
                team_id: { type: "string", description: "Team ID to recruit into" },
                capability: { type: "string", description: "Required capability" }
              }
            }
          }
        }
      end

      def call(params)
        case params[:action]
        when "emit_signal" then emit_signal(params)
        when "perceive_signals" then perceive_signals(params)
        when "reinforce_signal" then reinforce_signal(params)
        when "measure_pressure" then measure_pressure(params)
        when "perceive_pressure" then perceive_pressure(params)
        when "optimize_team" then optimize_team(params)
        when "recruit_agent" then recruit_agent(params)
        else
          error_result("Unknown action: #{params[:action]}")
        end
      end

      private

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

        service = Ai::Coordination::SelfOrganizingTeamService.new(account: account)
        result = service.recruit_member!(team: team, capability: params["capability"])
        success_result(result)
      rescue StandardError => e
        error_result("Failed to recruit agent: #{e.message}")
      end
    end
  end
end
