# frozen_string_literal: true

module Ai
  module TeamStrategies
    class HierarchicalStrategy < BaseStrategy
      # Lead agent decomposes the task, delegates subtasks to workers via DAG,
      # then synthesizes the final result from all worker outputs.
      def execute(input:)
        lead_member = team.members.leads.includes(:agent).first
        raise "Hierarchical team #{team.id} has no lead member" unless lead_member

        worker_members = team.members.non_leads.includes(:agent).order(:priority_order).to_a
        raise "Hierarchical team #{team.id} has no worker members" if worker_members.empty?

        lead_agent = lead_member.agent

        Rails.logger.info "[HierarchicalStrategy] Lead: #{lead_agent.name}, Workers: #{worker_members.size}"

        # Phase 1: Lead decomposes the task
        decomposition = decompose_task(lead_agent, input, worker_members)
        subtasks = decomposition[:subtasks] || []

        if subtasks.empty?
          Rails.logger.warn "[HierarchicalStrategy] No subtasks produced, executing input directly"
          return execute_fallback(lead_agent, lead_member, input)
        end

        # Phase 2: Delegate subtasks to workers
        worker_results = execute_subtasks(subtasks, worker_members, input)

        # Phase 3: Lead synthesizes final result
        synthesis = synthesize_results(lead_agent, input, worker_results)

        build_final_results(lead_member, lead_agent, worker_results, synthesis)
      end

      private

      def decompose_task(lead_agent, input, worker_members)
        llm_client = build_llm_client(lead_agent)
        capabilities = worker_members.map do |m|
          { name: m.agent.name, role: m.role, capabilities: m.agent.system_prompt&.truncate(200) }
        end

        decomposer = Ai::Planning::TaskDecompositionService.new(account: account)
        decomposer.decompose(
          task: input,
          agent_capabilities: capabilities,
          llm_client: llm_client,
          model: lead_agent.model_id
        )
      end

      def execute_subtasks(subtasks, worker_members, original_input)
        results = []

        subtasks.each_with_index do |subtask, index|
          worker = find_worker_for_subtask(subtask, worker_members, index)
          agent = worker.agent

          Rails.logger.info "[HierarchicalStrategy] Delegating subtask to #{agent.name}: #{subtask[:description]&.truncate(80)}"

          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          begin
            task_input = subtask[:description] || subtask[:task] || original_input
            result = execute_agent(agent, task_input)
            duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

            results << record_task(
              agent: agent,
              role: worker.role || "worker",
              output: result.is_a?(Hash) ? (result[:output] || result["output"]) : result.to_s,
              cost: result.is_a?(Hash) ? (result[:cost] || result["cost"] || 0.0) : 0.0,
              tokens: result.is_a?(Hash) ? (result[:tokens_used] || result["tokens_used"] || 0) : 0,
              duration_ms: duration_ms
            )
          rescue StandardError => e
            Rails.logger.error "[HierarchicalStrategy] Worker #{agent.name} failed: #{e.message}"
            results << record_task(agent: agent, role: worker.role || "worker", output: nil)
          end
        end

        results
      end

      def find_worker_for_subtask(_subtask, worker_members, index)
        worker_members[index % worker_members.size]
      end

      def synthesize_results(lead_agent, original_input, worker_results)
        llm_client = build_llm_client(lead_agent)
        completed = worker_results.select { |r| r[:output].present? }

        summary = completed.map do |r|
          "[#{r[:role]} - #{r[:agent_name]}]: #{r[:output]}"
        end.join("\n\n")

        messages = [
          { role: "user", content: "Original task: #{original_input}\n\nWorker outputs:\n#{summary}\n\nSynthesize a final cohesive result." }
        ]

        response = llm_client.complete(
          messages: messages,
          model: lead_agent.model_id,
          system_prompt: lead_agent.system_prompt
        )

        response.content
      rescue StandardError => e
        Rails.logger.error "[HierarchicalStrategy] Synthesis failed: #{e.message}"
        worker_results.filter_map { |r| r[:output] }.join("\n\n")
      end

      def execute_fallback(lead_agent, lead_member, input)
        result = execute_agent(lead_agent, input)
        output = result.is_a?(Hash) ? (result[:output] || result["output"]) : result.to_s

        finalize_results([
          record_task(agent: lead_agent, role: lead_member.role || "lead", output: output)
        ])
      end

      def build_final_results(lead_member, lead_agent, worker_results, synthesis)
        all_results = worker_results.dup
        all_results << record_task(
          agent: lead_agent,
          role: lead_member.role || "lead",
          output: synthesis
        )

        finalize_results(all_results)
      end
    end
  end
end
