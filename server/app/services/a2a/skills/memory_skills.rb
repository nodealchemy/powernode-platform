# frozen_string_literal: true

module A2a
  module Skills
    # MemorySkills - A2A skill implementations for agent memory operations
    class MemorySkills
      def initialize(account:, user: nil)
        @account = account
        @user = user
      end

      # Store memory
      def store(input, task = nil)
        agent = find_agent(input["agent_id"])
        memory_type = input["memory_type"] || "factual"

        memory_service = case memory_type
                         when "experiential"
                           Memory::ExperientialMemoryService.new(agent: agent, account: @account)
                         when "procedural"
                           Memory::ProceduralMemoryService.new(agent: agent, account: @account)
                         else
                           Memory::FactualMemoryService.new(agent: agent, account: @account)
                         end

        memory = memory_service.store(
          content: input["content"],
          context: input["context"] || {}
        )

        {
          output: {
            memory_id: memory.id,
            success: true,
            memory_type: memory_type
          }
        }
      end

      # Retrieve memories
      def retrieve(input, task = nil)
        agent = find_agent(input["agent_id"])

        retriever = Memory::ContextInjectorService.new(agent: agent, account: @account)

        memories = if input["query"].present?
                     retriever.search(query: input["query"], limit: input["limit"] || 10)
                   else
                     retriever.recent(limit: input["limit"] || 10)
                   end

        {
          output: {
            memories: memories.map { |m| memory_summary(m) }
          }
        }
      end

      # Inject memory context
      def inject(input, task = nil)
        agent = find_agent(input["agent_id"])

        injector = Memory::ContextInjectorService.new(agent: agent, account: @account)

        context = injector.build_context(
          task: input["task"],
          token_budget: input["token_budget"] || 2000
        )

        {
          output: {
            context: context
          }
        }
      end

      private

      def find_agent(id)
        @account.ai_agents.find(id)
      end

      def memory_summary(memory)
        {
          id: memory.id,
          memory_type: memory.memory_type,
          content: memory.content,
          importance: memory.importance,
          created_at: memory.created_at.iso8601
        }
      end
    end
  end
end
