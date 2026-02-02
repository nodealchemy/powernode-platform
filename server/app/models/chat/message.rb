# frozen_string_literal: true

module Chat
  class Message < ApplicationRecord
    # Concerns
    include Auditable

    # Constants
    DIRECTIONS = %w[inbound outbound].freeze
    MESSAGE_TYPES = %w[text image audio video document location sticker].freeze
    DELIVERY_STATUSES = %w[pending sent delivered read failed].freeze

    # Associations
    belongs_to :session, class_name: "Chat::Session"
    belongs_to :ai_message, class_name: "Ai::Message", optional: true

    has_many :attachments, class_name: "Chat::MessageAttachment",
                           foreign_key: "message_id",
                           dependent: :destroy

    has_one :a2a_task, class_name: "Ai::A2aTask", foreign_key: "chat_message_id"

    # Delegations
    delegate :channel, to: :session
    delegate :account, to: :session
    delegate :platform, to: :session

    # Validations
    validates :direction, presence: true, inclusion: { in: DIRECTIONS }
    validates :message_type, presence: true, inclusion: { in: MESSAGE_TYPES }
    validates :delivery_status, presence: true, inclusion: { in: DELIVERY_STATUSES }
    validates :content, presence: true, if: -> { message_type == "text" }

    # Scopes
    scope :inbound, -> { where(direction: "inbound") }
    scope :outbound, -> { where(direction: "outbound") }
    scope :text_messages, -> { where(message_type: "text") }
    scope :media_messages, -> { where.not(message_type: "text") }
    scope :pending, -> { where(delivery_status: "pending") }
    scope :sent, -> { where(delivery_status: "sent") }
    scope :delivered, -> { where(delivery_status: "delivered") }
    scope :failed, -> { where(delivery_status: "failed") }
    scope :recent, -> { order(created_at: :desc) }
    scope :chronological, -> { order(created_at: :asc) }

    # Callbacks
    after_create :sync_to_ai_conversation, if: -> { session.ai_conversation.present? }
    after_update :broadcast_status_change, if: :saved_change_to_delivery_status?

    # Direction checks
    def inbound?
      direction == "inbound"
    end

    def outbound?
      direction == "outbound"
    end

    # Message type checks
    def text?
      message_type == "text"
    end

    def media?
      !text?
    end

    def has_attachments?
      attachments.any?
    end

    # Delivery status management
    def mark_sent!(platform_message_id = nil)
      attrs = { delivery_status: "sent", sent_at: Time.current }
      attrs[:platform_message_id] = platform_message_id if platform_message_id.present?
      update!(attrs)
    end

    def mark_delivered!
      update!(delivery_status: "delivered", delivered_at: Time.current)
    end

    def mark_read!
      update!(delivery_status: "read", read_at: Time.current)
    end

    def mark_failed!(error_reason = nil)
      update!(
        delivery_status: "failed",
        platform_metadata: platform_metadata.merge("error" => error_reason)
      )
    end

    # Content helpers
    def display_content
      case message_type
      when "text"
        content
      when "image"
        "[Image: #{attachments.first&.filename || 'attachment'}]"
      when "audio"
        "[Audio: #{format_duration}]"
      when "video"
        "[Video: #{attachments.first&.filename || 'attachment'}]"
      when "document"
        "[Document: #{attachments.first&.filename || 'attachment'}]"
      when "location"
        location_data = platform_metadata.dig("location")
        "[Location: #{location_data&.dig('name') || 'Shared location'}]"
      when "sticker"
        "[Sticker]"
      else
        content || "[#{message_type}]"
      end
    end

    def content_for_ai
      sanitized_content || content
    end

    # Transcription for voice messages
    def transcription
      return nil unless message_type == "audio"

      attachments.first&.transcription
    end

    def transcribed?
      transcription.present?
    end

    # Summary for API
    def message_summary
      {
        id: id,
        direction: direction,
        message_type: message_type,
        content: display_content,
        delivery_status: delivery_status,
        platform_message_id: platform_message_id,
        sent_at: sent_at,
        delivered_at: delivered_at,
        read_at: read_at,
        created_at: created_at
      }
    end

    def message_details
      message_summary.merge(
        session_id: session_id,
        ai_message_id: ai_message_id,
        raw_content: content,
        sanitized_content: sanitized_content,
        attachments: attachments.map(&:attachment_summary),
        platform_metadata: platform_metadata.except("error"),
        transcription: transcription
      )
    end

    # Format for A2A task submission
    def to_a2a_message
      {
        role: inbound? ? "user" : "assistant",
        parts: build_a2a_parts
      }
    end

    private

    def sync_to_ai_conversation
      return unless session.ai_conversation.present?

      role = inbound? ? "user" : "assistant"
      ai_content = content_for_ai

      # Add voice transcription if available
      if message_type == "audio" && transcription.present?
        ai_content = "[Voice message transcription] #{transcription}"
      end

      ai_message = session.ai_conversation.add_message(
        role,
        ai_content,
        metadata: {
          chat_message_id: id,
          message_type: message_type,
          platform: platform
        }
      )

      update_column(:ai_message_id, ai_message.id) if ai_message.persisted?
    rescue StandardError => e
      Rails.logger.error "Failed to sync chat message to AI conversation: #{e.message}"
    end

    def broadcast_status_change
      ActionCable.server.broadcast(
        "chat_session_#{session_id}",
        {
          type: "message_status",
          message_id: id,
          delivery_status: delivery_status,
          timestamp: Time.current.iso8601
        }
      )
    end

    def format_duration
      duration = platform_metadata.dig("duration")
      return "unknown duration" unless duration

      minutes = (duration / 60).to_i
      seconds = (duration % 60).to_i
      "#{minutes}:#{seconds.to_s.rjust(2, '0')}"
    end

    def build_a2a_parts
      parts = []

      # Text content
      if content.present?
        parts << { type: "text", text: content_for_ai }
      end

      # File attachments
      attachments.each do |attachment|
        parts << {
          type: "file",
          file: {
            name: attachment.filename,
            mimeType: attachment.mime_type,
            uri: attachment.storage_url
          }
        }
      end

      parts
    end
  end
end
