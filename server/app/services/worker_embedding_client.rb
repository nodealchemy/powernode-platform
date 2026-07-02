# frozen_string_literal: true

# Thin HTTP client that proxies embedding generation to the worker service.
# Replaces direct OpenAI/Ollama calls in the server's EmbeddingService.
#
# The worker generates embeddings by calling AI providers directly, while
# the server handles caching and storage (pgvector columns).
#
# Usage:
#   client = WorkerEmbeddingClient.new
#   embedding = client.generate("Hello world", account_id: account.id)
#   embeddings = client.generate_batch(["Hello", "World"], account_id: account.id)
#
class WorkerEmbeddingClient
  TIMEOUT = 30 # seconds

  def initialize
    @transport = WorkerTransport.new(open_timeout: 5, read_timeout: TIMEOUT)
  end

  # Generate a single embedding via the worker
  # @param text [String] text to embed
  # @param account_id [String] account UUID for provider resolution
  # @return [Array<Float>, nil] embedding vector
  def generate(text, account_id:)
    response = make_request("/api/v1/embeddings/generate", {
      text: text,
      account_id: account_id
    })

    response&.dig("embedding")
  end

  # Generate batch embeddings via the worker
  # @param texts [Array<String>] texts to embed
  # @param account_id [String] account UUID for provider resolution
  # @return [Array<Array<Float>>] embedding vectors
  def generate_batch(texts, account_id:)
    response = make_request("/api/v1/embeddings/batch", {
      texts: texts,
      account_id: account_id
    })

    response&.dig("embeddings") || []
  end

  private

  # Shared Net::HTTP + JWT plumbing lives in WorkerTransport; this maps its
  # typed errors onto the client's nil-on-failure semantics.
  def make_request(path, payload)
    @transport.post(path, payload)
  rescue WorkerTransport::HttpError => e
    Rails.logger.error "[WorkerEmbeddingClient] Request failed (#{e.status}): #{e.body}"
    nil
  rescue WorkerTransport::TimeoutError, WorkerTransport::ConnectionError => e
    Rails.logger.error "[WorkerEmbeddingClient] Connection error: #{e.message}"
    nil
  end
end
