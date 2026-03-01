# frozen_string_literal: true

# Async chat attachment processing (thumbnails, text extraction, transcription)
# Queue: file_processing (priority 2)
#
# Receives a message_id + attachment metadata, processes the file based on type:
# - Images: generate thumbnail URL, extract dimensions
# - PDFs: extract text content
# - Audio: transcription via AI provider (if available)
# - Other: mark as processed
#
# On completion, notifies backend to broadcast attachment_ready via ActionCable.
class AiChatAttachmentProcessingJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'file_processing', retry: 2

  # Supported MIME type categories
  IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp image/svg+xml image/bmp].freeze
  PDF_TYPES = %w[application/pdf].freeze
  AUDIO_TYPES = %w[audio/mpeg audio/wav audio/ogg audio/webm audio/mp4 audio/flac].freeze

  def execute(message_id, account_id, attachment_metadata)
    validate_required_params(
      { 'message_id' => message_id, 'account_id' => account_id,
        'attachment_metadata' => attachment_metadata },
      'message_id', 'account_id', 'attachment_metadata'
    )

    # Normalize metadata keys to strings
    metadata = attachment_metadata.is_a?(Hash) ? attachment_metadata.transform_keys(&:to_s) : {}

    idempotency_key = "attachment_processing:#{message_id}:#{metadata['storage_key']}"
    if already_processed?(idempotency_key)
      log_info("Attachment already processed", message_id: message_id)
      return
    end

    log_info("Starting attachment processing",
      message_id: message_id,
      file_name: metadata['name'],
      file_type: metadata['type'],
      file_size: metadata['size']
    )

    start_time = Time.current

    begin
      result = process_attachment(metadata)

      duration_ms = ((Time.current - start_time) * 1000).to_i

      notify_backend_complete(message_id, account_id, metadata, result, duration_ms)

      mark_processed(idempotency_key, ttl: 86_400)

      log_info("Attachment processing completed",
        message_id: message_id,
        processing_type: result[:processing_type],
        duration_ms: duration_ms
      )
    rescue StandardError => e
      duration_ms = ((Time.current - start_time) * 1000).to_i

      notify_backend_error(message_id, account_id, metadata, e.message)

      log_error("Attachment processing failed",
        message_id: message_id,
        error: e.message,
        duration_ms: duration_ms
      )

      handle_ai_processing_error(e, {
        message_id: message_id,
        account_id: account_id,
        file_type: metadata['type']
      })
    end
  end

  private

  def process_attachment(metadata)
    content_type = metadata['type'].to_s.downcase

    if image_type?(content_type)
      process_image(metadata)
    elsif pdf_type?(content_type)
      process_pdf(metadata)
    elsif audio_type?(content_type)
      process_audio(metadata)
    else
      process_generic(metadata)
    end
  end

  # ---------------------------------------------------------------------------
  # Image processing: thumbnail generation + dimension extraction
  # ---------------------------------------------------------------------------

  def process_image(metadata)
    log_info("Processing image attachment", file_name: metadata['name'])

    with_backend_api_circuit_breaker do
      response = backend_api_post("/api/v1/internal/ai/attachments/process_image", {
        storage_key: metadata['storage_key'],
        file_name: metadata['name'],
        content_type: metadata['type']
      })

      if response['success']
        data = response['data'] || {}
        {
          processing_type: 'image',
          thumbnail_url: data['thumbnail_url'],
          width: data['width'],
          height: data['height'],
          format: data['format'],
          status: 'processed'
        }
      else
        log_warn("Image processing API returned failure, marking as basic",
          file_name: metadata['name'])
        {
          processing_type: 'image',
          status: 'processed',
          note: 'Thumbnail generation unavailable'
        }
      end
    end
  end

  # ---------------------------------------------------------------------------
  # PDF processing: text extraction
  # ---------------------------------------------------------------------------

  def process_pdf(metadata)
    log_info("Processing PDF attachment", file_name: metadata['name'])

    with_backend_api_circuit_breaker do
      response = backend_api_post("/api/v1/internal/ai/attachments/extract_text", {
        storage_key: metadata['storage_key'],
        file_name: metadata['name'],
        content_type: metadata['type']
      })

      if response['success']
        data = response['data'] || {}
        {
          processing_type: 'pdf',
          extracted_text: data['text'],
          page_count: data['page_count'],
          char_count: data['text']&.length || 0,
          status: 'processed'
        }
      else
        log_warn("PDF text extraction failed, marking as basic",
          file_name: metadata['name'])
        {
          processing_type: 'pdf',
          status: 'processed',
          note: 'Text extraction unavailable'
        }
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Audio processing: transcription via AI provider
  # ---------------------------------------------------------------------------

  def process_audio(metadata)
    log_info("Processing audio attachment", file_name: metadata['name'])

    with_backend_api_circuit_breaker do
      response = backend_api_post("/api/v1/internal/ai/attachments/transcribe", {
        storage_key: metadata['storage_key'],
        file_name: metadata['name'],
        content_type: metadata['type']
      })

      if response['success']
        data = response['data'] || {}
        {
          processing_type: 'audio',
          transcript: data['transcript'],
          duration_seconds: data['duration_seconds'],
          language: data['language'],
          status: 'processed'
        }
      else
        log_warn("Audio transcription unavailable, marking as basic",
          file_name: metadata['name'])
        {
          processing_type: 'audio',
          status: 'processed',
          note: 'Transcription unavailable'
        }
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Generic file: just mark as processed
  # ---------------------------------------------------------------------------

  def process_generic(metadata)
    log_info("Processing generic attachment", file_name: metadata['name'], type: metadata['type'])

    {
      processing_type: 'generic',
      status: 'processed'
    }
  end

  # ---------------------------------------------------------------------------
  # Backend notification
  # ---------------------------------------------------------------------------

  def notify_backend_complete(message_id, account_id, metadata, result, duration_ms)
    with_backend_api_circuit_breaker do
      backend_api_post("/api/v1/internal/ai/conversations/attachments/#{message_id}/processed", {
        account_id: account_id,
        file_name: metadata['name'],
        content_type: metadata['type'],
        storage_key: metadata['storage_key'],
        processing_result: result,
        duration_ms: duration_ms,
        processed_at: Time.current.iso8601
      })
    end
  rescue StandardError => e
    log_error("Failed to notify backend of attachment completion",
      message_id: message_id, error: e.message)
  end

  def notify_backend_error(message_id, account_id, metadata, error_message)
    with_backend_api_circuit_breaker do
      backend_api_post("/api/v1/internal/ai/conversations/attachments/#{message_id}/processed", {
        account_id: account_id,
        file_name: metadata['name'],
        content_type: metadata['type'],
        storage_key: metadata['storage_key'],
        processing_result: {
          processing_type: detect_processing_type(metadata['type']),
          status: 'error',
          error: error_message
        },
        processed_at: Time.current.iso8601
      })
    end
  rescue StandardError => e
    log_error("Failed to notify backend of attachment error",
      message_id: message_id, error: e.message)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def image_type?(content_type)
    content_type.start_with?('image/')
  end

  def pdf_type?(content_type)
    PDF_TYPES.include?(content_type)
  end

  def audio_type?(content_type)
    content_type.start_with?('audio/')
  end

  def detect_processing_type(content_type)
    content_type = content_type.to_s.downcase
    if image_type?(content_type)
      'image'
    elsif pdf_type?(content_type)
      'pdf'
    elsif audio_type?(content_type)
      'audio'
    else
      'generic'
    end
  end
end
