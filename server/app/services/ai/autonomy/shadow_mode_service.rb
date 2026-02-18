# frozen_string_literal: true

module Ai
  module Autonomy
    class ShadowModeService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # Execute an action in shadow mode and compare with reference
      # @param agent [Ai::Agent] The agent being shadowed
      # @param action_type [String] The action type
      # @param input [Hash] The input data
      # @param shadow_output [Hash] The shadow agent's output
      # @param reference_output [Hash] The reference (human/trusted agent) output
      # @return [Ai::ShadowExecution]
      def execute_shadow(agent:, action_type:, input:, shadow_output:, reference_output: nil)
        comparison = reference_output ? compare_outputs(shadow_output, reference_output) : { agreed: false, score: 0.0 }

        Ai::ShadowExecution.create!(
          account: account,
          agent: agent,
          action_type: action_type,
          shadow_input: input,
          shadow_output: shadow_output,
          reference_output: reference_output || {},
          agreed: comparison[:agreed],
          agreement_score: comparison[:score]
        )
      end

      # Compare two outputs for agreement
      # @param shadow [Hash] Shadow output
      # @param reference [Hash] Reference output
      # @return [Hash] { agreed: Boolean, score: Float, details: Hash }
      def compare_outputs(shadow, reference)
        return { agreed: false, score: 0.0, details: { reason: "empty_reference" } } if reference.blank?
        return { agreed: true, score: 1.0, details: { reason: "exact_match" } } if shadow == reference

        # Key-level comparison
        all_keys = (shadow.keys + reference.keys).uniq
        return { agreed: false, score: 0.0, details: { reason: "no_keys" } } if all_keys.empty?

        matching_keys = all_keys.count { |k| shadow[k] == reference[k] }
        score = (matching_keys.to_f / all_keys.size).round(4)
        agreed = score >= 0.8

        { agreed: agreed, score: score, details: { total_keys: all_keys.size, matching: matching_keys } }
      end

      # Calculate agreement rate for an agent over a time window
      # @param agent [Ai::Agent] The agent
      # @param window [ActiveSupport::Duration] Time window (default: 7 days)
      # @return [Hash] { rate: Float, total: Integer, agreed: Integer }
      def agreement_rate(agent:, window: 7.days)
        executions = Ai::ShadowExecution.for_agent(agent.id)
          .where("created_at >= ?", window.ago)

        total = executions.count
        return { rate: 0.0, total: 0, agreed: 0 } if total.zero?

        agreed = executions.agreed.count
        { rate: (agreed.to_f / total).round(4), total: total, agreed: agreed }
      end

      # List shadow executions
      def list(limit: 50)
        Ai::ShadowExecution
          .where(account_id: account.id)
          .includes(:agent)
          .recent
          .limit(limit)
      end

      # List shadow executions for a specific agent
      def for_agent(agent, limit: 50)
        Ai::ShadowExecution.for_agent(agent.id)
          .where(account_id: account.id)
          .recent
          .limit(limit)
      end
    end
  end
end
