# frozen_string_literal: true

module Ai
  module TeamStrategies
    class MeshStrategy < BaseStrategy
      MAX_ROUNDS = 3

      CONSENSUS_SCHEMA = {
        name: "consensus_check",
        schema: {
          type: "object",
          properties: {
            consensus_reached: { type: "boolean", description: "Whether all outputs converge on a consistent answer" },
            synthesis: { type: "string", description: "Synthesized result combining all perspectives" }
          },
          required: %w[consensus_reached synthesis]
        }
      }.freeze

      # Multi-round collaboration: all members work the same task, share outputs,
      # and iterate until consensus is reached or MAX_ROUNDS exhausted.
      def execute(input:)
        members = sorted_members.to_a

        Rails.logger.info "[MeshStrategy] Executing #{members.size} members, max #{MAX_ROUNDS} rounds for team #{team.id}"

        all_results = []
        round_outputs = []

        (1..MAX_ROUNDS).each do |round|
          Rails.logger.info "[MeshStrategy] Round #{round}/#{MAX_ROUNDS}"

          round_input = build_round_input(input, round_outputs, round)
          current_round_outputs = execute_round(members, round_input)

          all_results.concat(current_round_outputs)
          round_outputs << current_round_outputs

          # Check consensus after round completes
          consensus = check_consensus(members.first.agent, input, current_round_outputs)

          if consensus[:consensus_reached]
            Rails.logger.info "[MeshStrategy] Consensus reached in round #{round}"
            return build_consensus_result(all_results, consensus[:synthesis])
          end
        end

        Rails.logger.info "[MeshStrategy] Max rounds reached without consensus, synthesizing best result"
        final_synthesis = force_synthesis(members.first.agent, input, round_outputs)
        build_consensus_result(all_results, final_synthesis)
      end

      private

      def build_round_input(original_input, previous_rounds, round_number)
        return original_input if previous_rounds.empty?

        prior_context = previous_rounds.last.filter_map do |result|
          next unless result[:output].present?

          "[#{result[:role]} - #{result[:agent_name]}]: #{result[:output]}"
        end.join("\n\n")

        "#{original_input}\n\n---\nRound #{round_number} - Previous peer outputs:\n#{prior_context}\n\nRefine your answer considering your peers' perspectives."
      end

      def execute_round(members, round_input)
        results = []

        members.each do |member|
          agent = member.agent
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          begin
            result = execute_agent(agent, round_input)
            duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

            output = result.is_a?(Hash) ? (result[:output] || result["output"]) : result.to_s

            results << record_task(
              agent: agent,
              role: member.role || "collaborator",
              output: output,
              cost: result.is_a?(Hash) ? (result[:cost] || result["cost"] || 0.0) : 0.0,
              tokens: result.is_a?(Hash) ? (result[:tokens_used] || result["tokens_used"] || 0) : 0,
              duration_ms: duration_ms
            )
          rescue StandardError => e
            Rails.logger.error "[MeshStrategy] Agent #{agent.name} failed in round: #{e.message}"
            results << record_task(agent: agent, role: member.role || "collaborator", output: nil)
          end
        end

        results
      end

      def check_consensus(evaluator_agent, original_input, round_outputs)
        llm_client = build_llm_client(evaluator_agent)
        completed = round_outputs.select { |r| r[:output].present? }

        return { consensus_reached: true, synthesis: completed.first[:output] } if completed.size <= 1

        summary = completed.map { |r| "[#{r[:agent_name]}]: #{r[:output]}" }.join("\n\n")

        messages = [
          { role: "user", content: "Task: #{original_input}\n\nOutputs:\n#{summary}\n\nDo these outputs reach consensus? Synthesize if so." }
        ]

        response = llm_client.complete_structured(
          messages: messages,
          schema: CONSENSUS_SCHEMA,
          model: evaluator_agent.model_id
        )

        response.deep_symbolize_keys
      rescue StandardError => e
        Rails.logger.error "[MeshStrategy] Consensus check failed: #{e.message}"
        { consensus_reached: false, synthesis: nil }
      end

      def force_synthesis(_evaluator_agent, _original_input, all_rounds)
        last_round = all_rounds.last || []
        outputs = last_round.filter_map { |r| r[:output] }
        outputs.join("\n\n---\n\n")
      end

      def build_consensus_result(all_results, synthesis)
        result = finalize_results(all_results)
        result[:synthesis] = synthesis
        result
      end
    end
  end
end
