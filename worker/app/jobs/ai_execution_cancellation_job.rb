# frozen_string_literal: true

class AiExecutionCancellationJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_cancellations', retry: 1

  def execute(execution_id)
    @execution = find_execution(execution_id)
    return unless @execution

    log_info("Processing cancellation for execution #{execution_id}")

    begin
      # Check if execution is still cancellable
      unless can_be_cancelled?
        log_warn("Execution #{execution_id} cannot be cancelled (status: #{@execution['status']})")
        return
      end

      # Cancel any active provider API calls
      cancel_provider_operations

      # Update execution status
      update_execution_status

      # Cleanup resources
      cleanup_execution_resources

      # Broadcast final cancellation status
      broadcast_cancellation_complete

      # Record cancellation metrics
      record_cancellation_metrics

      log_info("Successfully cancelled execution #{execution_id}")

    rescue StandardError => e
      handle_cancellation_error(e)
    end
  end

  private

  def find_execution(execution_id)
    response = backend_api_get("/api/v1/ai/agent_executions/#{execution_id}")
    return nil unless response['success']
    
    response['data']['execution']
  end

  def can_be_cancelled?
    return false unless @execution

    cancellable_statuses = %w[queued running processing]
    cancellable_statuses.include?(@execution['status'])
  end

  def cancel_provider_operations
    return unless @execution['metadata']

    # Cancel any ongoing API calls based on provider
    provider = @execution['ai_agent']['ai_provider']
    
    case provider['slug']
    when 'ollama'
      cancel_ollama_operations
    when 'openai'
      cancel_openai_operations
    when 'anthropic'
      cancel_anthropic_operations
    else
      cancel_generic_provider_operations
    end
  end

  def cancel_ollama_operations
    # For Ollama, we might need to send a cancellation request
    # if the API supports it, or just let the timeout handle it
    log_info("Cancelling Ollama operations for execution #{@execution['id']}")
    
    # If we stored the request ID or session info, we could cancel it here
    request_id = @execution['metadata']['ollama_request_id']
    if request_id.present?
      # Attempt to cancel the specific request
      # This is provider-specific implementation
      cancel_ollama_request(request_id)
    end
  end

  def cancel_openai_operations
    log_info("Cancelling OpenAI operations for execution #{@execution['id']}")
    
    # OpenAI doesn't have a direct cancellation API
    # We rely on request timeouts and status tracking
    # Mark any streaming connections as cancelled
    
    stream_id = @execution['metadata']['openai_stream_id']
    if stream_id.present?
      # Cancel streaming connection if applicable
      cancel_openai_stream(stream_id)
    end
  end

  def cancel_anthropic_operations
    log_info("Cancelling Anthropic operations for execution #{@execution['id']}")
    
    # Similar to OpenAI, Anthropic doesn't have direct cancellation
    # We handle this through timeout and status management
    
    message_id = @execution['metadata']['anthropic_message_id']
    if message_id.present?
      # Log the cancellation attempt
      log_info("Attempted to cancel Anthropic message #{message_id}")
    end
  end

  def cancel_generic_provider_operations
    log_info("Cancelling generic provider operations for execution #{@execution['id']}")
    
    # Generic cancellation logic for other providers
    # This can be extended based on provider capabilities
  end

  def cancel_ollama_request(request_id)
    begin
      # Get credentials to find Ollama base URL
      credential = get_execution_credential
      return unless credential

      creds_response = backend_api_post("/api/v1/ai/provider_credentials/#{credential['id']}/decrypt")
      return unless creds_response['success']

      decrypted_creds = creds_response['data']['credentials']
      base_url = decrypted_creds['base_url'] || 'http://localhost:11434'

      # Attempt cancellation request (if Ollama supports it)
      response = make_http_request(
        "#{base_url}/api/cancel",
        method: :post,
        headers: { 'Content-Type' => 'application/json' },
        body: { request_id: request_id }.to_json,
        timeout: 5
      )

      if response.code == 200
        log_info("Successfully cancelled Ollama request #{request_id}")
      else
        log_warn("Failed to cancel Ollama request: #{response.body}")
      end

    rescue StandardError => e
      log_warn("Error cancelling Ollama request: #{e.message}")
    end
  end

  def cancel_openai_stream(stream_id)
    # Implementation for cancelling OpenAI streaming connections
    log_info("Cancelling OpenAI stream #{stream_id}")
    
    # This would involve closing any WebSocket or SSE connections
    # and updating the execution metadata
  end

  def update_execution_status
    payload = {
      execution: {
        status: 'cancelled',
        completed_at: Time.current.iso8601,
        result: (@execution['result'] || {}).merge({
          cancelled: true,
          cancelled_at: Time.current.iso8601,
          cancellation_processed_at: Time.current.iso8601
        }),
        metadata: (@execution['metadata'] || {}).merge({
          cancellation_processed: true,
          cancelled_by_job: true
        })
      }
    }

    response = backend_api_patch("/api/v1/ai/agent_executions/#{@execution['id']}", payload)
    
    if response['success']
      @execution = response['data']['execution']
      log_info("Updated execution status to cancelled")
    else
      log_error("Failed to update execution status: #{response['error']}")
    end
  end

  def cleanup_execution_resources
    # Clean up any temporary files, connections, or resources
    log_info("Cleaning up resources for execution #{@execution['id']}")

    begin
      # Remove temporary files if any
      cleanup_temporary_files

      # Close any open connections
      cleanup_connections

      # Cancel related jobs
      cleanup_related_jobs

    rescue StandardError => e
      log_warn("Error during resource cleanup: #{e.message}")
    end
  end

  def cleanup_temporary_files
    # Clean up any temporary files created during execution
    temp_files = @execution['metadata']['temp_files'] || []
    
    temp_files.each do |file_path|
      begin
        File.delete(file_path) if File.exist?(file_path)
        logger.debug "Cleaned up temp file: #{file_path}"
      rescue StandardError => e
        log_warn("Failed to clean up temp file #{file_path}: #{e.message}")
      end
    end
  end

  def cleanup_connections
    # Close any persistent connections
    connection_ids = @execution['metadata']['connection_ids'] || []
    
    connection_ids.each do |conn_id|
      # Implementation depends on connection type
      logger.debug "Cleaning up connection: #{conn_id}"
    end
  end

  def cleanup_related_jobs
    # Cancel any related Sidekiq jobs
    related_job_ids = @execution['metadata']['related_job_ids'] || []
    
    related_job_ids.each do |job_id|
      begin
        # Attempt to cancel the related job
        Sidekiq::Queue.new.each do |job|
          if job.jid == job_id
            job.delete
            logger.debug "Cancelled related job: #{job_id}"
            break
          end
        end
      rescue StandardError => e
        log_warn("Failed to cancel related job #{job_id}: #{e.message}")
      end
    end
  end

  def broadcast_cancellation_complete
    # Broadcast cancellation completion via ActionCable
    execution_struct = OpenStruct.new(@execution)
    
    AiAgentExecutionChannel.broadcast_execution_complete(execution_struct)
    
    log_info("Broadcasted cancellation completion for execution #{@execution['id']}")
  end

  def record_cancellation_metrics
    # Record metrics about the cancellation
    metrics_data = {
      execution_id: @execution['id'],
      account_id: @execution['account_id'],
      agent_id: @execution['ai_agent_id'],
      provider_id: @execution['ai_agent']['ai_provider']['id'],
      cancelled_at: Time.current.iso8601,
      duration_before_cancel: calculate_duration_before_cancel,
      resources_cleaned: true,
      cancellation_method: 'job_processor'
    }

    response = backend_api_post("/api/v1/ai/analytics/cancellations", { metrics: metrics_data })
    
    if response['success']
      log_info("Recorded cancellation metrics")
    else
      log_warn("Failed to record cancellation metrics: #{response['error']}")
    end
  end

  def calculate_duration_before_cancel
    return 0 unless @execution['started_at']

    start_time = Time.parse(@execution['started_at'])
    cancel_time = Time.current
    
    ((cancel_time - start_time) * 1000).to_i # milliseconds
  end

  def get_execution_credential
    # Get the credential used by this execution
    agent = @execution['ai_agent']
    provider = agent['ai_provider']

    response = backend_api_get("/api/v1/ai/provider_credentials", {
      provider_id: provider['id'],
      default_only: true,
      active: true
    })

    if response['success'] && response['data']['credentials'].any?
      response['data']['credentials'].first
    else
      nil
    end
  end

  def handle_cancellation_error(error)
    log_error("Cancellation processing failed for execution #{@execution['id']}: #{error.message}")
    log_error(error.backtrace.join("\n"))

    # Try to update execution with error status
    begin
      payload = {
        execution: {
          status: 'failed',
          completed_at: Time.current.iso8601,
          result: (@execution['result'] || {}).merge({
            error: true,
            error_message: "Cancellation failed: #{error.message}",
            failed_at: Time.current.iso8601
          })
        }
      }

      backend_api_patch("/api/v1/ai/agent_executions/#{@execution['id']}", payload)

    rescue StandardError => update_error
      log_error("Failed to update execution after cancellation error: #{update_error.message}")
    end

    # Broadcast error
    begin
      execution_struct = OpenStruct.new(@execution)
      AiAgentExecutionChannel.broadcast_execution_error(
        execution_struct,
        "Cancellation failed: #{error.message}",
        { cancellation_error: true }
      )
    rescue StandardError => broadcast_error
      log_error("Failed to broadcast cancellation error: #{broadcast_error.message}")
    end

    # Re-raise for potential retry
    raise error
  end
end