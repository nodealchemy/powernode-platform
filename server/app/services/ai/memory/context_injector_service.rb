# frozen_string_literal: true

module Ai
  module Memory
    # Context Injector Service - Decides what memory enters LLM context
    # Manages token budget, relevance ranking across memory types
    # Prevents "context rot" by prioritizing high-value information
    class ContextInjectorService
      DEFAULT_TOKEN_BUDGET = 4000
      CHARS_PER_TOKEN = 4  # Rough estimate

      # Memory type priorities (higher = more important)
      MEMORY_PRIORITIES = {
        "factual" => 3,
        "working" => 2,
        "experiential" => 1
      }.freeze

      def initialize(agent:, account:)
        @agent = agent
        @account = account
        @factual_service = FactualMemoryService.new(agent: agent, account: account)
        @experiential_service = ExperientialMemoryService.new(agent: agent, account: account)
      end

      # Build optimized context for LLM injection
      def build_context(task: nil, query: nil, token_budget: DEFAULT_TOKEN_BUDGET, include_types: nil)
        budget_chars = token_budget * CHARS_PER_TOKEN
        context_parts = []
        used_chars = 0

        # Determine which memory types to include
        types = include_types || %w[factual working experiential]

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

        {
          context: context_parts.join("\n\n"),
          token_estimate: (used_chars / CHARS_PER_TOKEN.to_f).ceil,
          breakdown: {
            factual: context_parts.count { |p| p.start_with?("## Known Facts") },
            working: context_parts.count { |p| p.start_with?("## Current State") },
            experiential: context_parts.count { |p| p.start_with?("## Relevant Experience") }
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
        facts = @factual_service.all(limit: 50)
        return [nil, 0] if facts.empty?

        # Sort by importance and recency
        sorted_facts = facts.sort_by do |f|
          -(f[:importance_score] || 0.5) * (task_relevance_boost(f, task) || 1.0)
        end

        # Build context string within budget
        context_lines = ["## Known Facts"]
        used_chars = context_lines.first.length + 2

        sorted_facts.each do |fact|
          line = format_fact(fact)
          break if used_chars + line.length > char_budget

          context_lines << line
          used_chars += line.length + 1
        end

        return [nil, 0] if context_lines.size == 1  # Only header

        [context_lines.join("\n"), used_chars]
      end

      def inject_working_memory(char_budget, task)
        return [nil, 0] unless task

        working_service = WorkingMemoryService.new(
          agent: @agent,
          account: @account,
          task: task
        )

        memory = working_service.all
        return [nil, 0] if memory.empty?

        context_lines = ["## Current State"]
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

        return [nil, 0] if context_lines.size == 1

        [context_lines.join("\n"), used_chars]
      end

      def inject_experiential_memory(char_budget, query)
        return [nil, 0] if query.blank?

        # Search for relevant experiences
        experiences = @experiential_service.search(query, limit: 10, threshold: 0.6)
        return [nil, 0] if experiences.empty?

        context_lines = ["## Relevant Experience"]
        used_chars = context_lines.first.length + 2

        experiences.each do |exp|
          line = format_experience(exp)
          break if used_chars + line.length > char_budget

          context_lines << line
          used_chars += line.length + 1
        end

        return [nil, 0] if context_lines.size == 1

        [context_lines.join("\n"), used_chars]
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
