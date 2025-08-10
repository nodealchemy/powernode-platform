require 'sidekiq'

# Base class for all Sidekiq workers
class BaseWorker
  include Sidekiq::Worker

  def initialize
    @api_client = ApiClient.new
  end

  protected

  attr_reader :api_client

  def log_info(message, context = {})
    Sidekiq.logger.info "#{self.class.name}: #{message} #{context_string(context)}"
  end

  def log_error(message, error = nil, context = {})
    error_details = error ? " - #{error.class}: #{error.message}" : ""
    Sidekiq.logger.error "#{self.class.name}: #{message}#{error_details} #{context_string(context)}"
    Sidekiq.logger.error error.backtrace.join("\n") if error&.backtrace
  end

  def log_warn(message, context = {})
    Sidekiq.logger.warn "#{self.class.name}: #{message} #{context_string(context)}"
  end

  def create_audit_log(account_id:, action:, resource_type:, resource_id:, user_id: nil, metadata: {})
    api_client.create_audit_log(
      account_id: account_id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      user_id: user_id,
      metadata: metadata.merge(
        worker_class: self.class.name,
        job_id: jid,
        processed_at: Time.now.utc.iso8601
      )
    )
  rescue ApiClient::ApiError => e
    log_error("Failed to create audit log", e)
  end

  def handle_api_error(error, context = {})
    case error.status
    when 401, 403
      log_error("Authentication/authorization failed", error, context)
      # Don't retry auth failures
      raise error
    when 404
      log_warn("Resource not found", context.merge(error: error.message))
      # Don't retry not found errors
      raise error
    when 422
      log_error("Validation error", error, context)
      # Don't retry validation errors
      raise error
    when 429
      log_warn("Rate limited, will retry", context)
      # Let Sidekiq handle retry for rate limits
      raise error
    else
      log_error("API error", error, context)
      raise error
    end
  end

  private

  def context_string(context)
    return "" if context.empty?
    
    context_pairs = context.map { |k, v| "#{k}=#{v}" }
    "[#{context_pairs.join(', ')}]"
  end
end