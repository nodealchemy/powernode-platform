# frozen_string_literal: true

module Ai
  module Autonomy
    class CapabilityMatrixService
      # Declarative permission matrix: (trust_tier x action_type) → policy
      # Policies: :allowed, :requires_approval, :denied
      DEFAULT_MATRIX = {
        "supervised" => {
          "read_data"                    => :allowed,
          "execute_tool"                 => :requires_approval,
          "spawn_agent"                  => :denied,
          "modify_system"                => :denied,
          "access_credentials"           => :denied,
          "external_api_call"            => :denied,
          "delete_data"                  => :denied,
          "execute_code"                 => :denied,
          "modify_permissions"           => :denied,
          "plan_and_execute"             => :denied,
          "observe_environment"          => :allowed,
          "create_goal"                  => :denied,
          "create_feature_suggestion"    => :denied,
          "send_proactive_notification"  => :denied,
          "apply_recommendation"         => :denied,
          "request_code_change"          => :denied,
          "create_mission_draft"         => :denied
        },
        "monitored" => {
          "read_data"                    => :allowed,
          "execute_tool"                 => :allowed,
          "spawn_agent"                  => :requires_approval,
          "modify_system"                => :denied,
          "access_credentials"           => :requires_approval,
          "external_api_call"            => :requires_approval,
          "delete_data"                  => :denied,
          "execute_code"                 => :requires_approval,
          "modify_permissions"           => :denied,
          "plan_and_execute"             => :requires_approval,
          "observe_environment"          => :allowed,
          "create_goal"                  => :requires_approval,
          "create_feature_suggestion"    => :denied,
          "send_proactive_notification"  => :requires_approval,
          "apply_recommendation"         => :denied,
          "request_code_change"          => :denied,
          "create_mission_draft"         => :denied
        },
        "trusted" => {
          "read_data"                    => :allowed,
          "execute_tool"                 => :allowed,
          "spawn_agent"                  => :allowed,
          "modify_system"                => :requires_approval,
          "access_credentials"           => :allowed,
          "external_api_call"            => :allowed,
          "delete_data"                  => :requires_approval,
          "execute_code"                 => :allowed,
          "modify_permissions"           => :requires_approval,
          "plan_and_execute"             => :allowed,
          "observe_environment"          => :allowed,
          "create_goal"                  => :allowed,
          "create_feature_suggestion"    => :requires_approval,
          "send_proactive_notification"  => :allowed,
          "apply_recommendation"         => :requires_approval,
          "request_code_change"          => :requires_approval,
          "create_mission_draft"         => :requires_approval
        },
        "autonomous" => {
          "read_data"                    => :allowed,
          "execute_tool"                 => :allowed,
          "spawn_agent"                  => :allowed,
          "modify_system"                => :allowed,
          "access_credentials"           => :allowed,
          "external_api_call"            => :allowed,
          "delete_data"                  => :requires_approval,
          "execute_code"                 => :allowed,
          "modify_permissions"           => :requires_approval,
          "plan_and_execute"             => :allowed,
          "observe_environment"          => :allowed,
          "create_goal"                  => :allowed,
          "create_feature_suggestion"    => :allowed,
          "send_proactive_notification"  => :allowed,
          "apply_recommendation"         => :allowed,
          "request_code_change"          => :allowed,
          "create_mission_draft"         => :allowed
        }
      }.freeze

      # Normalize common action aliases to canonical matrix keys.
      # The security gate passes generic action types (e.g. "execute") that must
      # map to the specific matrix vocabulary.
      ACTION_ALIASES = {
        "execute" => "execute_tool",
        "run" => "execute_tool",
        "generate" => "execute_tool",
        "call_api" => "external_api_call",
        "api_call" => "external_api_call",
        "spawn" => "spawn_agent",
        "create_agent" => "spawn_agent",
        "read" => "read_data",
        "delete" => "delete_data",
        "modify" => "modify_system",
        "plan" => "plan_and_execute",
        "decompose" => "plan_and_execute",
        "observe" => "observe_environment",
        "sense" => "observe_environment",
        "suggest_feature" => "create_feature_suggestion",
        "propose_feature" => "create_feature_suggestion",
        "notify" => "send_proactive_notification",
        "alert_user" => "send_proactive_notification",
        "apply_fix" => "apply_recommendation",
        "code_change" => "request_code_change",
        "create_mission" => "create_mission_draft",
        "propose_mission" => "create_mission_draft"
      }.freeze

      ACTION_TYPES = DEFAULT_MATRIX["supervised"].keys.freeze

      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Check what policy applies for a given agent and action
      # @param agent [Ai::Agent] The agent
      # @param action_type [String] The action type
      # @return [Symbol] :allowed, :requires_approval, or :denied
      def check(agent:, action_type:)
        tier = agent_tier(agent)
        matrix = effective_matrix
        canonical = normalize_action(action_type.to_s)
        policy = matrix.dig(tier, canonical)

        policy&.to_sym || :denied
      end

      # Get the full capability matrix (with any customizations)
      # @return [Hash]
      def full_matrix
        effective_matrix
      end

      # Get capabilities for a specific agent
      # @param agent [Ai::Agent] The agent
      # @return [Hash]
      def agent_capabilities(agent:)
        tier = agent_tier(agent)
        matrix = effective_matrix

        {
          agent_id: agent.id,
          agent_name: agent.name,
          tier: tier,
          capabilities: matrix[tier] || {}
        }
      end

      private

      def normalize_action(action_type)
        return action_type if ACTION_TYPES.include?(action_type)

        ACTION_ALIASES[action_type] || action_type
      end

      def agent_tier(agent)
        trust_score = Ai::AgentTrustScore.find_by(agent_id: agent.id)
        trust_score&.tier || "supervised"
      end

      def effective_matrix
        custom = guardrail_matrix
        return DEFAULT_MATRIX if custom.blank?

        # Deep merge: custom overrides default
        DEFAULT_MATRIX.each_with_object({}) do |(tier, actions), result|
          result[tier] = actions.merge(custom[tier] || {})
        end
      end

      def guardrail_matrix
        config = Ai::GuardrailConfig.where(account_id: account.id).active.global.first
        return nil unless config

        config.effective_config[:capability_matrix]
      end
    end
  end
end
