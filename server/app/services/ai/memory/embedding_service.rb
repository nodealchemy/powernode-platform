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
        @redis = redis_client
      end

      def redis_client
        if Rails.application.config.respond_to?(:redis_client) && Rails.application.config.redis_client
          Rails.application.config.redis_client
        else
          Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
        end
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
          .where("capabilities @> ?", [ "text_embedding" ].to_json)
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

        credential = build_credential

        case @provider&.provider_type
        when "openai"
          raise EmbeddingError, "No OpenAI credentials configured" unless credential
          generate_openai_embedding(credential, text)
        when "ollama"
          generate_ollama_embedding(text)
        else
          openai_fallback = find_openai_fallback
          if openai_fallback
            generate_openai_embedding(openai_fallback, text)
          else
            raise EmbeddingError, "No embedding provider available. #{@provider&.provider_type || 'Unknown'} does not support embeddings. Configure an OpenAI or Ollama provider."
          end
        end
      end

      def generate_batch_from_provider(texts)
        return texts.map { |t| generate_mock_embedding(t) } if Rails.env.test?

        credential = build_credential

        case @provider&.provider_type
        when "openai"
          raise EmbeddingError, "No OpenAI credentials configured" unless credential
          generate_openai_batch_embeddings(credential, texts)
        when "ollama"
          texts.map { |t| generate_ollama_embedding(t) }
        else
          openai_fallback = find_openai_fallback
          if openai_fallback
            generate_openai_batch_embeddings(openai_fallback, texts)
          else
            raise EmbeddingError, "No embedding provider available for batch generation. Configure an OpenAI or Ollama provider."
          end
        end
      end

      class EmbeddingError < StandardError; end

      def build_credential
        return nil unless @provider

        @account.ai_provider_credentials
          .where(ai_provider_id: @provider.id, is_active: true).first
      end

      def generate_openai_embedding(credential, text)
        api_key = credential.credentials["api_key"]
        return nil unless api_key

        response = HTTParty.post(
          "https://api.openai.com/v1/embeddings",
          headers: {
            "Authorization" => "Bearer #{api_key}",
            "Content-Type" => "application/json"
          },
          body: { model: "text-embedding-3-small", input: text }.to_json,
          timeout: 30
        )

        parsed = JSON.parse(response.body)
        parsed.dig("data", 0, "embedding")
      end

      def generate_openai_batch_embeddings(credential, texts)
        api_key = credential.credentials["api_key"]
        return texts.map { nil } unless api_key

        response = HTTParty.post(
          "https://api.openai.com/v1/embeddings",
          headers: {
            "Authorization" => "Bearer #{api_key}",
            "Content-Type" => "application/json"
          },
          body: { model: "text-embedding-3-small", input: texts }.to_json,
          timeout: 60
        )

        parsed = JSON.parse(response.body)
        data = parsed["data"] || []
        data.sort_by { |d| d["index"] }.map { |d| d["embedding"] }
      end

      def find_openai_fallback
        openai_provider = Ai::Provider
          .where(account_id: @account.id, provider_type: "openai")
          .active
          .first
        return nil unless openai_provider

        @account.ai_provider_credentials
          .where(ai_provider_id: openai_provider.id, is_active: true).first
      end

      def generate_ollama_embedding(text)
        ollama_url = @provider.configuration&.dig("base_url") || ENV.fetch("OLLAMA_URL", "http://localhost:11434")
        model = @provider.configuration&.dig("embedding_model") || "nomic-embed-text"

        response = HTTParty.post(
          "#{ollama_url}/api/embeddings",
          headers: { "Content-Type" => "application/json" },
          body: { model: model, prompt: text }.to_json,
          timeout: 30
        )

        parsed = JSON.parse(response.body)
        embedding = parsed["embedding"]
        raise EmbeddingError, "Ollama returned no embedding: #{parsed['error'] || 'unknown error'}" unless embedding

        embedding
      end

      # Generate deterministic mock embedding for testing
      def generate_mock_embedding(text)
        # Create a deterministic but useful mock embedding
        hash = Digest::SHA256.digest(text)
        seed = hash.bytes.sum

        rng = Random.new(seed)
        EMBEDDING_DIMENSION.times.map do
          rng.rand(-1.0..1.0)
        end.tap do |embedding|
          # Normalize to unit vector
          magnitude = Math.sqrt(embedding.sum { |x| x * x })
          embedding.map! { |x| x / magnitude } if magnitude.positive?
        end
      end
    end
  end
end
