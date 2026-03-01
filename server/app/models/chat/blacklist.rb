# frozen_string_literal: true

module Chat
  class Blacklist < ApplicationRecord
    self.table_name = "chat_blacklists"

    # Concerns
    include Auditable

    # Constants
    BLOCK_TYPES = %w[temporary permanent].freeze

    # Associations
    belongs_to :account
    belongs_to :channel, class_name: "Chat::Channel", optional: true
    belongs_to :blocked_by, class_name: "User", optional: true

    # Validations
    validates :platform_user_id, presence: true
    validates :block_type, presence: true, inclusion: { in: BLOCK_TYPES }
    validate :expires_at_required_for_temporary
    validate :unique_active_block

    # Scopes
    scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :expired, -> { where("expires_at IS NOT NULL AND expires_at <= ?", Time.current) }
    scope :permanent, -> { where(block_type: "permanent") }
    scope :temporary, -> { where(block_type: "temporary") }
    scope :account_wide, -> { where(channel_id: nil) }
    scope :for_channel, ->(channel) { where(channel_id: channel.is_a?(Chat::Channel) ? channel.id : channel) }
    scope :for_user, ->(platform_user_id) { where(platform_user_id: platform_user_id) }

    # Status checks
    def active?
      permanent? || (temporary? && expires_at > Time.current)
    end

    def expired?
      temporary? && expires_at <= Time.current
    end

    def permanent?
      block_type == "permanent"
    end

    def temporary?
      block_type == "temporary"
    end

    def account_wide?
      channel_id.nil?
    end

    def channel_specific?
      channel_id.present?
    end

    # Duration helpers
    def remaining_time
      return nil if permanent? || expired?

      expires_at - Time.current
    end

    def remaining_time_formatted
      return "Permanent" if permanent?
      return "Expired" if expired?

      remaining = remaining_time
      if remaining < 1.hour
        "#{(remaining / 1.minute).to_i} minutes"
      elsif remaining < 1.day
        "#{(remaining / 1.hour).to_i} hours"
      else
        "#{(remaining / 1.day).to_i} days"
      end
    end

    # Management
    def extend!(additional_time)
      return false if permanent?

      new_expires_at = [ expires_at, Time.current ].max + additional_time
      update!(expires_at: new_expires_at)
    end

    def make_permanent!
      update!(block_type: "permanent", expires_at: nil)
    end

    def unblock!
      destroy
    end

    # Close any active sessions for this user
    def close_active_sessions!
      sessions = if channel_specific?
                   channel.sessions.where(platform_user_id: platform_user_id)
      else
                   Chat::Session.joins(:channel)
                                .where(chat_channels: { account_id: account_id })
                                .where(platform_user_id: platform_user_id)
      end

      sessions.open.find_each do |session|
        session.block!(reason: reason)
      end
    end

    # Summary for API
    def blacklist_summary
      {
        id: id,
        platform_user_id: platform_user_id,
        block_type: block_type,
        reason: reason,
        channel_id: channel_id,
        channel_name: channel&.name,
        account_wide: account_wide?,
        expires_at: expires_at,
        remaining: remaining_time_formatted,
        active: active?,
        blocked_by: blocked_by&.full_name,
        created_at: created_at
      }
    end

    # Class methods
    class << self
      def block_user(account:, platform_user_id:, channel: nil, reason: nil, duration: nil, blocked_by: nil)
        block_type = duration.present? ? "temporary" : "permanent"
        expires_at = duration.present? ? Time.current + duration : nil

        blacklist = create!(
          account: account,
          channel: channel,
          platform_user_id: platform_user_id,
          reason: reason,
          block_type: block_type,
          expires_at: expires_at,
          blocked_by: blocked_by
        )

        # Close active sessions
        blacklist.close_active_sessions!

        blacklist
      end

      def cleanup_expired!
        expired.destroy_all
      end
    end

    private

    def expires_at_required_for_temporary
      if temporary? && expires_at.blank?
        errors.add(:expires_at, "is required for temporary blocks")
      end
    end

    def unique_active_block
      existing = self.class.active
                     .where(account_id: account_id, platform_user_id: platform_user_id)
                     .where(channel_id: channel_id)
                     .where.not(id: id)

      if existing.exists?
        errors.add(:platform_user_id, "already has an active block")
      end
    end
  end
end
