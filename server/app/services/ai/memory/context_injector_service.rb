# frozen_string_literal: true

module Ai
  module Memory
    # Context Injector Service - Decides what memory enters LLM context
    # Manages token budget, relevance ranking across memory types
    # Prevents "context rot" by prioritizing high-value information
    class ContextInjectorService
      DEFAULT_TOKEN_BUDGET = 4000
      CHARS_PER_TOKEN = 4  # Rough estimate

      def initialize(agent:, account:)
        @agent = agent
        @account = account
        @storage_service = StorageService.new(account: account, agent: agent)
      end

      # Build optimized context for LLM injection
      def build_context(task: nil, query: nil, token_budget: DEFAULT_TOKEN_BUDGET, include_types: nil)
        budget_chars = token_budget * CHARS_PER_TOKEN
        context_parts = []
        used_chars = 0

        # Determine which memory types to include
        types = include_types || %w[factual working experiential trajectories shared_learnings compound_learnings graph_rag]

        # 1. Always include critical facts first (highest priority)
        if types.include?("factual")
          factual_context, factual_chars = inject_factual_memory(budget_chars - used_chars, task)
          context_parts << factual_context if factual_context.present?
          used_chars += factual_chars
        end

        # 2. Include working memory (current task state)
        if types.include?("working") && task.present?
          working_context, working_chars = inject_working_memory(budget_chars - used_chars, task)
          context_parts << working_context if working_context.present?
          used_chars += working_chars
        end

        # 3. Include relevant experiential memories
        if types.include?("experiential") && (query.present? || task.present?)
          search_query = query || extract_task_query(task)
          experiential_context, exp_chars = inject_experiential_memory(
            budget_chars - used_chars,
            search_query
          )
          context_parts << experiential_context if experiential_context.present?
          used_chars += exp_chars
        end

        # 4. Include relevant trajectory memories
        if types.include?("trajectories") && (query.present? || task.present?)
          search_query = query || extract_task_query(task)
          trajectory_context, traj_chars = inject_trajectory_memory(
            budget_chars - used_chars,
            search_query
          )
          context_parts << trajectory_context if trajectory_context.present?
          used_chars += traj_chars
        end

        # 5. Include shared learnings from cross-execution learning
        if types.include?("shared_learnings") && (query.present? || task.present?)
          search_query = query || extract_task_query(task)
          learnings_context, learnings_chars = inject_shared_learnings(
            budget_chars - used_chars,
            search_query
          )
          context_parts << learnings_context if learnings_context.present?
          used_chars += learnings_chars
        end

        # 6. Include compound learnings from the learning loop
        if types.include?("compound_learnings") && (query.present? || task.present?)
          search_query = query || extract_task_query(task)
          compound_context, compound_chars = inject_compound_learnings(
            budget_chars - used_chars,
            search_query
          )
          context_parts << compound_context if compound_context.present?
          used_chars += compound_chars
        end

        # 7. Include GraphRAG context (knowledge graph + RAG fusion)
        if types.include?("graph_rag") && (query.present? || task.present?)
          search_query = query || extract_task_query(task)
          graph_rag_context, graph_rag_chars = inject_graph_rag_memory(
            budget_chars - used_chars,
            search_query
          )
          context_parts << graph_rag_context if graph_rag_context.present?
          used_chars += graph_rag_chars
        end

        {
          context: context_parts.join("\n\n"),
          token_estimate: (used_chars / CHARS_PER_TOKEN.to_f).ceil,
          breakdown: {
            factual: context_parts.count { |p| p.start_with?("## Known Facts") },
            working: context_parts.count { |p| p.start_with?("## Current State") },
            experiential: context_parts.count { |p| p.start_with?("## Relevant Experience") },
            trajectories: context_parts.count { |p| p.start_with?("## Past Trajectories") },
            shared_learnings: context_parts.count { |p| p.start_with?("## Shared Learnings") },
            compound_learnings: context_parts.count { |p| p.start_with?("## Compound Learnings") },
            graph_rag: context_parts.count { |p| p.start_with?("## Graph Knowledge") }
          }
        }
      end

      # Build context for a specific query (semantic search focused)
      def build_query_context(query:, token_budget: DEFAULT_TOKEN_BUDGET)
        build_context(query: query, token_budget: token_budget, include_types: %w[factual experiential])
      end

      # Build minimal context (facts only)
      def build_minimal_context(token_budget: 1000)
        build_context(token_budget: token_budget, include_types: %w[factual])
      end

      # Preview what would be injected
      def preview_context(task: nil, query: nil, token_budget: DEFAULT_TOKEN_BUDGET)
        result = build_context(task: task, query: query, token_budget: token_budget)

        {
          preview: result[:context].truncate(500),
          token_estimate: result[:token_estimate],
          breakdown: result[:breakdown],
          within_budget: result[:token_estimate] <= token_budget
        }
      end

      private

      def inject_factual_memory(char_budget, task)
        facts = @storage_service.all_facts(limit: 50)
        return [ nil, 0 ] if facts.empty?

        # Sort by importance and recency
        sorted_facts = facts.sort_by do |f|
          -(f[:importance_score] || 0.5) * (task_relevance_boost(f, task) || 1.0)
        end

        # Build context string within budget
        context_lines = [ "## Known Facts" ]
        used_chars = context_lines.first.length + 2

        sorted_facts.each do |fact|
          line = format_fact(fact)
          break if used_chars + line.length > char_budget

          context_lines << line
          used_chars += line.length + 1
        end

        return [ nil, 0 ] if context_lines.size == 1  # Only header

        [ context_lines.join("\n"), used_chars ]
      end

      def inject_working_memory(char_budget, task)
        return [ nil, 0 ] unless task

        working_service = WorkingMemoryService.new(
          agent: @agent,
          account: @account,
          task: task
        )

        memory = working_service.all
        return [ nil, 0 ] if memory.empty?

        context_lines = [ "## Current State" ]
        used_chars = context_lines.first.length + 2

        # Prioritize task state and conversation context
        priority_keys = %w[task_state conversation_context scratch_pad]

        priority_keys.each do |key|
          next unless memory[key]

          line = format_working_memory(key, memory[key])
          break if used_chars + line.length > char_budget

          context_lines << line
          used_chars += line.length + 1
        end

        # Add other working memory
        memory.except(*priority_keys).each do |key, value|
          line = format_working_memory(key, value)
          break if used_chars + line.length > char_budget

          context_lines << line
          used_chars += line.length + 1
        end

        return [ nil, 0 ] if context_lines.size == 1

        [ context_lines.join("\n"), used_chars ]
      end

      def inject_trajectory_memory(char_budget, query)
        return [ nil, 0 ] if query.blank?

        trajectory_service = Ai::TrajectoryService.new(account: @account)
        context_text = trajectory_service.inject_context(
          agent_id: @agent.id,
          task_description: query,
          max_trajectories: 3
        )

        return [ nil, 0 ] if context_text.blank?

        # Truncate to budget
        if context_text.length > char_budget
          context_text = context_text.truncate(char_budget)
        end

        [ context_text, context_text.length ]
      end

      def inject_shared_learnings(char_budget, query)
        return [ nil, 0 ] if query.blank?

        storage = Ai::Memory::StorageService.new(account: @account)
        context_text = storage.build_learning_context(
          query: query,
          max_chars: char_budget
        )

        return [ nil, 0 ] if context_text.blank?

        [ context_text, context_text.length ]
      rescue StandardError => e
        Rails.logger.warn("[ContextInjector] Shared learnings injection failed: #{e.message}")
        [ nil, 0 ]
      end

      def inject_compound_learnings(char_budget, query)
        return [nil, 0] if query.blank?

        service = Ai::Learning::CompoundLearningService.new(account: @account)
        result = service.build_compound_context(
          agent: @agent,
          task_description: query,
          token_budget: char_budget / CHARS_PER_TOKEN
        )

        context_text = result[:context]
        return [nil, 0] if context_text.blank?

        if context_text.length > char_budget
          context_text = context_text.truncate(char_budget)
        end

        [context_text, context_text.length]
      rescue StandardError => e
        Rails.logger.warn("[ContextInjector] Compound learnings injection failed: #{e.message}")
        [nil, 0]
      end

      def inject_graph_rag_memory(char_budget, query)
        return [nil, 0] if query.blank?

        graph_rag = Ai::Rag::GraphRagService.new(account: @account)
        result = graph_rag.build_context(
          query: query,
          token_budget: char_budget / CHARS_PER_TOKEN
        )

        context_text = result[:context]
        return [nil, 0] if context_text.blank?

        if context_text.length > char_budget
          context_text = context_text.truncate(char_budget)
        end

        [context_text, context_text.length]
      rescue StandardError => e
        Rails.logger.warn("[ContextInjector] GraphRAG injection failed: #{e.message}")
        [nil, 0]
      end

      def inject_experiential_memory(char_budget, query)
        return [ nil, 0 ] if query.blank?

        # Search for relevant experiences
        experiences = @storage_service.search_experiential(query, limit: 10, threshold: 0.6)
        return [ nil, 0 ] if experiences.empty?

        context_lines = [ "## Relevant Experience" ]
        used_chars = context_lines.first.length + 2

        experiences.each do |exp|
          line = format_experience(exp)
          break if used_chars + line.length > char_budget

          context_lines << line
          used_chars += line.length + 1
        end

        return [ nil, 0 ] if context_lines.size == 1

        [ context_lines.join("\n"), used_chars ]
      end

      def format_fact(fact)
        key = fact[:entry_key]
        value = extract_value(fact[:content])
        "- #{key}: #{value}"
      end

      def format_working_memory(key, value)
        formatted_value = case value
        when Hash, Array
                            value.to_json.truncate(200)
        else
                            value.to_s.truncate(200)
        end

        "- #{key.humanize}: #{formatted_value}"
      end

      def format_experience(exp)
        content = exp[:content]
        outcome = exp[:outcome_success] ? "succeeded" : (exp[:outcome_success] == false ? "failed" : "unknown")
        similarity = exp[:similarity] ? " (#{(exp[:similarity] * 100).round}% relevant)" : ""

        summary = extract_value(content).truncate(150)
        "- [#{outcome}#{similarity}] #{summary}"
      end

      def extract_value(content)
        case content
        when Hash
          content["text"] || content["value"] || content["description"] || content.to_json.truncate(100)
        when String
          content
        else
          content.to_s
        end
      end

      def extract_task_query(task)
        return nil unless task

        # Extract searchable text from task
        message = task.message || {}
        parts = message["parts"] || []

        text_parts = parts.select { |p| p["type"] == "text" }.map { |p| p["text"] }
        text_parts.join(" ").truncate(200)
      end

      def task_relevance_boost(fact, task)
        return 1.0 unless task

        # Boost facts that match task context
        task_tags = task.metadata["tags"] || []
        fact_tags = fact[:context_tags] || []

        matching_tags = (task_tags & fact_tags).size
        1.0 + (matching_tags * 0.2)
      end
    end
  end
end
