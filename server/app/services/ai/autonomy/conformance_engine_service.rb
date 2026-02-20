# frozen_string_literal: true

module Ai
  module Autonomy
    class ConformanceEngineService
      # Declarative temporal rules: trigger event requires a prior event within a time window
      DEFAULT_RULES = [
        {
          name: "approval_before_execution",
          trigger: "action_executed",
          required_prior: "action_approved",
          window_seconds: 3600,
          severity: "high"
        },
        {
          name: "trust_check_before_spawn",
          trigger: "agent_spawned",
          required_prior: "trust_evaluated",
          window_seconds: 86_400,
          severity: "medium"
        },
        {
          name: "budget_check_before_spend",
          trigger: "budget_spent",
          required_prior: "budget_checked",
          window_seconds: 300,
          severity: "high"
        },
        {
          name: "anomaly_scan_regular",
          trigger: "action_executed",
          required_prior: "anomaly_scanned",
          window_seconds: 3600,
          severity: "low"
        }
      ].freeze

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Check if an event conforms to all applicable rules
      # @param agent [Ai::Agent] The agent
      # @param event_type [String] The event being checked
      # @return [Hash] { conformant: Boolean, violations: Array }
      def check_event(agent:, event_type:)
        rules = effective_rules
        violations = []

        rules.each do |rule|
          next unless rule[:trigger] == event_type.to_s || rule["trigger"] == event_type.to_s

          required = rule[:required_prior] || rule["required_prior"]
          window = rule[:window_seconds] || rule["window_seconds"]
          severity = rule[:severity] || rule["severity"]
          name = rule[:name] || rule["name"]

          # Check if the required prior event exists within the window
          prior_exists = Ai::TelemetryEvent
            .where(account_id: account.id)
            .for_agent(agent.id)
            .where(event_type: required)
            .where("created_at >= ?", window.seconds.ago)
            .exists?

          unless prior_exists
            violations << {
              rule: name,
              trigger: event_type,
              required_prior: required,
              window_seconds: window,
              severity: severity,
              message: "Required prior event '#{required}' not found within #{window}s window"
            }
          end
        end

        { conformant: violations.empty?, violations: violations }
      end

      # Get all applicable rules
      def effective_rules
        custom = guardrail_rules
        return DEFAULT_RULES if custom.blank?

        # Custom rules override defaults by name, then add any extras
        default_names = DEFAULT_RULES.map { |r| r[:name] }
        custom_names = custom.map { |r| r[:name] || r["name"] }

        merged = DEFAULT_RULES.map do |rule|
          custom_override = custom.find { |c| (c[:name] || c["name"]) == rule[:name] }
          custom_override || rule
        end

        # Add custom rules not in defaults
        extras = custom.reject { |c| default_names.include?(c[:name] || c["name"]) }
        merged + extras
      end

      private

      def guardrail_rules
        config = Ai::GuardrailConfig.where(account_id: account.id).active.global.first
        return nil unless config

        config.effective_config[:conformance_rules]
      end
    end
  end
end
