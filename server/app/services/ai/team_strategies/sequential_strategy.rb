# frozen_string_literal: true

module Ai
  module TeamStrategies
    class SequentialStrategy < BaseStrategy
      # Execute members sequentially by priority order, passing accumulated
      # output forward so each member receives the task plus all prior results.
      def execute(input:)
        members = sorted_members.to_a
        results = []
        accumulated_context = []

        Rails.logger.info "[SequentialStrategy] Executing #{members.size} members for team #{team.id}"

        members.each_with_index do |member, index|
          agent = member.agent
          role = member.role || "worker"

          Rails.logger.info "[SequentialStrategy] Step #{index + 1}/#{members.size}: #{agent.name} (#{role})"

          task_input = build_task_input(input, accumulated_context, member)
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          begin
            result = execute_agent(agent, task_input)
            duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

            output = extract_output(result)
            task_record = record_task(
              agent: agent,
              role: role,
              output: output,
              cost: extract_cost(result),
              tokens: extract_tokens(result),
              duration_ms: duration_ms
            )

            results << task_record
            accumulated_context << { agent: agent.name, role: role, output: output }
          rescue StandardError => e
            Rails.logger.error "[SequentialStrategy] Agent #{agent.name} failed: #{e.message}"
            results << record_task(agent: agent, role: role, output: nil)
          end
        end

        finalize_results(results)
      end

      private

      def build_task_input(original_input, accumulated_context, _member)
        return original_input if accumulated_context.empty?

        context_summary = accumulated_context.map do |ctx|
          "[#{ctx[:role]} - #{ctx[:agent]}]: #{ctx[:output]}"
        end.join("\n\n")

        "#{original_input}\n\n---\nPrevious outputs:\n#{context_summary}"
      end

      def extract_output(result)
        return result[:output] if result.is_a?(Hash) && result[:output]
        return result["output"] if result.is_a?(Hash) && result["output"]

        result.to_s
      end

      def extract_cost(result)
        return result[:cost] || result["cost"] || 0.0 if result.is_a?(Hash)

        0.0
      end

      def extract_tokens(result)
        return result[:tokens_used] || result["tokens_used"] || 0 if result.is_a?(Hash)

        0
      end
    end
  end
end
