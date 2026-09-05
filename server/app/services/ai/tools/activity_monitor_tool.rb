# frozen_string_literal: true

module Ai
  module Tools
    class ActivityMonitorTool < BaseTool
      REQUIRED_PERMISSION = "ai.agents.read"

      # APO-1a (IMP-1e58753b3b6c) — governance declarations for every action
      # this tool advertises. NON-ENFORCING: `mutating:` alone leaves
      # BaseTool#gated_action? false, so #execute still routes to #call and
      # behaviour is unchanged. Gate wiring (categories/executors) is APO-1e.
      declare_action "dismiss_all_notifications", mutating: true
      declare_action "dismiss_notification", mutating: true
      declare_action "get_activity_feed", mutating: false
      declare_action "get_mission_status", mutating: false
      declare_action "get_notifications", mutating: false
      declare_action "get_system_health", mutating: false
      declare_action "mark_all_notifications_read", mutating: true

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
            description: "Unified AI activity feed for THIS account: recent missions, conversations, " \
                         "agent execution events, and AI AGENT EXECUTION failures. The failures are " \
                         "Ai::ExecutionEvent rows, not platform or fleet errors — this feed does not " \
                         "observe node instances, and cannot tell you whether any instance is in error.",
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
            description: "Get notifications for the current user. Defaults to active+unread (default 10, max 50). Filterable by category, type, source_type, before timestamp, or unread_only=false to include read.",
            parameters: {
              limit: { type: "integer", required: false, description: "Max notifications to return (default 10, max 50)" },
              category: { type: "string", required: false, description: "Filter by category (e.g. ai, system, security)" },
              type: { type: "string", required: false, description: "Filter by notification type (e.g. autonomy_approval_required, ai_concierge_message)" },
              source_type: { type: "string", required: false, description: "Filter by metadata.source_type (e.g. system_fleet, system_cve_responder)" },
              before: { type: "string", required: false, description: "Only return notifications created before this ISO8601 timestamp" },
              unread_only: { type: "boolean", required: false, description: "Restrict to unread (default true)" }
            }
          },
          "dismiss_notification" => {
            description: "Mark a notification as read",
            parameters: {
              notification_id: { type: "string", required: true, description: "ID of the notification to dismiss" }
            }
          },
          "dismiss_all_notifications" => {
            description: "Dismiss all active notifications permanently (sets dismissed_at). Returns count of dismissed.",
            parameters: {}
          },
          "mark_all_notifications_read" => {
            description: "Mark all unread notifications as read (lighter than dismiss — still visible but marked as read). Returns count.",
            parameters: {}
          },
          "get_system_health" => {
            # SCOPE, stated because getting it wrong cost an operator a wrong
            # answer (offer 01a07024-d980): on 2026-09-05 05:57Z a Concierge
            # read this action's error block and reported "there are no node
            # instances in error status" while 12 were. This action has never
            # looked at node instances. Its counts are AI-side only.
            description: "AI-side activity snapshot for THIS account: mission counts, active agents and " \
                         "conversations, AI AGENT EXECUTION error rates, and which providers hold an active " \
                         "credential. This is NOT platform or fleet health: it does not observe node instances, " \
                         "Rails, Postgres, Redis, Sidekiq, the worker, the reverse proxy or certificates, and it " \
                         "cannot tell you whether any node instance is in error. For fleet and platform health " \
                         "use the platform_maintenance skill with action=health_check, which returns a composite " \
                         "across every subsystem and reports anything it could not observe as not_measured.",
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
        when "dismiss_all_notifications" then dismiss_all_notifications
        when "mark_all_notifications_read" then mark_all_notifications_read
        when "get_system_health" then get_system_health
        else
          { success: false, error: "Unknown action: #{params[:action]}. Valid: get_activity_feed, get_mission_status, get_notifications, dismiss_notification, dismiss_all_notifications, mark_all_notifications_read, get_system_health" }
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

        # AI AGENT EXECUTION failures, NOT platform or fleet errors. These are
        # Ai::ExecutionEvent rows — the same `with_errors` query whose sibling
        # in get_system_health was renamed after the concierge read it as fleet
        # health and told the operator no node instances were in error while
        # twelve were. This door returned the identical rows under the identical
        # bare name, so the identical misreading was still available through it.
        #
        # The scope noun is the fix, and it is the rule the lint at
        # spec/lint/no_bare_fact_result_keys_spec.rb now enforces: a count of
        # errors has to say what it counts. For node instances in error, the
        # fleet verbs are the answer, not this feed.
        agent_execution_errors = Ai::ExecutionEvent.where(account_id: account.id)
          .with_errors.in_time_range(since)
          .recent(limit)

        {
          success: true,
          window_hours: hours,
          missions: missions.map { |m| serialize_mission_brief(m) },
          conversations: conversations.map { |c| serialize_conversation_brief(c) },
          events: events.map { |e| serialize_event(e) },
          agent_execution_errors: agent_execution_errors.map { |e| serialize_error(e) },
          summary: {
            mission_count: missions.size,
            conversation_count: conversations.size,
            event_count: events.size,
            agent_execution_error_count: agent_execution_errors.size
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
        unread_only = params[:unread_only].nil? ? true : ActiveModel::Type::Boolean.new.cast(params[:unread_only])

        scope = user.notifications.active
        scope = scope.unread if unread_only
        scope = scope.where(category: params[:category]) if params[:category].present?
        scope = scope.where(notification_type: params[:type]) if params[:type].present?
        if params[:source_type].present?
          scope = scope.where("metadata ->> 'source_type' = ?", params[:source_type])
        end
        if params[:before].present?
          begin
            scope = scope.where("created_at < ?", Time.iso8601(params[:before].to_s))
          rescue ArgumentError
            return { success: false, error: "before must be an ISO8601 timestamp" }
          end
        end

        notifications = scope.recent.limit(limit)
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
        NotificationChannel.broadcast_notification_read(notification)
        { success: true, notification_id: notification.id, read_at: notification.read_at&.iso8601 }
      rescue StandardError => e
        { success: false, error: "Failed to dismiss notification: #{e.message}" }
      end

      def dismiss_all_notifications
        return { success: false, error: "User context required" } unless user

        scope = user.notifications.active
        count = scope.count
        scope.update_all(dismissed_at: Time.current)
        NotificationChannel.broadcast_all_dismissed(account, count: count)

        { success: true, dismissed_count: count }
      rescue StandardError => e
        { success: false, error: "Failed to dismiss notifications: #{e.message}" }
      end

      def mark_all_notifications_read
        return { success: false, error: "User context required" } unless user

        scope = user.notifications.active.unread
        count = scope.count
        scope.update_all(read_at: Time.current)
        NotificationChannel.broadcast_all_read(account, count: count)

        { success: true, marked_read_count: count }
      rescue StandardError => e
        { success: false, error: "Failed to mark notifications read: #{e.message}" }
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
        providers = Ai::Provider.where(account_id: account.id).includes(:provider_credentials).map do |p|
          credential = p.provider_credentials.find { |c| c.is_active? && c.account_id == account.id }
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
          # NOT platform errors. These are Ai::ExecutionEvent rows — AI agent
          # execution failures. The old key name was `errors`, which read to a
          # model choosing a tool as the platform's error count; see the action
          # description.
          agent_execution_errors: {
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
