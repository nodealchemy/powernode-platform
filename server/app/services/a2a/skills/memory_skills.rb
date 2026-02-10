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

        storage = Memory::StorageService.new(account: @account, agent: agent)

        memory = case memory_type
        when "experiential"
                   storage.store_experiential(
                     content: input["content"],
                     context: input["context"] || {}
                   )
        else
                   storage.store_fact(
                     key: input["key"] || "fact_#{Time.current.to_i}",
                     value: input["content"],
                     metadata: input["context"] || {}
                   )
        end

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
