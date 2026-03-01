# frozen_string_literal: true

module Ai
  module Tools
    class ActivityMonitorTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.read"

      def self.definition
        {
          name: "activity_monitor",
          description: "Monitor platform activity: missions, conversations, execution events, notifications, and system health",
          parameters: {
            action: { type: "string", required: true, description: "Action: get_activity_feed, get_mission_status, get_notifications, dismiss_notification, get_system_health" },
            mission_id: { type: "string", required: false, description: "Mission ID (for get_mission_status)" },
            notification_id: { type: "string", required: false, description: "Notification ID (for dismiss_notification)" },
            hours: { type: "integer", required: false, description: "Lookback window in hours (for get_activity_feed, default 24)" },
            limit: { type: "integer", required: false, description: "Max results (default 10)" }
          }
        }
      end

      def self.action_definitions
        {
          "get_activity_feed" => {
            description: "Get a unified activity feed of recent missions, conversations, execution events, and errors across the platform",
            parameters: {
              hours: { type: "integer", required: false, description: "Lookback window in hours (default 24, max 168)" },
              limit: { type: "integer", required: false, description: "Max items per category (default 10, max 50)" }
            }
          },
          "get_mission_status" => {
            description: "Get mission status. Without mission_id: all in-progress missions with approval gates. With mission_id: full mission details.",
            parameters: {
              mission_id: { type: "string", required: false, description: "Specific mission ID for full details (omit for overview)" }
            }
          },
          "get_notifications" => {
            description: "Get unread notifications for the current user with type, severity, and action URL",
            parameters: {
              limit: { type: "integer", required: false, description: "Max notifications to return (default 10, max 50)" }
            }
          },
          "dismiss_notification" => {
            description: "Mark a notification as read",
            parameters: {
              notification_id: { type: "string", required: true, description: "ID of the notification to dismiss" }
            }
          },
          "get_system_health" => {
            description: "Get a lightweight system health snapshot: active counts, approval queues, error rates, and provider status",
            parameters: {}
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "get_activity_feed" then get_activity_feed(params)
        when "get_mission_status" then get_mission_status(params)
        when "get_notifications" then get_notifications(params)
        when "dismiss_notification" then dismiss_notification(params)
        when "get_system_health" then get_system_health
        else
          { success: false, error: "Unknown action: #{params[:action]}. Valid: get_activity_feed, get_mission_status, get_notifications, dismiss_notification, get_system_health" }
        end
      end

      private

      def get_activity_feed(params)
        hours = (params[:hours] || 24).to_i.clamp(1, 168)
        limit = (params[:limit] || 10).to_i.clamp(1, 50)
        since = hours.hours.ago

        # Recent missions
        missions = account.ai_missions
          .where("ai_missions.created_at >= ? OR ai_missions.updated_at >= ?", since, since)
          .order(updated_at: :desc).limit(limit)

        # Recent conversations
        conversations = Ai::Conversation.where(account: account)
          .where("last_activity_at >= ?", since)
          .includes(:agent).order(last_activity_at: :desc).limit(limit)

        # Recent execution events
        events = Ai::ExecutionEvent.where(account_id: account.id)
          .in_time_range(since)
          .recent(limit)

        # Recent errors
        errors = Ai::ExecutionEvent.where(account_id: account.id)
          .with_errors.in_time_range(since)
          .recent(limit)

        {
          success: true,
          window_hours: hours,
          missions: missions.map { |m| serialize_mission_brief(m) },
          conversations: conversations.map { |c| serialize_conversation_brief(c) },
          events: events.map { |e| serialize_event(e) },
          errors: errors.map { |e| serialize_error(e) },
          summary: {
            mission_count: missions.size,
            conversation_count: conversations.size,
            event_count: events.size,
            error_count: errors.size
          }
        }
      end

      def get_mission_status(params)
        if params[:mission_id].present?
          mission = account.ai_missions.find_by(id: params[:mission_id])
          return { success: false, error: "Mission not found" } unless mission

          { success: true, mission: mission.mission_details }
        else
          missions = account.ai_missions.in_progress.order(updated_at: :desc)
          awaiting = missions.select(&:awaiting_approval?)

          {
            success: true,
            in_progress_count: missions.size,
            awaiting_approval_count: awaiting.size,
            missions: missions.map { |m| serialize_mission_brief(m) },
            awaiting_approval: awaiting.map { |m|
              {
                id: m.id,
                name: m.name,
                gate: m.current_gate,
                phase_progress: m.phase_progress
              }
            }
          }
        end
      end

      def get_notifications(params)
        return { success: false, error: "User context required for notifications" } unless user

        limit = (params[:limit] || 10).to_i.clamp(1, 50)
        notifications = user.notifications.active.unread.recent.limit(limit)

        {
          success: true,
          count: notifications.size,
          notifications: notifications.map { |n| serialize_notification(n) }
        }
      end

      def dismiss_notification(params)
        return { success: false, error: "notification_id is required" } if params[:notification_id].blank?
        return { success: false, error: "User context required" } unless user

        notification = user.notifications.find_by(id: params[:notification_id])
        return { success: false, error: "Notification not found" } unless notification

        notification.mark_as_read!
        { success: true, notification_id: notification.id, read_at: notification.read_at&.iso8601 }
      rescue StandardError => e
        { success: false, error: "Failed to dismiss notification: #{e.message}" }
      end

      def get_system_health
        now = Time.current

        # Mission counts
        active_missions = account.ai_missions.in_progress.count
        awaiting_approval = account.ai_missions.in_progress.select(&:awaiting_approval?).size
        completed_24h = account.ai_missions.completed.where("completed_at >= ?", 24.hours.ago).count
        failed_24h = account.ai_missions.failed.where("ai_missions.updated_at >= ?", 24.hours.ago).count

        # Agent & conversation counts
        active_agents = account.ai_agents.active.count
        active_conversations = Ai::Conversation.where(account: account).active.count

        # Error rate (last 24h)
        total_events_24h = Ai::ExecutionEvent.where(account_id: account.id).in_time_range(24.hours.ago).count
        error_events_24h = Ai::ExecutionEvent.where(account_id: account.id).with_errors.in_time_range(24.hours.ago).count
        error_rate = total_events_24h > 0 ? (error_events_24h.to_f / total_events_24h * 100).round(1) : 0.0

        # Provider status
        providers = Ai::Provider.where(account_id: account.id).map do |p|
          credential = p.provider_credentials.where(is_active: true, account_id: account.id).first
          {
            name: p.name,
            provider_type: p.provider_type,
            has_active_credential: credential.present?
          }
        end

        # Pending notifications (if user context available)
        pending_notifications = user ? user.notifications.active.unread.count : nil

        {
          success: true,
          timestamp: now.iso8601,
          missions: {
            active: active_missions,
            awaiting_approval: awaiting_approval,
            completed_24h: completed_24h,
            failed_24h: failed_24h
          },
          agents: { active: active_agents },
          conversations: { active: active_conversations },
          errors: {
            total_events_24h: total_events_24h,
            error_events_24h: error_events_24h,
            error_rate_percent: error_rate
          },
          providers: providers,
          pending_notifications: pending_notifications
        }
      end

      # --- Serializers ---

      def serialize_mission_brief(mission)
        {
          id: mission.id,
          name: mission.name,
          mission_type: mission.mission_type,
          status: mission.status,
          current_phase: mission.current_phase,
          phase_progress: mission.phase_progress,
          awaiting_approval: mission.awaiting_approval?,
          repository: mission.repository&.full_name,
          team: mission.team&.name,
          updated_at: mission.updated_at&.iso8601
        }
      end

      def serialize_conversation_brief(conversation)
        {
          id: conversation.conversation_id,
          title: conversation.title,
          agent: conversation.agent&.name,
          status: conversation.status,
          message_count: conversation.message_count,
          last_activity_at: conversation.last_activity_at&.iso8601
        }
      end

      def serialize_event(event)
        {
          id: event.id,
          source_type: event.source_type,
          source_id: event.source_id,
          event_type: event.event_type,
          status: event.status,
          created_at: event.created_at&.iso8601
        }
      end

      def serialize_error(event)
        {
          id: event.id,
          source_type: event.source_type,
          source_id: event.source_id,
          event_type: event.event_type,
          error_class: event.error_class,
          error_message: event.error_message&.truncate(500),
          created_at: event.created_at&.iso8601
        }
      end

      def serialize_notification(notification)
        {
          id: notification.id,
          type: notification.notification_type,
          title: notification.title,
          message: notification.message,
          severity: notification.severity,
          category: notification.category,
          action_url: notification.action_url,
          action_label: notification.action_label,
          metadata: notification.metadata,
          created_at: notification.created_at&.iso8601
        }
      end
    end
  end
end
