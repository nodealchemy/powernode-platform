# frozen_string_literal: true

# Service for handling streaming AI operations with real-time updates
class AiStreamingService
  include ActiveModel::Model

  attr_accessor :execution, :channel, :account

  def initialize(execution:, channel: nil, account: nil)
    @execution = execution
    @channel = channel
    @account = account || execution.account
    @buffer = []
    @stream_id = SecureRandom.uuid
    @start_time = Time.current
  end

  # Stream AI agent execution with real-time updates
  def stream_execution(agent, input_parameters)
    Rails.logger.info "[STREAMING] Starting stream #{@stream_id} for agent #{agent.id}"

    # Broadcast stream start
    broadcast_stream_event("stream_started", {
      stream_id: @stream_id,
      agent_id: agent.id,
      agent_name: agent.name,
      started_at: Time.current.iso8601
    })

    begin
      # Simulate streaming chunks (in production, this would be actual AI API streaming)
      response_chunks = simulate_streaming_response(input_parameters)

      response_chunks.each_with_index do |chunk, index|
        # Process chunk
        process_stream_chunk(chunk, index)

        # Brief delay to simulate real streaming
        sleep(0.1)
      end

      # Complete streaming
      complete_stream(response_chunks.join)

    rescue StandardError => e
      handle_stream_error(e)
    end
  end

  # Process a stream chunk and broadcast update
  def process_stream_chunk(chunk, index)
    @buffer << chunk

    # Broadcast chunk to connected clients
    broadcast_stream_event("stream_chunk", {
      stream_id: @stream_id,
      chunk_index: index,
      content: chunk,
      buffer_size: @buffer.size,
      elapsed_ms: ((Time.current - @start_time) * 1000).to_i
    })

    # Update execution with partial results periodically
    if index % 10 == 0
      update_execution_progress
    end
  end

  # Complete the stream with final results
  def complete_stream(full_response)
    Rails.logger.info "[STREAMING] Completing stream #{@stream_id}"

    final_data = {
      stream_id: @stream_id,
      full_response: full_response,
      total_chunks: @buffer.size,
      duration_ms: ((Time.current - @start_time) * 1000).to_i,
      completed_at: Time.current.iso8601
    }

    # Broadcast completion
    broadcast_stream_event("stream_completed", final_data)

    # Update execution with final results
    @execution.update!(
      output_data: {
        response: full_response,
        stream_metadata: final_data
      },
      status: "completed",
      completed_at: Time.current
    )

    final_data
  end

  # Handle streaming errors
  def handle_stream_error(error)
    Rails.logger.error "[STREAMING] Stream error #{@stream_id}: #{error.message}"

    error_data = {
      stream_id: @stream_id,
      error: error.message,
      error_class: error.class.name,
      partial_response: @buffer.join,
      failed_at: Time.current.iso8601
    }

    # Broadcast error
    broadcast_stream_event("stream_error", error_data)

    # Update execution with error
    @execution.update!(
      status: "failed",
      error_details: error_data,
      completed_at: Time.current
    )

    raise error
  end

  private

  def broadcast_stream_event(event_type, data)
    return unless @channel

    message = {
      type: event_type,
      data: data,
      timestamp: Time.current.iso8601
    }

    # Broadcast to execution-specific channel
    ActionCable.server.broadcast(
      "ai_execution_stream_#{@execution.id}",
      message
    )

    # Also broadcast to account-level monitoring
    ActionCable.server.broadcast(
      "ai_monitoring_#{@account.id}",
      message.merge(execution_id: @execution.id)
    )
  end

  def update_execution_progress
    progress_percentage = (@buffer.size.to_f / estimated_total_chunks * 100).round(2)

    @execution.update!(
      performance_metrics: {
        progress_percentage: progress_percentage,
        chunks_processed: @buffer.size,
        elapsed_ms: ((Time.current - @start_time) * 1000).to_i,
        streaming: true
      }
    )
  end

  def simulate_streaming_response(input)
    # In production, this would be replaced with actual AI API streaming
    # For now, simulate a response broken into chunks
    base_response = "Processing input: #{input.to_s[0..50]}...\n\n"

    chunks = []
    chunks << "Analyzing request...\n"
    chunks << "Understanding context...\n"
    chunks << "Generating response...\n"
    chunks << "\nBased on the input provided, "
    chunks << "I can see that you're working with "
    chunks << "#{input.keys.join(', ')} parameters. "
    chunks << "\n\nHere's my analysis:\n"
    chunks << "1. The data appears to be well-structured\n"
    chunks << "2. Processing can proceed as requested\n"
    chunks << "3. Results will be optimal for your use case\n"
    chunks << "\nFinal recommendation: Proceed with confidence!"

    chunks
  end

  def estimated_total_chunks
    # Estimate based on typical response size
    50
  end
end
