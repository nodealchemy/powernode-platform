# frozen_string_literal: true

module Ai
  module Intelligence
    class NotificationIntelligenceService
      CHANNEL_PRIORITY = {
        "security_alert" => "push",
        "payment_failed" => "email",
        "billing_reminder" => "email",
        "subscription_update" => "email",
        "system_alert" => "in_app",
        "feature_announcement" => "in_app",
        "usage_warning" => "push",
        "team_update" => "in_app",
        "workflow_complete" => "in_app",
        "export_ready" => "email",
        "invitation_received" => "email",
        "account_update" => "in_app"
      }.freeze

      FATIGUE_THRESHOLDS = {
        high: 20,
        moderate: 10
      }.freeze

      def initialize(account:)
        @account = account
        @logger = Rails.logger
      end

      # Determine best delivery channel based on notification type and user preferences
      def smart_routing(notification_id:)
        notification = find_notification!(notification_id)
        return notification unless notification.is_a?(Notification)

        preferred_channel = determine_channel(notification)

        success_response(
          notification_id: notification.id,
          notification_type: notification.notification_type,
          severity: notification.severity,
          channel: preferred_channel[:channel],
          reason: preferred_channel[:reason],
          fallback_channel: preferred_channel[:fallback],
          routed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("smart_routing", e)
      end

      # Count notifications per user, flag users receiving too many
      def fatigue_analysis(user_id: nil)
        scope = Notification.where(account_id: @account.id)
        scope = scope.where(user_id: user_id) if user_id.present?

        users = if user_id.present?
                  [User.find_by(id: user_id)].compact
                else
                  @account.users.active
                end

        analyses = users.map { |user| analyze_user_fatigue(user, scope) }
                        .sort_by { |a| -a[:daily_count] }

        high_fatigue = analyses.count { |a| a[:fatigue_level] == "high" }
        moderate_fatigue = analyses.count { |a| a[:fatigue_level] == "moderate" }

        success_response(
          analyses: analyses,
          summary: {
            total_users: analyses.size,
            high_fatigue_count: high_fatigue,
            moderate_fatigue_count: moderate_fatigue,
            no_fatigue_count: analyses.size - high_fatigue - moderate_fatigue
          },
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("fatigue_analysis", e)
      end

      # Identify users who would benefit from digest mode
      def digest_recommendations
        users = @account.users.active
        recommendations = users.filter_map { |user| recommend_digest(user) }
                               .sort_by { |r| -r[:daily_avg] }

        success_response(
          recommendations: recommendations,
          total_candidates: recommendations.size,
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("digest_recommendations", e)
      end

      private

      def find_notification!(id)
        Notification.where(account_id: @account.id).find_by(id: id) ||
          error_hash("Notification not found: #{id}")
      end

      def determine_channel(notification)
        type_channel = CHANNEL_PRIORITY[notification.notification_type]

        # High severity always gets push
        if notification.severity == "error"
          return { channel: "push", reason: "high_severity_notification", fallback: "email" }
        end

        # Check user preferences via Review::NotificationPreference if available
        pref = Review::NotificationPreference.find_by(account_id: notification.account_id)
        if pref.present?
          delivery_channels = pref.delivery_channels
          if delivery_channels.is_a?(Hash) || delivery_channels.is_a?(Array)
            preferred = delivery_channels.is_a?(Array) ? delivery_channels.first : nil
            if preferred.present?
              return { channel: preferred, reason: "user_preference", fallback: type_channel || "in_app" }
            end
          end
        end

        channel = type_channel || "in_app"
        { channel: channel, reason: "notification_type_default", fallback: "in_app" }
      end

      def analyze_user_fatigue(user, scope)
        user_notifications = scope.where(user_id: user.id)

        daily_count = user_notifications.where("created_at >= ?", 24.hours.ago).count
        weekly_count = user_notifications.where("created_at >= ?", 7.days.ago).count
        unread_count = user_notifications.unread.count

        fatigue_level = if daily_count >= FATIGUE_THRESHOLDS[:high]
                         "high"
                       elsif daily_count >= FATIGUE_THRESHOLDS[:moderate]
                         "moderate"
                       else
                         "none"
                       end

        recommendations = []
        recommendations << "Enable digest mode to batch notifications" if daily_count > 15
        recommendations << "Review notification preferences to disable non-essential alerts" if daily_count > 10
        recommendations << "#{unread_count} unread notifications suggest user may be overwhelmed" if unread_count > 50

        {
          user_id: user.id,
          email: user.email,
          daily_count: daily_count,
          weekly_count: weekly_count,
          unread_count: unread_count,
          fatigue_level: fatigue_level,
          recommendations: recommendations
        }
      end

      def recommend_digest(user)
        notifications = Notification.where(account_id: @account.id, user_id: user.id)
        daily_counts = (0..6).map do |days_ago|
          start_time = (days_ago + 1).days.ago
          end_time = days_ago.days.ago
          notifications.where(created_at: start_time..end_time).count
        end

        daily_avg = daily_counts.sum.to_f / daily_counts.size
        return nil if daily_avg < 8

        # Check if already on digest
        pref = Review::NotificationPreference.find_by(account_id: @account.id)
        already_digest = pref&.frequency.in?(%w[hourly daily weekly])
        return nil if already_digest

        type_breakdown = notifications.where("created_at >= ?", 7.days.ago)
                                      .group(:notification_type).count
                                      .sort_by { |_, v| -v }.to_h

        {
          user_id: user.id,
          email: user.email,
          daily_avg: daily_avg.round(1),
          weekly_total: daily_counts.sum,
          top_notification_types: type_breakdown.first(3).to_h,
          recommended_frequency: daily_avg > 20 ? "daily" : "hourly",
          reason: "User receives an average of #{daily_avg.round(0)} notifications per day"
        }
      end

      def success_response(**data) = { success: true }.merge(data)

      def error_hash(message) = { success: false, error: message }

      def error_response(method_name, exception)
        @logger.error("[Ai::Intelligence::NotificationIntelligenceService##{method_name}] #{exception.message}")
        @logger.error(exception.backtrace&.first(5)&.join("\n"))
        { success: false, error: exception.message }
      end
    end
  end
end
