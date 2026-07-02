# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

# Shared HTTP transport for server -> worker calls.
#
# Owns the plumbing every worker client (WorkerLlmClient, WorkerApiClient,
# WorkerEmbeddingClient) previously reimplemented: Net::HTTP setup (SSL,
# timeouts), the system-worker JWT bearer + JSON headers, response parsing,
# and typed error signaling. Base-URL resolution is unified on
# Rails.application.config.worker_url (WORKER_URL env, default
# http://localhost:4567); pass base_url: to override.
#
# Contract:
#   - 2xx  -> parsed JSON body (JSON::ParserError propagates; callers map it)
#   - !2xx -> raises HttpError (status + raw body + best-effort parsed body)
#   - timeouts -> raises TimeoutError; connect failures -> ConnectionError
#
# Callers translate these into their own error/result semantics.
class WorkerTransport
  class Error < StandardError; end
  class TimeoutError < Error; end
  class ConnectionError < Error; end

  class HttpError < Error
    attr_reader :status, :body, :parsed

    def initialize(message, status:, body:, parsed: nil)
      @status = status
      @body = body
      @parsed = parsed
      super(message)
    end
  end

  DEFAULT_OPEN_TIMEOUT = 10 # seconds
  DEFAULT_READ_TIMEOUT = 30 # seconds

  attr_reader :base_url

  def initialize(base_url: nil, open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT)
    @base_url = (base_url.presence || Rails.application.config.worker_url).to_s.chomp("/")
    @open_timeout = open_timeout
    @read_timeout = read_timeout
  end

  def get(path)
    request(:get, path)
  end

  def post(path, payload = {})
    request(:post, path, payload)
  end

  private

  def request(method, path, payload = nil)
    uri = URI("#{@base_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = @open_timeout
    http.read_timeout = @read_timeout

    req = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri)
    if method == :post
      req["Content-Type"] = "application/json"
      req.body = payload.to_json if payload
    end
    req["Accept"] = "application/json"
    req["Authorization"] = "Bearer #{WorkerJobService.system_worker_jwt}"

    response = http.request(req)
    status = response.code.to_i
    unless (200..299).cover?(status)
      parsed = begin
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        nil
      end
      raise HttpError.new("Worker returned HTTP #{status}", status: status, body: response.body, parsed: parsed)
    end

    JSON.parse(response.body)
  rescue Net::ReadTimeout, Net::OpenTimeout, Timeout::Error => e
    raise TimeoutError, e.message
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
    raise ConnectionError, e.message
  end
end
