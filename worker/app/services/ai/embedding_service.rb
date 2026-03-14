# frozen_string_literal: true

module Ai
  # Worker-side embedding service -- generates vector embeddings by calling
  # AI providers directly (OpenAI, Ollama).
  #
  # Mirrors server's Ai::Memory::EmbeddingService interface but uses
  # CredentialResolver instead of ActiveRecord for credential access.
  #
  # Usage:
  #   service = Ai::EmbeddingService.new(
  #     api_post_method: method(:backend_api_post),
  #     provider_type: "openai",
  #     credential_id: "uuid"
  #   )
  #   embedding = service.generate("Hello world")
  #   # => [0.123, -0.456, ...]
  #
  class EmbeddingService
    EMBEDDING_DIMENSION = 1536 # OpenAI text-embedding-3-small dimension
    CACHE_PREFIX = "ai:embeddings"
    CACHE_TTL = 7 * 24 * 3600 # 7 days in seconds

    # @param api_post_method [Method] bound backend_api_post for credential resolution
    # @param provider_type [String] "openai" or "ollama"
    # @param credential_id [String] UUID of the provider credential (for OpenAI)
    # @param account_id [String] account UUID for cache scoping
    # @param ollama_url [String] Ollama base URL (for ollama provider)
    # @param ollama_model [String] Ollama embedding model name
    def initialize(api_post_method:, provider_type:, credential_id: nil, account_id:,
                   ollama_url: nil, ollama_model: nil)
      @api_post = api_post_method
      @provider_type = provider_type
      @credential_id = credential_id
      @account_id = account_id
      @ollama_url = ollama_url || ENV.fetch("OLLAMA_URL", "http://localhost:11434")
      @ollama_model = ollama_model || "nomic-embed-text"
      @credential_resolver = CredentialResolver.new(api_post_method)
      @redis = build_redis
    end

    # Generate embedding for text
    # @param text [String] text to embed
    # @param use_cache [Boolean] whether to check/store in Redis cache
    # @return [Array<Float>, nil] embedding vector or nil on failure
    def generate(text, use_cache: true)
      return nil if text.blank?

      normalized = normalize_text(text)
      cache_key = build_cache_key(normalized)

      if use_cache
        cached = @redis.get(cache_key)
        return JSON.parse(cached) if cached
      end

      embedding = generate_from_provider(normalized)
      return nil unless embedding

      @redis.set(cache_key, embedding.to_json, ex: CACHE_TTL) if use_cache
      embedding
    end

    # Batch generate embeddings
    # @param texts [Array<String>] texts to embed
    # @param use_cache [Boolean] whether to check/store in Redis cache
    # @return [Array<Array<Float>>] embedding vectors
    def generate_batch(texts, use_cache: true)
      return [] if texts.blank?

      results = []
      uncached_indices = []
      uncached_texts = []

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

      if uncached_texts.any?
        new_embeddings = generate_batch_from_provider(uncached_texts)

        uncached_indices.each_with_index do |original_index, batch_index|
          embedding = new_embeddings[batch_index]
          results[original_index] = embedding

          if use_cache && embedding
            normalized = normalize_text(texts[original_index])
            cache_key = build_cache_key(normalized)
            @redis.set(cache_key, embedding.to_json, ex: CACHE_TTL)
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

    private

    def normalize_text(text)
      text.to_s
          .strip
          .gsub(/\s+/, " ")
          .truncate(8000)
    end

    def build_cache_key(text)
      hash = Digest::SHA256.hexdigest(text)[0..15]
      "#{CACHE_PREFIX}:#{@account_id}:#{hash}"
    end

    def generate_from_provider(text)
      case @provider_type
      when "openai"
        generate_openai_embedding(text)
      when "ollama"
        generate_ollama_embedding(text)
      else
        # Try OpenAI as fallback
        generate_openai_embedding(text)
      end
    rescue StandardError => e
      logger.error "[EmbeddingService] Failed to generate embedding: #{e.message}"
      nil
    end

    def generate_batch_from_provider(texts)
      case @provider_type
      when "openai"
        generate_openai_batch_embeddings(texts)
      when "ollama"
        texts.map { |t| generate_ollama_embedding(t) }
      else
        generate_openai_batch_embeddings(texts)
      end
    rescue StandardError => e
      logger.error "[EmbeddingService] Failed to generate batch embeddings: #{e.message}"
      texts.map { nil }
    end

    def generate_openai_embedding(text)
      api_key = resolve_api_key
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

    def generate_openai_batch_embeddings(texts)
      api_key = resolve_api_key
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

    def generate_ollama_embedding(text)
      response = HTTParty.post(
        "#{@ollama_url}/api/embeddings",
        headers: { "Content-Type" => "application/json" },
        body: { model: @ollama_model, prompt: text }.to_json,
        timeout: 30
      )

      parsed = JSON.parse(response.body)
      embedding = parsed["embedding"]
      unless embedding
        raise "Ollama returned no embedding: #{parsed['error'] || 'unknown error'}"
      end

      embedding
    end

    def resolve_api_key
      return nil unless @credential_id

      credentials = @credential_resolver.resolve(@credential_id)
      credentials&.dig("api_key")
    end

    def build_redis
      Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
    end

    def logger
      @logger ||= PowernodeWorker.application.logger
    end
  end
end
