# frozen_string_literal: true

module Chat
  class MessageAttachment < ApplicationRecord
    self.table_name = "chat_message_attachments"

    # Concerns
    include Auditable

    # Constants
    ATTACHMENT_TYPES = %w[image audio video document].freeze
    ALLOWED_MIME_TYPES = {
      "image" => %w[image/jpeg image/png image/gif image/webp],
      "audio" => %w[audio/ogg audio/mpeg audio/mp4 audio/wav audio/webm],
      "video" => %w[video/mp4 video/webm video/quicktime],
      "document" => %w[application/pdf application/msword application/vnd.openxmlformats-officedocument.wordprocessingml.document
                       application/vnd.ms-excel application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
                       text/plain text/csv]
    }.freeze

    MAX_FILE_SIZE = 25.megabytes

    # Associations
    belongs_to :message, class_name: "Chat::Message"
    belongs_to :file_object, class_name: "FileManagement::FileObject", optional: true

    # Delegations
    delegate :session, to: :message
    delegate :channel, to: :message
    delegate :account, to: :message

    # Validations
    validates :attachment_type, presence: true, inclusion: { in: ATTACHMENT_TYPES }
    validates :mime_type, presence: true
    validate :valid_mime_type_for_attachment_type
    validate :file_size_within_limit

    # Scopes
    scope :images, -> { where(attachment_type: "image") }
    scope :audio, -> { where(attachment_type: "audio") }
    scope :videos, -> { where(attachment_type: "video") }
    scope :documents, -> { where(attachment_type: "document") }
    scope :scanned, -> { where(scanned_for_malware: true) }
    scope :safe, -> { where(scanned_for_malware: true, malware_detected: false) }
    scope :pending_scan, -> { where(scanned_for_malware: false) }
    scope :needs_transcription, -> { audio.where(transcription: nil) }

    # Callbacks
    after_create :enqueue_malware_scan, unless: :scanned_for_malware?
    after_create :enqueue_transcription, if: :needs_transcription?

    # Type checks
    def image?
      attachment_type == "image"
    end

    def audio?
      attachment_type == "audio"
    end

    def video?
      attachment_type == "video"
    end

    def document?
      attachment_type == "document"
    end

    # Security
    def safe_to_use?
      scanned_for_malware? && !malware_detected?
    end

    def mark_scanned!(malware_found: false)
      update!(
        scanned_for_malware: true,
        malware_detected: malware_found,
        scanned_at: Time.current
      )
    end

    def quarantine!
      update!(malware_detected: true)
      # Move to quarantine storage or delete
      Rails.logger.warn "Quarantined malicious attachment: #{id}"
    end

    # Transcription
    def needs_transcription?
      audio? && transcription.blank?
    end

    def set_transcription!(text)
      update!(transcription: text)

      # Update the message with transcription
      if message.content.blank?
        message.update!(
          content: "[Voice message] #{text}",
          sanitized_content: "[USER_MESSAGE_START]\n[Voice message] #{text}\n[USER_MESSAGE_END]"
        )
      end
    end

    # File access
    def signed_url(expires_in: 1.hour)
      return storage_url if storage_url&.start_with?("http")

      file_object&.signed_url(expires_in: expires_in)
    end

    def download_url
      signed_url(expires_in: 5.minutes)
    end

    # Metadata helpers
    def dimensions
      return nil unless image? || video?

      {
        width: metadata.dig("width"),
        height: metadata.dig("height")
      }
    end

    def duration_seconds
      return nil unless audio? || video?

      metadata.dig("duration")
    end

    def formatted_duration
      return nil unless duration_seconds

      minutes = (duration_seconds / 60).to_i
      seconds = (duration_seconds % 60).to_i
      "#{minutes}:#{seconds.to_s.rjust(2, '0')}"
    end

    def formatted_file_size
      return "Unknown" unless file_size

      if file_size < 1.kilobyte
        "#{file_size} B"
      elsif file_size < 1.megabyte
        "#{(file_size / 1.kilobyte).round(1)} KB"
      else
        "#{(file_size / 1.megabyte).round(1)} MB"
      end
    end

    # Summary for API
    def attachment_summary
      {
        id: id,
        attachment_type: attachment_type,
        mime_type: mime_type,
        filename: filename,
        file_size: file_size,
        formatted_size: formatted_file_size,
        download_url: safe_to_use? ? download_url : nil,
        dimensions: dimensions,
        duration: formatted_duration,
        transcription: transcription,
        safe: safe_to_use?
      }
    end

    def attachment_details
      attachment_summary.merge(
        message_id: message_id,
        platform_file_id: platform_file_id,
        storage_url: storage_url,
        metadata: metadata,
        scanned_at: scanned_at,
        malware_detected: malware_detected,
        created_at: created_at
      )
    end

    private

    def valid_mime_type_for_attachment_type
      return unless attachment_type.present? && mime_type.present?

      allowed = ALLOWED_MIME_TYPES[attachment_type] || []
      unless allowed.include?(mime_type)
        errors.add(:mime_type, "#{mime_type} is not allowed for #{attachment_type}")
      end
    end

    def file_size_within_limit
      return unless file_size.present?

      if file_size > MAX_FILE_SIZE
        errors.add(:file_size, "exceeds maximum allowed size of #{MAX_FILE_SIZE / 1.megabyte}MB")
      end
    end

    def enqueue_malware_scan
      WorkerJobService.enqueue_chat_attachment_scan(id)
    rescue StandardError => e
      Rails.logger.error "Failed to enqueue malware scan for attachment #{id}: #{e.message}"
    end

    def enqueue_transcription
      WorkerJobService.enqueue_chat_transcription(id)
    rescue StandardError => e
      Rails.logger.error "Failed to enqueue transcription for attachment #{id}: #{e.message}"
    end
  end
end
