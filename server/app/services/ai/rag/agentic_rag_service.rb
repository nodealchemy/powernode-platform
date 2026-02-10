# frozen_string_literal: true

module Ai
  module Rag
    class AgenticRagService
      MAX_ROUNDS = 3
      MIN_RELEVANT_RESULTS = 3
      MIN_AVG_SCORE = 0.6

      def initialize(account)
        @account = account
        @hybrid_search = HybridSearchService.new(account)
        @reranking = RerankingService.new(account)
      end

      # Agentic RAG: iteratively search and refine query until sufficient results found
      def retrieve(query:, max_rounds: MAX_ROUNDS, **opts)
        max_rounds = [max_rounds.to_i, 5].min
        search_history = []
        all_results = []
        current_query = query

        rounds_used = 0

        max_rounds.times do |round|
          rounds_used = round + 1

          # Search with current query
          search_result = @hybrid_search.search(
            query: current_query,
            mode: opts[:mode] || :hybrid,
            top_k: opts[:top_k] || 10,
            knowledge_base_id: opts[:knowledge_base_id]
          )

          results = search_result[:results] || []

          # Rerank results
          if opts[:enable_reranking] && results.any?
            results = @reranking.rerank(
              query: query, # Always rerank against original query
              results: results
            )
          end

          search_history << {
            round: rounds_used,
            query: current_query,
            results_count: results.size,
            avg_score: calculate_avg_score(results)
          }

          # Merge new results (deduplicate by id)
          existing_ids = all_results.map { |r| r[:id] }.to_set
          new_results = results.reject { |r| existing_ids.include?(r[:id]) }
          all_results.concat(new_results)

          # Check sufficiency
          if sufficient_results?(all_results)
            Rails.logger.info "[AgenticRag] Sufficient results after round #{rounds_used}"
            break
          end

          # If not last round, reformulate query
          if round < max_rounds - 1
            gaps = identify_gaps(query, all_results)
            reformed = reformulate_query(query, current_query, gaps)
            current_query = reformed || current_query
          end
        end

        # Sort final results by score
        final_results = all_results.sort_by { |r| -(r[:rerank_score] || r[:score] || 0) }

        # Synthesize answer from retrieved chunks
        answer = synthesize_answer(query, final_results)

        {
          answer: answer,
          sources: final_results.first(10).map { |r| { id: r[:id], content: r[:content]&.truncate(200), score: r[:rerank_score] || r[:score] } },
          search_history: search_history,
          rounds_used: rounds_used,
          total_results: final_results.size
        }
      end

      private

      def sufficient_results?(results)
        return false if results.size < MIN_RELEVANT_RESULTS

        relevant = results.select { |r| (r[:rerank_score] || r[:score] || 0) >= MIN_AVG_SCORE }
        relevant.size >= MIN_RELEVANT_RESULTS
      end

      def calculate_avg_score(results)
        return 0.0 if results.empty?

        scores = results.map { |r| r[:rerank_score] || r[:score] || 0 }
        (scores.sum / scores.size).round(4)
      end

      def identify_gaps(original_query, results)
        # Extract key terms from query that aren't well-covered in results
        query_terms = original_query.downcase.split(/\s+/).reject { |w| w.length < 3 }.uniq
        content_text = results.map { |r| (r[:content] || "").downcase }.join(" ")

        uncovered = query_terms.reject { |term| content_text.include?(term) }

        {
          uncovered_terms: uncovered,
          low_score_count: results.count { |r| (r[:score] || 0) < MIN_AVG_SCORE },
          total_results: results.size
        }
      end

      def reformulate_query(original_query, current_query, gaps)
        client = Ai::Llm::Client.for_account(@account)

        if client
          llm_reformulate(client, original_query, current_query, gaps)
        else
          heuristic_reformulate(original_query, gaps)
        end
      end

      def llm_reformulate(client, original_query, current_query, gaps)
        messages = [
          {
            role: "system",
            content: "You are a search query optimizer. Given an original query and search gaps, " \
                     "generate a better search query that might retrieve more relevant results. " \
                     "Return only the improved query text, nothing else."
          },
          {
            role: "user",
            content: "Original query: #{original_query}\n" \
                     "Current query: #{current_query}\n" \
                     "Uncovered terms: #{gaps[:uncovered_terms].join(', ')}\n" \
                     "Results so far: #{gaps[:total_results]} (#{gaps[:low_score_count]} low relevance)\n\n" \
                     "Generate an improved search query:"
          }
        ]

        response = client.complete(
          messages: messages,
          model: "gpt-4.1",
          max_tokens: 100
        )

        return nil unless response.success?

        reformulated = response.content&.strip
        reformulated.present? ? reformulated : nil
      rescue StandardError => e
        Rails.logger.warn "[AgenticRag] LLM reformulation failed: #{e.message}"
        nil
      end

      def heuristic_reformulate(original_query, gaps)
        # Simple heuristic: add uncovered terms and use synonyms
        uncovered = gaps[:uncovered_terms]
        return nil if uncovered.empty?

        "#{original_query} #{uncovered.join(' ')}"
      end

      def synthesize_answer(query, results)
        return nil if results.empty?

        client = Ai::Llm::Client.for_account(@account)
        return simple_synthesis(results) unless client

        context = results.first(5).map { |r| r[:content] }.compact.join("\n\n---\n\n")
        return simple_synthesis(results) if context.blank?

        messages = [
          {
            role: "system",
            content: "You are a helpful assistant. Answer the question based only on the provided context. " \
                     "If the context doesn't contain enough information, say so. Be concise and factual."
          },
          {
            role: "user",
            content: "Context:\n#{context}\n\nQuestion: #{query}"
          }
        ]

        response = client.complete(
          messages: messages,
          model: "gpt-4.1",
          max_tokens: 500
        )

        response.success? ? response.content : simple_synthesis(results)
      rescue StandardError => e
        Rails.logger.warn "[AgenticRag] Synthesis failed: #{e.message}"
        simple_synthesis(results)
      end

      def simple_synthesis(results)
        return nil if results.empty?

        results.first(3).map { |r| r[:content] }.compact.join("\n\n")&.truncate(1000)
      end
    end
  end
end
