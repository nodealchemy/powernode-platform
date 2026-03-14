# frozen_string_literal: true

module Ai
  module Intelligence
    class OpsIntelligenceService < BaseIntelligenceService
      # =====================================================================
      # Notification Constants
      # =====================================================================

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

      # =====================================================================
      # Monitoring Intelligence Methods
      # =====================================================================

      # Analyze CircuitBreaker patterns to predict failures
      def predictive_failure(service_name: nil)
        breakers = Monitoring::CircuitBreaker.all
        breakers = breakers.for_service(service_name) if service_name.present?

        predictions = breakers.map { |cb| predict_failure(cb) }.compact
                              .sort_by { |p| -p[:failure_probability] }

        overall_risk = if predictions.any? { |p| p[:risk_level] == "high" }
                         "high"
                       elsif predictions.any? { |p| p[:risk_level] == "medium" }
                         "medium"
                       else
                         "low"
                       end

        success_response(
          predictions: predictions,
          overall_risk: overall_risk,
          total_breakers: breakers.count,
          unhealthy_count: breakers.unhealthy.count,
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("predictive_failure", e)
      end

      # Based on circuit breaker states, suggest remediation actions
      def self_healing_recommendations
        breakers = Monitoring::CircuitBreaker.all.includes(:circuit_breaker_events)
        unhealthy = breakers.unhealthy

        recommendations = unhealthy.map { |cb| build_recommendation(cb) }
                                   .sort_by { |r| priority_order(r[:priority]) }

        success_response(
          recommendations: recommendations,
          total_unhealthy: unhealthy.count,
          total_monitored: breakers.count,
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("self_healing_recommendations", e)
      end

      # Analyze circuit breaker events for SLA risk
      def sla_breach_risk
        breakers = Monitoring::CircuitBreaker.all
        period = 24.hours.ago

        sla_data = breakers.map { |cb| calculate_sla_risk(cb, period) }
                           .sort_by { |s| s[:uptime_percentage] }

        at_risk = sla_data.count { |s| s[:uptime_percentage] < 99.9 }

        success_response(
          services: sla_data,
          at_risk_count: at_risk,
          total_monitored: breakers.count,
          period_hours: 24,
          analyzed_at: Time.current.iso8601
        )
      rescue StandardError => e
        error_response("sla_breach_risk", e)
      end

      # =====================================================================
      # Notification Intelligence Methods
      # =====================================================================

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

      # --- Monitoring private methods ---

      def predict_failure(cb)
        events = cb.circuit_breaker_events.where("created_at >= ?", 1.hour.ago)
        total_events = events.count
        return nil if total_events.zero? && cb.closed?

        failure_count = events.failures.count
        timeout_count = events.timeouts.count
        state_changes = events.state_changes.count

        # Calculate failure probability based on recent patterns
        failure_rate = total_events > 0 ? (failure_count + timeout_count).to_f / total_events : 0
        state_change_weight = [state_changes * 0.1, 0.3].min
        current_state_weight = case cb.state
                               when "open" then 0.5
                               when "half_open" then 0.3
                               else 0.0
                               end

        probability = (failure_rate * 0.5 + state_change_weight + current_state_weight).clamp(0, 1)

        risk_level = if probability > 0.7 then "high"
                    elsif probability > 0.4 then "medium"
                    else "low"
                    end

        {
          circuit_breaker_id: cb.id,
          name: cb.name,
          service: cb.service,
          current_state: cb.state,
          failure_probability: probability.round(3),
          risk_level: risk_level,
          recent_failures: failure_count,
          recent_timeouts: timeout_count,
          state_changes: state_changes,
          failure_count: cb.failure_count,
          last_failure_at: cb.last_failure_at&.iso8601
        }
      end

      def build_recommendation(cb)
        events = cb.circuit_breaker_events.where("created_at >= ?", 1.hour.ago)
        failure_events = events.failures
        timeout_events = events.timeouts

        actions = []

        if cb.open?
          actions << { action: "attempt_reset", description: "Trigger half-open state to test service recovery" }
        end

        if timeout_events.count > failure_events.count
          actions << { action: "increase_timeout", description: "Increase timeout from #{cb.timeout_seconds}s to #{cb.timeout_seconds * 2}s" }
        end

        if failure_events.count >= cb.failure_threshold
          actions << { action: "restart_service", description: "Service '#{cb.service}' has reached failure threshold - consider restart" }
          actions << { action: "add_retries", description: "Add retry logic with exponential backoff for transient failures" }
        end

        if cb.half_open? && cb.success_count == 0
          actions << { action: "investigate_dependency", description: "Service stuck in half-open with no successes - check downstream dependencies" }
        end

        actions << { action: "monitor_closely", description: "Continue monitoring and escalate if state doesn't improve within #{cb.reset_timeout_seconds}s" } if actions.empty?

        priority = cb.open? ? "critical" : cb.half_open? ? "high" : "medium"

        {
          circuit_breaker_id: cb.id,
          name: cb.name,
          service: cb.service,
          current_state: cb.state,
          failure_count: cb.failure_count,
          priority: priority,
          actions: actions
        }
      end

      def calculate_sla_risk(cb, period)
        events = cb.circuit_breaker_events.where("created_at >= ?", period)
        state_changes = events.state_changes.order(:created_at)

        total_seconds = (Time.current - period).to_f
        downtime_seconds = 0.0

        # Calculate downtime from state change events
        open_at = nil
        state_changes.each do |event|
          if event.new_state == "open"
            open_at = event.created_at
          elsif event.new_state.in?(%w[closed half_open]) && open_at.present?
            downtime_seconds += (event.created_at - open_at).to_f
            open_at = nil
          end
        end

        # If currently open, count until now
        if cb.open? && open_at.present?
          downtime_seconds += (Time.current - open_at).to_f
        elsif cb.open? && cb.opened_at.present? && cb.opened_at >= period
          downtime_seconds += (Time.current - cb.opened_at).to_f
        end

        uptime_pct = total_seconds > 0 ? ((1.0 - downtime_seconds / total_seconds) * 100).round(3) : 100.0
        uptime_pct = [uptime_pct, 0].max

        breach_risk = if uptime_pct < 99.0 then "critical"
                     elsif uptime_pct < 99.9 then "high"
                     elsif uptime_pct < 99.95 then "medium"
                     else "low"
                     end

        {
          circuit_breaker_id: cb.id,
          name: cb.name,
          service: cb.service,
          current_state: cb.state,
          uptime_percentage: uptime_pct,
          downtime_seconds: downtime_seconds.round(1),
          breach_risk: breach_risk,
          state_transitions: state_changes.count
        }
      end

      def priority_order(priority)
        %w[critical high medium low].index(priority) || 99
      end

      # --- Notification private methods ---

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
    end
  end
end
