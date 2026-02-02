# frozen_string_literal: true

module A2a
  module Skills
    # AgentSkills - A2A skill implementations for agent operations
    class AgentSkills
      def initialize(account:, user: nil)
        @account = account
        @user = user
      end

      # List agents
      def list(input, task = nil)
        scope = @account.ai_agents.order(created_at: :desc)

        scope = scope.where(status: input["status"]) if input["status"].present?
        scope = scope.by_type(input["agent_type"]) if input["agent_type"].present?

        page = (input["page"] || 1).to_i
        per_page = [ (input["per_page"] || 20).to_i, 100 ].min

        agents = scope.offset((page - 1) * per_page).limit(per_page)

        {
          output: {
            agents: agents.map { |a| agent_summary(a) },
            total: scope.count,
            page: page,
            per_page: per_page
          }
        }
      end

      # Get agent details
      def get(input, task = nil)
        agent = find_agent(input["agent_id"])

        {
          output: {
            agent: agent_details(agent)
          }
        }
      end

      # Execute agent
      def execute(input, task = nil)
        agent = find_agent(input["agent_id"])

        unless agent.can_execute?
          raise ArgumentError, "Agent cannot be executed in #{agent.status} status"
        end

        executor = Ai::McpAgentExecutor.new(
          agent: agent,
          account: @account,
          context: input["context"] || {}
        )

        result = executor.execute(input: input["input"] || {})

        {
          output: {
            output: result[:output],
            execution_id: result[:execution_id],
            cost: result[:cost],
            tokens_used: result[:tokens_used]
          }
        }
      end

      # Discover A2A agents
      def discover(input, task = nil)
        a2a_service = ::Ai::A2a::Service.new(account: @account, user: @user)

        result = a2a_service.discover_agents(
          skill: input["skill"],
          tag: input["tag"],
          query: input["query"],
          page: input["page"],
          per_page: input["per_page"]
        )

        {
          output: result
        }
      end

      # Submit A2A task
      def submit_task(input, task = nil)
        a2a_service = ::Ai::A2a::Service.new(account: @account, user: @user)

        a2a_task = a2a_service.submit_task(
          to_agent_card: input["to_agent_card_id"],
          message: input["message"],
          sync: input["sync"] || false
        )

        {
          output: {
            task: a2a_task.to_a2a_json
          }
        }
      end

      private

      def find_agent(id)
        @account.ai_agents.find(id)
      end

      def agent_summary(agent)
        {
          id: agent.id,
          name: agent.name,
          description: agent.description,
          agent_type: agent.agent_type,
          status: agent.status,
          version: agent.version,
          last_executed_at: agent.last_executed_at&.iso8601
        }
      end

      def agent_details(agent)
        agent_summary(agent).merge(
          configuration: agent.configuration,
          capabilities: agent.mcp_capabilities,
          mcp_tool_manifest: agent.mcp_tool_manifest,
          execution_stats: agent.execution_stats
        )
      end
    end
  end
end
