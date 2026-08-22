# frozen_string_literal: true

# Client for communicating with the worker service
# Used by backend to queue jobs in the worker's Sidekiq instance
class WorkerApiClient
  class ApiError < StandardError; end
  class AuthenticationError < ApiError; end
  class NetworkError < ApiError; end

  TIMEOUT = 10 # seconds

  # Base-URL resolution is unified across all worker clients on
  # Rails.application.config.worker_url (WORKER_URL env) via WorkerTransport.
  def initialize(base_url: nil)
    @transport = WorkerTransport.new(base_url: base_url, open_timeout: TIMEOUT, read_timeout: TIMEOUT)
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
    queue_job("Git::CredentialSetupJob", [ credential_id, options ], queue: "services")
  end

  # Queue a Git repository sync job
  # @param credential_id [String] GitProviderCredential ID
  # @return [Hash] Response from worker
  def queue_git_repository_sync(credential_id)
    queue_job("Git::RepositorySyncJob", [ credential_id ], queue: "services")
  end

  # NOTE: fleet-substrate (System) extension job dispatch (module/disk-image publication
  # processing, retention sweeps) lives in the extension itself — it enqueues its own jobs via
  # the slug-agnostic #queue_job primitive below, so this core client never names an extension job.

  # Queue a Git pipeline sync job
  # @param repository_id [String] GitRepository ID
  # @param external_pipeline_id [String] Optional external pipeline ID to sync specific run
  # @return [Hash] Response from worker
  def queue_git_pipeline_sync(repository_id, external_pipeline_id = nil)
    args = external_pipeline_id ? [ repository_id, external_pipeline_id ] : [ repository_id ]
    queue_job("Git::PipelineSyncJob", args, queue: "services")
  end

  # Queue a Git webhook processing job
  # @param event_id [String] GitWebhookEvent ID
  # @return [Hash] Response from worker
  def queue_git_webhook_processing(event_id)
    queue_job("Git::WebhookProcessingJob", [ event_id ], queue: "webhooks")
  end

  # Queue a Git job logs sync job
  # @param job_id [String] GitPipelineJob ID
  # @param options [Hash] Options including repository_id, pipeline_id, streaming
  # @return [Hash] Response from worker
  def queue_git_job_logs_sync(job_id, options = {})
    queue_job("Git::JobLogsSyncJob", [ job_id, options ], queue: "services")
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

  # Worker job class for a FileManagement::ProcessingJob type. The media jobs
  # live under the worker's FileProcessing:: namespace (alongside
  # FileProcessing::VirusScanJob) and MUST be named fully-qualified here — the
  # worker resolves this string with Object.const_get, so a bare name is a 422
  # "Invalid job class" that never enqueues.
  def job_class_for_type(job_type)
    case job_type
    when "thumbnail"
      "FileProcessing::ThumbnailGenerationJob"
    when "metadata_extract"
      "FileProcessing::MetadataExtractionJob"
    when "video_processing"
      "FileProcessing::VideoProcessingJob"
    when "audio_processing"
      "FileProcessing::AudioProcessingJob"
    when "video_stitching"
      "VideoStitchingJob"
    when "document_generation"
      "DocumentGenerationJob"
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

  # Shared Net::HTTP + JWT plumbing lives in WorkerTransport; this maps its
  # typed errors onto the client's ApiError hierarchy.
  def request(method, path, body = nil)
    method == :get ? @transport.get(path) : @transport.post(path, body)
  rescue WorkerTransport::HttpError => e
    raise AuthenticationError, "Worker service authentication failed" if e.status == 401

    raise ApiError, "Worker API returned #{e.status}: #{e.body}"
  rescue JSON::ParserError => e
    Rails.logger.warn "[WorkerApiClient] Failed to parse JSON response: #{e.message}"
    {}
  rescue WorkerTransport::TimeoutError, WorkerTransport::ConnectionError => e
    raise NetworkError, "Cannot connect to worker service: #{e.message}"
  end
end
