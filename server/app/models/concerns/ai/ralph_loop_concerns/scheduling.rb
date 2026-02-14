# frozen_string_literal: true

module Ai
  module RalphLoopConcerns
    module Scheduling
      extend ActiveSupport::Concern

      # Calculate next execution time based on scheduling mode
      def calculate_next_scheduled_at
        case scheduling_mode
        when "scheduled"
          parse_cron_next_occurrence
        when "continuous"
          Time.current + (schedule_config["iteration_interval_seconds"] || 300).seconds
        else
          nil
        end
      end

      # Schedule the next iteration
      def schedule_next_iteration!
        return unless scheduling_mode.in?(%w[scheduled continuous])
        return if schedule_paused?
        return if exceeded_daily_limit?

        update!(
          next_scheduled_at: calculate_next_scheduled_at,
          last_scheduled_at: Time.current
        )
      end

      # Pause the schedule
      def pause_schedule!(reason: nil)
        update!(
          schedule_paused: true,
          schedule_paused_at: Time.current,
          schedule_paused_reason: reason
        )
      end

      # Resume the schedule
      def resume_schedule!
        update!(
          schedule_paused: false,
          schedule_paused_at: nil,
          schedule_paused_reason: nil,
          next_scheduled_at: calculate_next_scheduled_at
        )
      end

      # Check if daily iteration limit exceeded
      def exceeded_daily_limit?
        max_per_day = schedule_config["max_iterations_per_day"]
        return false if max_per_day.blank?

        reset_daily_counter_if_needed
        daily_iteration_count >= max_per_day
      end

      # Increment daily iteration count
      def increment_daily_iteration_count!
        reset_daily_counter_if_needed
        increment!(:daily_iteration_count)
      end

      # Check if loop is schedulable
      def schedulable?
        scheduling_mode.in?(%w[scheduled continuous event_triggered])
      end

      # Check if within schedule date range
      def within_schedule_range?
        start_at = schedule_config["start_at"]&.to_datetime
        end_at = schedule_config["end_at"]&.to_datetime
        now = Time.current

        (start_at.nil? || now >= start_at) && (end_at.nil? || now <= end_at)
      end

      # Check if should skip when already running
      def should_skip_if_running?
        schedule_config["skip_if_running"] != false && status == "running"
      end

      # Regenerate webhook token
      def regenerate_webhook_token!
        token = SecureRandom.urlsafe_base64(32)
        update!(webhook_token: token)
        token
      end

      private

      # Parse cron expression and get next occurrence
      def parse_cron_next_occurrence
        cron_expr = schedule_config["cron_expression"]
        return nil if cron_expr.blank?

        begin
          cron = Fugit::Cron.parse(cron_expr)
          return nil unless cron

          timezone = schedule_config["timezone"] || "UTC"
          cron.next_time(Time.current.in_time_zone(timezone)).to_time
        rescue StandardError => e
          Rails.logger.error("Failed to parse cron expression '#{cron_expr}': #{e.message}")
          nil
        end
      end

      # Reset daily counter if it's a new day
      def reset_daily_counter_if_needed
        return if daily_iteration_reset_at == Date.current

        update_columns(
          daily_iteration_count: 0,
          daily_iteration_reset_at: Date.current
        )
      end

      # Generate webhook token for event-triggered mode
      def generate_webhook_token
        return if webhook_token.present?

        self.webhook_token = SecureRandom.urlsafe_base64(32)
      end

      # Update next scheduled time when scheduling mode changes
      def update_next_scheduled_at
        if scheduling_mode.in?(%w[scheduled continuous])
          update_columns(next_scheduled_at: calculate_next_scheduled_at)
        else
          update_columns(next_scheduled_at: nil)
        end
      end

      # Validate schedule configuration
      def validate_schedule_config
        case scheduling_mode
        when "scheduled"
          if schedule_config["cron_expression"].blank?
            errors.add(:schedule_config, "must include cron_expression for scheduled mode")
          else
            begin
              cron = Fugit::Cron.parse(schedule_config["cron_expression"])
              errors.add(:schedule_config, "has invalid cron_expression") unless cron
            rescue StandardError
              errors.add(:schedule_config, "has invalid cron_expression")
            end
          end
        when "continuous"
          interval = schedule_config["iteration_interval_seconds"]
          if interval.blank? || interval.to_i < 60
            errors.add(:schedule_config, "must include iteration_interval_seconds (min 60) for continuous mode")
          end
        end
      end
    end
  end
end
