# frozen_string_literal: true

module Chat
  class SessionManager
    class SessionError < StandardError; end
    class BlockedUserError < SessionError; end
    class RateLimitError < SessionError; end

    def initialize(channel)
      @channel = channel
    end

    # Find or create session for incoming message
    def get_session(platform_user_id:, platform_username: nil, metadata: {})
      # Check if user is blacklisted
      if @channel.user_blacklisted?(platform_user_id)
        raise BlockedUserError, "User #{platform_user_id} is blocked"
      end

      # Find or create session
      @channel.find_or_create_session(
        platform_user_id: platform_user_id,
        platform_username: platform_username,
        metadata: metadata
      )
    end

    # Handle stale sessions
    def cleanup_stale_sessions(idle_threshold: 24.hours, close_threshold: 7.days)
      closed_count = 0
      idled_count = 0

      # Mark active sessions as idle
      @channel.sessions.active.where("last_activity_at < ?", idle_threshold.ago).find_each do |session|
        session.mark_idle!
        idled_count += 1
      end

      # Close very old idle sessions
      @channel.sessions.idle.where("last_activity_at < ?", close_threshold.ago).find_each do |session|
        session.close!(reason: "inactivity")
        closed_count += 1
      end

      { idled: idled_count, closed: closed_count }
    end

    # Transfer session to different agent
    def transfer_session(session, new_agent)
      unless session.channel_id == @channel.id
        raise SessionError, "Session does not belong to this channel"
      end

      session.transfer_to_agent!(new_agent)
    end

    # Escalate session to human operator
    def escalate_to_human(session, reason: nil)
      session.escalate_to_human!

      # Notify operators
      broadcast_escalation(session, reason)
    end

    # Get session statistics
    def session_stats
      sessions = @channel.sessions

      {
        total: sessions.count,
        active: sessions.active.count,
        idle: sessions.idle.count,
        closed: sessions.closed.count,
        blocked: sessions.blocked.count,
        avg_messages_per_session: sessions.average(:message_count).to_f.round(2),
        sessions_last_24h: sessions.where("created_at > ?", 24.hours.ago).count,
        messages_last_24h: @channel.messages.where("created_at > ?", 24.hours.ago).count
      }
    end

    # Get active sessions for monitoring
    def active_sessions(limit: 50)
      @channel.sessions
              .active
              .includes(:assigned_agent)
              .order(last_activity_at: :desc)
              .limit(limit)
    end

    # Get sessions needing attention (escalated, high message count, etc.)
    def sessions_needing_attention
      @channel.sessions
              .open
              .where("user_metadata->>'needs_human' = ?", "true")
              .or(@channel.sessions.open.where("message_count > ?", 50))
              .order(last_activity_at: :desc)
    end

    # Block a user
    def block_user(platform_user_id, reason: nil, duration: nil, blocked_by: nil)
      Chat::Blacklist.block_user(
        account: @channel.account,
        platform_user_id: platform_user_id,
        channel: @channel,
        reason: reason,
        duration: duration,
        blocked_by: blocked_by
      )
    end

    # Unblock a user
    def unblock_user(platform_user_id)
      @channel.blacklists
              .active
              .where(platform_user_id: platform_user_id)
              .destroy_all
    end

    private

    def broadcast_escalation(session, reason)
      ActionCable.server.broadcast(
        "chat_channel_#{@channel.id}",
        {
          type: "escalation",
          session_id: session.id,
          platform_user_id: session.platform_user_id,
          platform_username: session.platform_username,
          reason: reason,
          message_count: session.message_count,
          timestamp: Time.current.iso8601
        }
      )
    end
  end
end
