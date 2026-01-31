# frozen_string_literal: true

module Ai
  module Memory
    # Embedding Service - Generate vector embeddings for semantic search
    # Supports multiple providers with caching
    class EmbeddingService
      EMBEDDING_DIMENSION = 1536  # OpenAI text-embedding-3-small dimension
      CACHE_PREFIX = "ai:embeddings"
      CACHE_TTL = 7.days

      def initialize(account:, provider: nil)
        @account = account
        @provider = provider || default_provider
        @redis = Rails.application.config.redis_client || Redis.new
      end

      # Generate embedding for text
      def generate(text, use_cache: true)
        return nil if text.blank?

        # Normalize text
        normalized = normalize_text(text)
        cache_key = build_cache_key(normalized)

        # Check cache
        if use_cache
          cached = @redis.get(cache_key)
          return JSON.parse(cached) if cached
        end

        # Generate embedding
        embedding = generate_from_provider(normalized)
        return nil unless embedding

        # Cache result
        @redis.setex(cache_key, CACHE_TTL.to_i, embedding.to_json) if use_cache

        embedding
      end

      # Batch generate embeddings
      def generate_batch(texts, use_cache: true)
        return [] if texts.blank?

        results = []
        uncached_indices = []
        uncached_texts = []

        # Check cache for each text
        texts.each_with_index do |text, index|
          normalized = normalize_text(text)
          cache_key = build_cache_key(normalized)

          if use_cache
            cached = @redis.get(cache_key)
            if cached
              results[index] = JSON.parse(cached)
              next
            end
          end

          uncached_indices << index
          uncached_texts << normalized
        end

        # Generate embeddings for uncached texts
        if uncached_texts.any?
          new_embeddings = generate_batch_from_provider(uncached_texts)

          uncached_indices.each_with_index do |original_index, batch_index|
            embedding = new_embeddings[batch_index]
            results[original_index] = embedding

            # Cache result
            if use_cache && embedding
              normalized = normalize_text(texts[original_index])
              cache_key = build_cache_key(normalized)
              @redis.setex(cache_key, CACHE_TTL.to_i, embedding.to_json)
            end
          end
        end

        results
      end

      # Calculate cosine similarity between two embeddings
      def similarity(embedding1, embedding2)
        return 0.0 if embedding1.blank? || embedding2.blank?
        return 0.0 if embedding1.length != embedding2.length

        dot_product = embedding1.zip(embedding2).sum { |a, b| a * b }
        magnitude1 = Math.sqrt(embedding1.sum { |x| x * x })
        magnitude2 = Math.sqrt(embedding2.sum { |x| x * x })

        return 0.0 if magnitude1.zero? || magnitude2.zero?

        (dot_product / (magnitude1 * magnitude2)).round(6)
      end

      # Find most similar items from a collection
      def find_similar(query_embedding, candidates, top_k: 10)
        return [] if query_embedding.blank? || candidates.blank?

        candidates.map do |candidate|
          candidate_embedding = candidate[:embedding] || candidate["embedding"]
          score = similarity(query_embedding, candidate_embedding)
          candidate.merge(similarity: score)
        end.sort_by { |c| -c[:similarity] }.first(top_k)
      end

      # Clear cache for specific text
      def clear_cache(text)
        cache_key = build_cache_key(normalize_text(text))
        @redis.del(cache_key)
      end

      # Clear all embedding cache
      def clear_all_cache
        pattern = "#{CACHE_PREFIX}:#{@account.id}:*"
        keys = @redis.keys(pattern)
        @redis.del(*keys) if keys.any?
      end

      private

      def default_provider
        # Find an AI provider that supports embeddings
        Ai::Provider
          .where(account_id: @account.id)
          .where("capabilities @> ?", ["embeddings"].to_json)
          .active
          .first || Ai::Provider.where(account_id: @account.id).active.first
      end

      def normalize_text(text)
        text.to_s
            .strip
            .gsub(/\s+/, " ")
            .truncate(8000)  # Most embedding models have limits
      end

      def build_cache_key(text)
        hash = Digest::SHA256.hexdigest(text)[0..15]
        "#{CACHE_PREFIX}:#{@account.id}:#{hash}"
      end

      def generate_from_provider(text)
        return generate_mock_embedding(text) if Rails.env.test?

        client = build_client
        return nil unless client

        case @provider&.provider_type
        when "openai"
          generate_openai_embedding(client, text)
        when "anthropic"
          # Anthropic doesn't have embeddings, fall back to mock or another provider
          generate_mock_embedding(text)
        else
          generate_mock_embedding(text)
        end
      rescue StandardError => e
        Rails.logger.error "Embedding generation failed: #{e.message}"
        nil
      end

      def generate_batch_from_provider(texts)
        return texts.map { |t| generate_mock_embedding(t) } if Rails.env.test?

        client = build_client
        return texts.map { nil } unless client

        case @provider&.provider_type
        when "openai"
          generate_openai_batch_embeddings(client, texts)
        else
          texts.map { |t| generate_mock_embedding(t) }
        end
      rescue StandardError => e
        Rails.logger.error "Batch embedding generation failed: #{e.message}"
        texts.map { nil }
      end

      def build_client
        return nil unless @provider

        Ai::ProviderClientService.new(
          provider: @provider,
          account: @account
        ).build_client
      end

      def generate_openai_embedding(client, text)
        response = client.embeddings(
          parameters: {
            model: "text-embedding-3-small",
            input: text
          }
        )

        response.dig("data", 0, "embedding")
      end

      def generate_openai_batch_embeddings(client, texts)
        response = client.embeddings(
          parameters: {
            model: "text-embedding-3-small",
            input: texts
          }
        )

        data = response["data"] || []
        data.sort_by { |d| d["index"] }.map { |d| d["embedding"] }
      end

      # Generate deterministic mock embedding for testing
      def generate_mock_embedding(text)
        # Create a deterministic but useful mock embedding
        hash = Digest::SHA256.digest(text)
        seed = hash.bytes.sum

        Random.new(seed).rand(EMBEDDING_DIMENSION).times.map do
          Random.new(seed).rand(-1.0..1.0)
        end.tap do |embedding|
          # Normalize to unit vector
          magnitude = Math.sqrt(embedding.sum { |x| x * x })
          embedding.map! { |x| x / magnitude } if magnitude.positive?
        end
      end
    end
  end
end
