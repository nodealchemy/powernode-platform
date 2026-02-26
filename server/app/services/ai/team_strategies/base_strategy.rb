# frozen_string_literal: true

module Ai
  module TeamStrategies
    class BaseStrategy
      attr_reader :team, :execution, :account

      def initialize(team:, execution:, account:)
        @team = team
        @execution = execution
        @account = account
      end

      # Abstract method - subclasses must implement
      def execute(input:)
        raise NotImplementedError, "#{self.class}#execute must be implemented"
      end

      private

      # Execute a single agent via McpAgentExecutor
      def execute_agent(agent, task_input)
        executor = Ai::McpAgentExecutor.new(agent: agent, account: account)
        executor.execute({ "input" => task_input })
      end

      # Record a task result for the team execution
      def record_task(agent:, role:, output:, cost: 0.0, tokens: 0, duration_ms: 0)
        {
          agent_id: agent.id,
          agent_name: agent.name,
          role: role,
          output: output,
          cost: cost,
          tokens_used: tokens,
          duration_ms: duration_ms
        }
      end

      # Build LLM client for an agent
      def build_llm_client(agent)
        provider = agent.provider
        credential = provider.provider_credentials.where(account: account).active.first
        raise "No credentials for provider: #{provider.name}" unless credential

        Ai::Llm::Client.new(provider: provider, credential: credential)
      end

      # Get sorted team members
      def sorted_members
        team.members.includes(:agent).order(:priority_order)
      end

      # Update execution with results
      def finalize_results(results)
        {
          tasks_completed: results.count { |r| r[:output].present? },
          tasks_failed: results.count { |r| r[:output].nil? },
          total_cost: results.sum { |r| r[:cost] || 0.0 },
          total_tokens: results.sum { |r| r[:tokens_used] || 0 },
          outputs: results
        }
      end
    end
  end
end
