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
    @worker_url = Rails.application.config.worker_url
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

  def make_request(path, payload)
    uri = URI("#{@worker_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.read_timeout = TIMEOUT
    http.open_timeout = 5

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request["Authorization"] = "Bearer #{WorkerJobService.system_worker_jwt}"
    request.body = payload.to_json

    response = http.request(request)

    case response.code.to_i
    when 200..299
      JSON.parse(response.body)
    else
      Rails.logger.error "[WorkerEmbeddingClient] Request failed (#{response.code}): #{response.body}"
      nil
    end
  rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNREFUSED, SocketError => e
    Rails.logger.error "[WorkerEmbeddingClient] Connection error: #{e.message}"
    nil
  end
end
