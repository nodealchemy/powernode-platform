# frozen_string_literal: true

module Ai
  module Rag
    class RerankingService
      include Ai::Concerns::PromptTemplateLookup
      include AgentBackedService

      BATCH_SIZE = 10
      FALLBACK_MODEL = "gpt-4.1"

      PROMPT_SLUG = "ai-rag-relevance-scoring"
      FALLBACK_PROMPT = "You are a relevance scoring expert. Score each passage for relevance to the query. " \
                        "Return a relevance score between 0.0 (irrelevant) and 1.0 (highly relevant) for each passage. " \
                        "Consider semantic relevance, not just keyword matching."

      RERANKING_SCHEMA = {
        name: "relevance_scores",
        schema: {
          type: "object",
          properties: {
            scores: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  index: { type: "integer" },
                  relevance: { type: "number", minimum: 0, maximum: 1 }
                },
                required: %w[index relevance]
              }
            }
          },
          required: %w[scores]
        }
      }.freeze

      def initialize(account)
        @account = account
      end

      # Rerank results using LLM or heuristic fallback
      def rerank(query:, results:, model: nil, top_k: nil)
        return [] if results.blank?

        top_k ||= results.size
        model ||= resolve_reranking_model

        # Attempt LLM-based reranking
        reranked = llm_rerank(query, results, model)

        # Fall back to heuristic if LLM unavailable
        reranked = heuristic_rerank(query, results) if reranked.nil?

        reranked.first(top_k)
      end

      private

      def llm_rerank(query, results, model)
        agent = discover_service_agent(
          "Score and rerank RAG search results by semantic relevance to a query",
          fallback_slug: "rag-reranker"
        )
        return nil unless agent

        client = build_agent_client(agent)

        all_scores = []

        # Process in batches
        results.each_slice(BATCH_SIZE).with_index do |batch, batch_idx|
          batch_scores = score_batch(client, query, batch, model, batch_idx * BATCH_SIZE)
          all_scores.concat(batch_scores) if batch_scores
        end

        return nil if all_scores.empty?

        # Merge scores back to results
        results.each_with_index.map do |result, idx|
          score_entry = all_scores.find { |s| s["index"] == idx }
          relevance = score_entry ? score_entry["relevance"].to_f : 0.0
          result.merge(rerank_score: relevance.round(4))
        end.sort_by { |r| -(r[:rerank_score] || 0) }
      rescue StandardError => e
        Rails.logger.warn "[RerankingService] LLM reranking failed: #{e.message}"
        nil
      end

      def score_batch(client, query, batch, model, offset)
        passages = batch.each_with_index.map do |result, idx|
          content = result[:content].to_s.truncate(500)
          "[#{offset + idx}] #{content}"
        end.join("\n\n")

        system_content = resolve_prompt_template(
          PROMPT_SLUG,
          account: @account,
          fallback: FALLBACK_PROMPT
        )

        messages = [
          {
            role: "system",
            content: system_content
          },
          {
            role: "user",
            content: "Query: #{query}\n\nPassages:\n#{passages}"
          }
        ]

        response = client.complete_structured(
          messages: messages,
          schema: RERANKING_SCHEMA,
          model: model
        )

        return nil unless response.success?

        parsed = response.parsed_content || response.content
        parsed = JSON.parse(parsed) if parsed.is_a?(String)
        parsed["scores"]
      rescue StandardError => e
        Rails.logger.warn "[RerankingService] Batch scoring failed: #{e.message}"
        nil
      end

      def resolve_reranking_model
        router = Ai::ModelRouterService.new(account: @account, strategy: "quality_optimized")
        routing = router.route_for_task(task_type: "analysis")
        routing[:recommended_models]&.first || FALLBACK_MODEL
      rescue StandardError => e
        Rails.logger.debug "[RerankingService] Model resolution via router failed, using fallback: #{e.message}"
        FALLBACK_MODEL
      end

      def heuristic_rerank(query, results)
        query_terms = query.downcase.split(/\s+/).reject { |w| w.length < 3 }.uniq

        results.each_with_index.map do |result, idx|
          content = (result[:content] || "").downcase

          # Keyword overlap score
          overlap = query_terms.count { |term| content.include?(term) }
          keyword_score = query_terms.any? ? overlap.to_f / query_terms.size : 0.0

          # Position boost (earlier results get slight boost)
          position_score = 1.0 / (1.0 + idx * 0.1)

          # Original score contribution
          original_score = result[:score] || 0.0

          # Combined heuristic score
          combined = (original_score * 0.5) + (keyword_score * 0.3) + (position_score * 0.2)

          result.merge(rerank_score: combined.round(4))
        end.sort_by { |r| -(r[:rerank_score] || 0) }
      end
    end
  end
end
