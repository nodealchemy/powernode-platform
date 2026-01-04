# frozen_string_literal: true

module AiContext
  class EmbeddingGenerationJob < BaseJob
    sidekiq_options queue: 'ai',
                    retry: 3,
                    dead: true

    # Generate embeddings for context entries
    # Can generate for a single entry, a context, or batch process missing embeddings
    def execute(params = {})
      action = params[:action] || "batch"

      case action
      when "single"
        generate_single_embedding(params[:entry_id])
      when "context"
        generate_context_embeddings(params[:context_id], params)
      when "batch"
        batch_generate_missing_embeddings(params)
      when "refresh"
        refresh_stale_embeddings(params)
      else
        log_error("Unknown embedding action", action: action)
        { success: false, error: "Unknown action: #{action}" }
      end
    end

    private

    def generate_single_embedding(entry_id)
      unless entry_id
        return { success: false, error: "entry_id is required" }
      end

      log_info("Generating embedding for entry", entry_id: entry_id)

      # Fetch entry content
      response = api_client.get("/api/v1/internal/ai_context/entries/#{entry_id}")

      unless response[:success]
        return { success: false, error: "Failed to fetch entry: #{response[:error]}" }
      end

      entry = response[:data][:entry]
      content_text = entry[:content_text]

      unless content_text.present?
        return { success: false, error: "Entry has no content_text to embed" }
      end

      # Generate embedding
      embedding = generate_embedding(content_text)

      unless embedding
        return { success: false, error: "Failed to generate embedding" }
      end

      # Store embedding
      store_response = api_client.patch("/api/v1/internal/ai_context/entries/#{entry_id}", {
        embedding: embedding,
        embedding_updated_at: Time.current.iso8601
      })

      if store_response[:success]
        log_info("Embedding generated successfully", entry_id: entry_id)
        increment_counter("embedding_generated")
        { success: true, entry_id: entry_id }
      else
        log_error("Failed to store embedding", entry_id: entry_id, error: store_response[:error])
        { success: false, error: store_response[:error] }
      end
    rescue StandardError => e
      log_error("Embedding generation error", exception: e, entry_id: entry_id)
      { success: false, error: e.message }
    end

    def generate_context_embeddings(context_id, options = {})
      unless context_id
        return { success: false, error: "context_id is required" }
      end

      log_info("Generating embeddings for context", context_id: context_id)

      generated = 0
      failed = 0
      batch_size = options[:batch_size] || 50
      page = 1

      loop do
        # Fetch entries without embeddings
        response = api_client.get("/api/v1/internal/ai_context/entries", {
          context_id: context_id,
          without_embedding: true,
          page: page,
          per_page: batch_size
        })

        break unless response[:success]

        entries = response[:data][:entries] || []
        break if entries.empty?

        entries.each do |entry|
          result = generate_single_embedding(entry[:id])

          if result[:success]
            generated += 1
          else
            failed += 1
          end

          # Rate limit to avoid overwhelming the embedding service
          sleep(0.1)
        end

        # Check for more pages
        pagination = response[:data][:pagination]
        break if page >= (pagination[:total_pages] || 1)

        page += 1
      end

      log_info("Context embeddings generation completed",
               context_id: context_id,
               generated: generated,
               failed: failed)

      track_cleanup_metrics(
        embeddings_generated: generated,
        embeddings_failed: failed
      )

      { success: true, generated: generated, failed: failed }
    rescue StandardError => e
      log_error("Context embedding generation error", exception: e, context_id: context_id)
      { success: false, error: e.message }
    end

    def batch_generate_missing_embeddings(options = {})
      log_info("Batch generating missing embeddings")

      batch_size = options[:batch_size] || 100
      max_entries = options[:max_entries] || 1000
      generated = 0
      failed = 0
      processed = 0

      loop do
        # Fetch entries without embeddings
        response = api_client.get("/api/v1/internal/ai_context/entries", {
          without_embedding: true,
          has_content_text: true,
          page: 1,
          per_page: batch_size
        })

        break unless response[:success]

        entries = response[:data][:entries] || []
        break if entries.empty?

        entries.each do |entry|
          break if processed >= max_entries

          result = generate_single_embedding(entry[:id])

          if result[:success]
            generated += 1
          else
            failed += 1
          end

          processed += 1

          # Rate limit
          sleep(0.1)
        end

        break if processed >= max_entries
      end

      log_info("Batch embedding generation completed",
               processed: processed,
               generated: generated,
               failed: failed)

      track_cleanup_metrics(
        embeddings_batch_processed: processed,
        embeddings_batch_generated: generated,
        embeddings_batch_failed: failed
      )

      { success: true, processed: processed, generated: generated, failed: failed }
    rescue StandardError => e
      log_error("Batch embedding generation error", exception: e)
      { success: false, error: e.message }
    end

    def refresh_stale_embeddings(options = {})
      stale_days = options[:stale_days] || 30
      batch_size = options[:batch_size] || 50
      max_entries = options[:max_entries] || 500

      log_info("Refreshing stale embeddings", stale_days: stale_days)

      refreshed = 0
      failed = 0
      processed = 0

      loop do
        # Fetch entries with stale embeddings
        response = api_client.get("/api/v1/internal/ai_context/entries", {
          stale_embedding: true,
          stale_days: stale_days,
          page: 1,
          per_page: batch_size
        })

        break unless response[:success]

        entries = response[:data][:entries] || []
        break if entries.empty?

        entries.each do |entry|
          break if processed >= max_entries

          result = generate_single_embedding(entry[:id])

          if result[:success]
            refreshed += 1
          else
            failed += 1
          end

          processed += 1
          sleep(0.1)
        end

        break if processed >= max_entries
      end

      log_info("Stale embedding refresh completed",
               processed: processed,
               refreshed: refreshed,
               failed: failed)

      { success: true, processed: processed, refreshed: refreshed, failed: failed }
    rescue StandardError => e
      log_error("Stale embedding refresh error", exception: e)
      { success: false, error: e.message }
    end

    def generate_embedding(text)
      return nil if text.blank?

      # Call embedding service via backend
      response = api_client.post("/api/v1/internal/ai/embeddings", {
        text: text,
        model: embedding_model
      })

      return nil unless response[:success]

      response[:data][:embedding]
    rescue StandardError => e
      log_error("Failed to generate embedding", exception: e)
      nil
    end

    def embedding_model
      # Default to OpenAI text-embedding-3-small (1536 dimensions)
      ENV.fetch("EMBEDDING_MODEL", "text-embedding-3-small")
    end
  end
end
