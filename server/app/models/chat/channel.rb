# frozen_string_literal: true

module Chat
  class Channel < ApplicationRecord
    self.table_name = "chat_channels"

    # Concerns
    include Auditable
    include VaultCredential

    self.vault_credential_type = "chat-channels"

    # Platform constants
    PLATFORMS = %w[whatsapp telegram discord slack mattermost].freeze
    STATUSES = %w[connected disconnected connecting error].freeze

    # Associations
    belongs_to :account
    belongs_to :default_agent, class_name: "Ai::Agent", optional: true

    has_many :sessions, class_name: "Chat::Session", foreign_key: "channel_id", dependent: :destroy
    has_many :messages, through: :sessions
    has_many :blacklists, class_name: "Chat::Blacklist", foreign_key: "channel_id", dependent: :destroy

    # Validations
    validates :platform, presence: true, inclusion: { in: PLATFORMS }
    validates :name, presence: true, length: { maximum: 255 }
    validates :name, uniqueness: { scope: [ :account_id, :platform ] }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :webhook_token, presence: true, uniqueness: true
    validates :rate_limit_per_minute, numericality: { greater_than: 0, less_than_or_equal_to: 1000 }

    # Scopes
    scope :connected, -> { where(status: "connected") }
    scope :disconnected, -> { where(status: "disconnected") }
    scope :by_platform, ->(platform) { where(platform: platform) }
    scope :active, -> { where(status: %w[connected connecting]) }
    scope :with_default_agent, -> { where.not(default_agent_id: nil) }
    scope :recently_active, -> { where("last_message_at > ?", 24.hours.ago) }

    # Callbacks
    before_validation :generate_webhook_token, on: :create
    after_update :broadcast_status_change, if: :saved_change_to_status?

    # Status methods
    def connected?
      status == "connected"
    end

    def disconnected?
      status == "disconnected"
    end

    def connect!
      update!(status: "connecting", last_error: nil)
      # Actual connection handled by platform adapter
    end

    def mark_connected!
      update!(
        status: "connected",
        connected_at: Time.current,
        last_error: nil
      )
    end

    def mark_disconnected!(error_message = nil)
      attrs = { status: "disconnected" }
      if error_message.present?
        attrs[:status] = "error"
        attrs[:last_error] = error_message.truncate(1000)
        attrs[:last_error_at] = Time.current
      end
      update!(attrs)
    end

    def disconnect!
      update!(status: "disconnected")
    end

    # Session management
    def find_or_create_session(platform_user_id:, platform_username: nil, metadata: {})
      session = sessions.find_or_initialize_by(platform_user_id: platform_user_id)

      if session.new_record?
        session.platform_username = platform_username
        session.user_metadata = metadata
        session.assigned_agent = default_agent
        session.save!
      elsif platform_username.present? && session.platform_username != platform_username
        session.update!(platform_username: platform_username)
      end

      session.touch_activity!
      session
    end

    # Check if user is blacklisted
    def user_blacklisted?(platform_user_id)
      blacklists.where(platform_user_id: platform_user_id)
                .where("expires_at IS NULL OR expires_at > ?", Time.current)
                .exists? ||
        account_wide_blacklist?(platform_user_id)
    end

    # Rate limiting
    def rate_limit_key
      "chat:channel:#{id}:rate"
    end

    def rate_limited?
      count = Rails.cache.read(rate_limit_key).to_i
      count >= rate_limit_per_minute
    end

    def increment_rate_counter!
      key = rate_limit_key
      count = Rails.cache.read(key).to_i
      Rails.cache.write(key, count + 1, expires_in: 1.minute)
    end

    # Token management
    def regenerate_webhook_token!
      update!(webhook_token: SecureRandom.urlsafe_base64(32))
    end

    # Message tracking
    def record_message!
      increment!(:message_count)
      touch(:last_message_at)
    end

    # Configuration helpers
    def platform_config
      configuration.with_indifferent_access
    end

    def update_config(new_config)
      update!(configuration: configuration.merge(new_config))
    end

    # Webhook URL generation
    def webhook_url
      Rails.application.routes.url_helpers.api_v1_chat_webhook_url(
        token: webhook_token,
        host: Rails.application.config.action_mailer.default_url_options[:host]
      )
    rescue StandardError
      nil
    end

    # Summary for API responses
    def channel_summary
      {
        id: id,
        platform: platform,
        name: name,
        status: status,
        message_count: message_count,
        session_count: session_count,
        default_agent: default_agent&.name,
        connected_at: connected_at,
        last_message_at: last_message_at
      }
    end

    def channel_details
      channel_summary.merge(
        configuration: configuration.except("credentials", "routing_config", "agent_personality"),
        routing_config: configuration&.dig("routing_config"),
        agent_personality: configuration&.dig("agent_personality"),
        rate_limit_per_minute: rate_limit_per_minute,
        last_error: last_error,
        last_error_at: last_error_at,
        webhook_url: webhook_url,
        created_at: created_at,
        updated_at: updated_at
      )
    end

    private

    def generate_webhook_token
      self.webhook_token ||= SecureRandom.urlsafe_base64(32)
    end

    def broadcast_status_change
      ActionCable.server.broadcast(
        "chat_channel_#{id}",
        {
          type: "status_change",
          channel_id: id,
          status: status,
          timestamp: Time.current.iso8601
        }
      )
    end

    def account_wide_blacklist?(platform_user_id)
      account.chat_blacklists
             .where(platform_user_id: platform_user_id, channel_id: nil)
             .where("expires_at IS NULL OR expires_at > ?", Time.current)
             .exists?
    end
  end
end
