# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Scheduler node executor - dispatches scheduled workflow resume to worker
    #
    # Configuration:
    # - schedule_type: delay, cron, datetime, relative
    # - delay: Duration to wait (for delay type) in seconds
    # - cron_expression: Cron schedule (for cron type)
    # - datetime: Specific datetime (for datetime type)
    # - relative_to: Reference variable for relative scheduling
    # - timezone: Timezone for scheduling
    # - max_executions: Limit for cron schedules
    # - skip_if_past: Skip if scheduled time has passed
    #
    class Scheduler < Base
      include Concerns::WorkerDispatch

      SCHEDULE_TYPES = %w[delay cron datetime relative].freeze

      protected

      def perform_execution
        log_info "Executing scheduler node"

        schedule_type = configuration["schedule_type"] || "delay"
        delay = configuration["delay"] || 0
        cron_expression = configuration["cron_expression"]
        datetime_str = resolve_value(configuration["datetime"])
        relative_to = resolve_value(configuration["relative_to"])
        offset = configuration["offset"] || 0
        timezone = configuration["timezone"] || "UTC"
        max_executions = configuration["max_executions"]
        skip_if_past = configuration.fetch("skip_if_past", true)
        resume_workflow = configuration.fetch("resume_workflow", true)

        validate_configuration!(schedule_type, delay, cron_expression, datetime_str)

        next_execution = calculate_next_execution(
          schedule_type, delay, cron_expression, datetime_str,
          relative_to, offset, timezone, skip_if_past
        )

        # If skipped (past time), return immediately
        if next_execution.nil? && skip_if_past
          return build_skipped_output(schedule_type)
        end

        workflow_run = @orchestrator&.workflow_run
        delay_seconds = next_execution ? [(next_execution - Time.current).to_i, 0].max : 0

        payload = {
          workflow_run_id: workflow_run&.id,
          node_id: @node.node_id,
          schedule_type: schedule_type,
          delay_seconds: delay_seconds,
          resume_at: next_execution&.iso8601,
          cron_expression: cron_expression,
          timezone: timezone,
          max_executions: max_executions,
          resume_workflow: resume_workflow
        }

        log_info "Dispatching schedule: #{schedule_type}, next execution in #{delay_seconds}s"

        dispatch_to_worker("Mcp::McpWorkflowResumeJob", payload)
      end

      private

      def validate_configuration!(schedule_type, delay, cron_expression, datetime_str)
        unless SCHEDULE_TYPES.include?(schedule_type)
          raise ArgumentError, "Invalid schedule_type: #{schedule_type}. Allowed: #{SCHEDULE_TYPES.join(', ')}"
        end

        case schedule_type
        when "delay"
          raise ArgumentError, "delay must be positive" if delay.to_i <= 0
        when "cron"
          raise ArgumentError, "cron_expression is required for cron schedule" if cron_expression.blank?
          validate_cron_expression!(cron_expression)
        when "datetime"
          raise ArgumentError, "datetime is required for datetime schedule" if datetime_str.blank?
        end
      end

      def validate_cron_expression!(expression)
        parts = expression.strip.split(/\s+/)
        unless parts.length.between?(5, 6)
          raise ArgumentError, "Invalid cron expression: must have 5-6 fields"
        end
      end

      def calculate_next_execution(schedule_type, delay, cron_expression, datetime_str,
                                   relative_to, offset, timezone, skip_if_past)
        case schedule_type
        when "delay"
          Time.current + delay.to_i.seconds
        when "cron"
          calculate_cron_next(cron_expression, timezone)
        when "datetime"
          parse_datetime(datetime_str, timezone, skip_if_past)
        when "relative"
          calculate_relative(relative_to, offset)
        end
      end

      def calculate_cron_next(cron_expression, timezone)
        # Use Fugit if available for precise cron parsing
        if defined?(Fugit)
          cron = Fugit.parse_cron(cron_expression)
          tz = ActiveSupport::TimeZone[timezone] || Time.zone
          cron.next_time(Time.current.in_time_zone(tz)).to_t
        else
          # Basic fallback: schedule 1 hour from now
          Time.current + 1.hour
        end
      end

      def parse_datetime(datetime_str, timezone, skip_if_past)
        tz = ActiveSupport::TimeZone[timezone] || Time.zone
        scheduled_time = tz.parse(datetime_str)

        if scheduled_time < Time.current && skip_if_past
          nil
        else
          scheduled_time
        end
      rescue ArgumentError => e
        raise ArgumentError, "Invalid datetime format: #{e.message}"
      end

      def calculate_relative(relative_to, offset)
        reference_time = if relative_to.is_a?(String)
                           Time.parse(relative_to) rescue nil
                         else
                           relative_to
                         end

        raise ArgumentError, "Could not parse relative_to as datetime" if reference_time.nil?

        reference_time + offset.to_i.seconds
      end

      def build_skipped_output(schedule_type)
        {
          output: {
            scheduled: false,
            schedule_type: schedule_type,
            skipped: true
          },
          data: {
            status: "skipped",
            schedule_type: schedule_type,
            reason: "Scheduled time is in the past"
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "scheduler",
            executed_at: Time.current.iso8601,
            workflow_state: "continuing"
          }
        }
      end

      def resolve_value(value)
        return nil if value.nil?

        if value.is_a?(String) && value.match?(/\$\{\{(.+?)\}\}|\{\{(.+?)\}\}/)
          variable_name = value.match(/\$?\{\{(.+?)\}\}/)[1].strip
          get_variable(variable_name) || value
        else
          value
        end
      end
    end
  end
end
