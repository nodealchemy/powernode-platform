# frozen_string_literal: true

# Client for communicating with the worker service
# Used by backend to queue jobs in the worker's Sidekiq instance
class WorkerApiClient
  class ApiError < StandardError; end
  class AuthenticationError < ApiError; end
  class NetworkError < ApiError; end

  def initialize(base_url: nil)
    # Use provided base_url or detect from environment
    @base_url = base_url || ENV.fetch("API_BASE_URL", detect_base_url)
    @service_token = ENV["WORKER_SERVICE_TOKEN"] ||
                     Rails.application.credentials.dig(:worker, :service_token) ||
                     "development_worker_service_token_that_persists_across_restarts"
    @timeout = 10 # seconds
  end

  # Queue a file processing job
  # @param job_id [String] FileProcessingJob ID
  # @param job_type [String] Type of job (thumbnail, metadata_extract, etc.)
  # @return [Hash] Response from worker
  def queue_file_processing_job(job_id, job_type)
    post("/api/v1/jobs", {
      job_class: job_class_for_type(job_type),
      args: [ job_id ],
      queue: "file_processing"
    })
  rescue StandardError => e
    Rails.logger.error "[WorkerApiClient] Failed to queue job #{job_id}: #{e.message}"
    raise ApiError, "Failed to queue job: #{e.message}"
  end

  # Health check
  def health_check
    get("/health")
  rescue StandardError
    { status: "unavailable" }
  end

  # Queue a Git credential setup job
  # @param credential_id [String] GitProviderCredential ID
  # @param options [Hash] Additional options (e.g., skip_repo_sync: true)
  # @return [Hash] Response from worker
  def queue_git_credential_setup(credential_id, options = {})
    queue_job("Git::CredentialSetupJob", [credential_id, options], queue: "services")
  end

  # Queue a Git repository sync job
  # @param credential_id [String] GitProviderCredential ID
  # @return [Hash] Response from worker
  def queue_git_repository_sync(credential_id)
    queue_job("Git::RepositorySyncJob", [credential_id], queue: "services")
  end

  # Queue a Git pipeline sync job
  # @param repository_id [String] GitRepository ID
  # @param external_pipeline_id [String] Optional external pipeline ID to sync specific run
  # @return [Hash] Response from worker
  def queue_git_pipeline_sync(repository_id, external_pipeline_id = nil)
    args = external_pipeline_id ? [repository_id, external_pipeline_id] : [repository_id]
    queue_job("Git::PipelineSyncJob", args, queue: "services")
  end

  # Queue a Git webhook processing job
  # @param event_id [String] GitWebhookEvent ID
  # @return [Hash] Response from worker
  def queue_git_webhook_processing(event_id)
    queue_job("Git::WebhookProcessingJob", [event_id], queue: "webhooks")
  end

  # Queue a Git job logs sync job
  # @param job_id [String] GitPipelineJob ID
  # @param options [Hash] Options including repository_id, pipeline_id, streaming
  # @return [Hash] Response from worker
  def queue_git_job_logs_sync(job_id, options = {})
    queue_job("Git::JobLogsSyncJob", [job_id, options], queue: "services")
  end

  # Generic job queueing method
  # @param job_class [String] Full job class name
  # @param args [Array] Job arguments
  # @param queue [String] Target queue name
  # @param options [Hash] Additional Sidekiq options
  # @return [Hash] Response from worker
  def queue_job(job_class, args = [], queue: nil, **options)
    payload = {
      job_class: job_class,
      args: args
    }
    payload[:queue] = queue if queue
    payload[:options] = options if options.any?

    post("/api/v1/jobs", payload)
  rescue StandardError => e
    Rails.logger.error "[WorkerApiClient] Failed to queue #{job_class}: #{e.message}"
    raise ApiError, "Failed to queue job: #{e.message}"
  end

  private

  def job_class_for_type(job_type)
    case job_type
    when "thumbnail"
      "ThumbnailGenerationJob"
    when "metadata_extract"
      "MetadataExtractionJob"
    when "video_processing"
      "VideoProcessingJob"
    when "audio_processing"
      "AudioProcessingJob"
    else
      raise ApiError, "Unknown job type: #{job_type}"
    end
  end

  def get(path)
    request(:get, path)
  end

  def post(path, body = {})
    request(:post, path, body)
  end

  def request(method, path, body = nil)
    uri = URI.join(@base_url, path)

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = @timeout
    http.read_timeout = @timeout

    request = case method
    when :get
                Net::HTTP::Get.new(uri.request_uri)
    when :post
                req = Net::HTTP::Post.new(uri.request_uri)
                req["Content-Type"] = "application/json"
                req.body = body.to_json if body
                req
    end

    request["Authorization"] = "Bearer #{@service_token}"
    request["Accept"] = "application/json"

    response = http.request(request)

    case response
    when Net::HTTPSuccess
      begin
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        Rails.logger.warn "[WorkerApiClient] Failed to parse JSON response: #{e.message}"
        {}
      end
    when Net::HTTPUnauthorized
      raise AuthenticationError, "Worker service authentication failed"
    else
      raise ApiError, "Worker API returned #{response.code}: #{response.body}"
    end
  rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
    raise NetworkError, "Cannot connect to worker service: #{e.message}"
  end

  def detect_base_url
    # Detect base URL from Rails configuration or environment
    # Worker service runs on its own port (default 4567)
    ENV.fetch("WORKER_API_URL") do
      if Rails.env.production? || Rails.env.staging?
        ENV.fetch("WORKER_SERVICE_URL") { raise "WORKER_SERVICE_URL environment variable must be set in production" }
      else
        # Development: worker service runs on port 4567
        "http://localhost:#{ENV.fetch('WORKER_PORT', 4567)}"
      end
    end
  end
end
