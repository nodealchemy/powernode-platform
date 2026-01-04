# frozen_string_literal: true

module Mcp
  module Orchestrator
    module ContextManagement
      # ==================== Persistent Context Loading ====================

      # Load persistent contexts for the workflow execution
      # Called during initialization to make contexts available to nodes
      def load_persistent_contexts
        @execution_context[:persistent_contexts] ||= {}
        @execution_context[:agent_memories] ||= {}
        @execution_context[:knowledge_bases] ||= {}

        # Load workflow-specific context if configured
        load_workflow_contexts

        # Load agent memories for all agents referenced in the workflow
        load_agent_memories

        # Load account-level knowledge bases
        load_knowledge_bases

        @logger.info "[MCP_ORCHESTRATOR] Loaded persistent contexts: " \
                     "#{@execution_context[:agent_memories].keys.count} agent memories, " \
                     "#{@execution_context[:knowledge_bases].keys.count} knowledge bases"
      end

      # Get persistent context by ID
      def get_persistent_context(context_id)
        return nil unless context_id.present?

        # Check cached contexts first
        cached = @execution_context.dig(:persistent_contexts, context_id)
        return cached if cached.present?

        # Load from database
        context = AiPersistentContext.find_by(id: context_id, account_id: @account.id)
        return nil unless context.present?

        @execution_context[:persistent_contexts][context_id] = context
        context
      end

      # Get agent memory for a specific agent
      def get_agent_memory(agent_id)
        return nil unless agent_id.present?

        @execution_context.dig(:agent_memories, agent_id)
      end

      # Store value in agent memory during execution
      def store_agent_memory(agent:, key:, value:, metadata: {})
        return unless agent.present? && key.present?

        AiContextPersistenceService.store_memory(
          agent: agent,
          key: key,
          value: value,
          metadata: metadata.merge(
            workflow_run_id: @workflow_run.id,
            stored_at: Time.current.iso8601
          )
        )

        # Update cached memory
        if @execution_context[:agent_memories][agent.id].present?
          @execution_context[:agent_memories][agent.id][:entries][key] = value
        end
      end

      # Recall value from agent memory
      def recall_agent_memory(agent:, key:)
        return nil unless agent.present? && key.present?

        # Check cache first
        cached = @execution_context.dig(:agent_memories, agent.id, :entries, key)
        return cached if cached.present?

        # Load from service
        AiContextPersistenceService.recall_memory(agent: agent, key: key)
      end

      # Search relevant knowledge base entries
      def search_knowledge_base(query:, context_ids: nil, limit: 10)
        contexts_to_search = if context_ids.present?
          context_ids.map { |id| get_persistent_context(id) }.compact
        else
          @execution_context[:knowledge_bases].values.map { |kb| kb[:context] }.compact
        end

        results = []
        contexts_to_search.each do |context|
          search_results = AiContextPersistenceService.search(
            context: context,
            query: query,
            accessor: @user,
            limit: limit
          )
          results.concat(search_results.to_a)
        end

        results.sort_by { |r| -r.importance_score }.first(limit)
      end

      # ==================== Execution Context Management ====================

      def update_execution_context(node, output_data)
        @execution_context[:node_results][node.node_id] = output_data

        if output_data.is_a?(Hash)
          variable_mapping = node.configuration&.dig("output_variables") || {}

          variable_mapping.each do |var_name, output_path|
            value = extract_value_from_path(output_data, output_path)
            @execution_context[:variables][var_name] = value if value.present?
          end

          if output_data["variables"].is_a?(Hash)
            @execution_context[:variables].merge!(output_data["variables"])
          end
        end

        serializable_context = @execution_context.except(:node_results).deep_dup
        @workflow_run.update_column(:runtime_context, serializable_context)
      end

      def extract_value_from_path(data, path)
        return data if path.blank?

        path.to_s.split(".").reduce(data) do |current, key|
          break nil unless current.is_a?(Hash) || current.is_a?(Array)

          if current.is_a?(Array) && key =~ /\A\d+\z/
            current[key.to_i]
          else
            current[key.to_s] || current[key.to_sym]
          end
        end
      end

      def execution_context
        @execution_context
      end

      def set_variable(name, value)
        @execution_context[:variables][name] = value
        serializable_context = @execution_context.except(:node_results).deep_dup
        @workflow_run.update_column(:runtime_context, serializable_context)
      end

      def get_variable(name)
        @execution_context[:variables][name]
      end

      def build_output_for_context(result)
        output_data = {}

        if result[:output].present?
          output_data["output"] = result[:output]
        end

        if result[:data].present? && result[:data].is_a?(Hash)
          output_data.merge!(result[:data])
        end

        if result[:result].present?
          output_data["result"] = result[:result]
        end

        output_data
      end

      private

      # ==================== Private Helper Methods ====================

      def load_workflow_contexts
        # Check if workflow has configured contexts
        workflow_config = @workflow.configuration || {}
        context_ids = workflow_config["persistent_context_ids"] || []

        context_ids.each do |context_id|
          context = AiPersistentContext.find_by(id: context_id, account_id: @account.id)
          next unless context.present?

          @execution_context[:persistent_contexts][context_id] = context
        end
      end

      def load_agent_memories
        # Find all agent nodes in the workflow
        agent_ids = @workflow.ai_workflow_nodes
          .where(node_type: "ai_agent")
          .pluck(:configuration)
          .map { |config| config&.dig("agent_id") }
          .compact
          .uniq

        # Also include any agents explicitly configured in workflow settings
        workflow_agent_ids = @workflow.configuration&.dig("agent_ids") || []
        agent_ids = (agent_ids + workflow_agent_ids).uniq

        agent_ids.each do |agent_id|
          agent = AiAgent.find_by(id: agent_id, account_id: @account.id)
          next unless agent.present?

          memory_context = AiContextPersistenceService.get_agent_memory(
            account: @account,
            agent: agent,
            create_if_missing: false
          )

          if memory_context.present?
            # Load recent/high-importance entries for quick access
            entries = memory_context.ai_context_entries
              .active
              .order(importance_score: :desc, updated_at: :desc)
              .limit(50)
              .each_with_object({}) { |e, h| h[e.entry_key] = e.content }

            @execution_context[:agent_memories][agent_id] = {
              agent: agent,
              context: memory_context,
              entries: entries
            }
          end
        end
      end

      def load_knowledge_bases
        # Load account-level knowledge bases
        knowledge_bases = AiPersistentContext
          .where(account_id: @account.id, context_type: "knowledge_base")
          .active
          .limit(10)

        knowledge_bases.each do |kb|
          @execution_context[:knowledge_bases][kb.id] = {
            context: kb,
            name: kb.name,
            entry_count: kb.entry_count
          }
        end

        # Load workflow-specific knowledge base if configured
        workflow_kb_id = @workflow.configuration&.dig("knowledge_base_id")
        if workflow_kb_id.present? && !@execution_context[:knowledge_bases].key?(workflow_kb_id)
          kb = AiPersistentContext.find_by(id: workflow_kb_id, account_id: @account.id)
          if kb.present?
            @execution_context[:knowledge_bases][kb.id] = {
              context: kb,
              name: kb.name,
              entry_count: kb.entry_count
            }
          end
        end
      end
    end
  end
end
