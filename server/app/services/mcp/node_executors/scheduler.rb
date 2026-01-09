# frozen_string_literal: true

module Mcp
  module NodeExecutors
    # Scheduler node executor - schedules workflow execution for later
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

        schedule_context = {
          schedule_type: schedule_type,
          delay: delay,
          cron_expression: cron_expression,
          datetime: datetime_str,
          relative_to: relative_to,
          offset: offset,
          timezone: timezone,
          max_executions: max_executions,
          skip_if_past: skip_if_past,
          resume_workflow: resume_workflow,
          started_at: Time.current
        }

        log_info "Scheduling with type: #{schedule_type}"

        # Calculate next execution time
        result = calculate_schedule(schedule_context)

        # Schedule the job
        schedule_result = schedule_execution(schedule_context, result)

        build_output(schedule_context, schedule_result)
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
        # Basic cron expression validation
        # Format: minute hour day_of_month month day_of_week
        parts = expression.strip.split(/\s+/)

        unless parts.length.between?(5, 6)
          raise ArgumentError, "Invalid cron expression: must have 5-6 fields"
        end

        # NOTE: In production, use a cron parser gem for full validation
      end

      def calculate_schedule(context)
        case context[:schedule_type]
        when "delay"
          calculate_delay_schedule(context)
        when "cron"
          calculate_cron_schedule(context)
        when "datetime"
          calculate_datetime_schedule(context)
        when "relative"
          calculate_relative_schedule(context)
        end
      end

      def calculate_delay_schedule(context)
        next_execution = Time.current + context[:delay].seconds

        {
          next_execution: next_execution,
          schedule_type: "delay",
          delay_seconds: context[:delay],
          is_recurring: false
        }
      end

      def calculate_cron_schedule(context)
        # NOTE: In production, use a cron parser to calculate next execution
        # For now, simulate with a placeholder

        next_execution = Time.current + 1.hour # Placeholder

        {
          next_execution: next_execution,
          schedule_type: "cron",
          cron_expression: context[:cron_expression],
          is_recurring: true,
          max_executions: context[:max_executions],
          executions_remaining: context[:max_executions]
        }
      end

      def calculate_datetime_schedule(context)
        begin
          # Parse the datetime in the specified timezone
          tz = ActiveSupport::TimeZone[context[:timezone]] || Time.zone

          scheduled_time = if context[:datetime].is_a?(String)
                            tz.parse(context[:datetime])
                          else
                            context[:datetime]
                          end

          # Check if time is in the past
          if scheduled_time < Time.current
            if context[:skip_if_past]
              return {
                next_execution: nil,
                schedule_type: "datetime",
                skipped: true,
                reason: "Scheduled time is in the past",
                original_datetime: context[:datetime]
              }
            end
          end

          {
            next_execution: scheduled_time,
            schedule_type: "datetime",
            timezone: context[:timezone],
            is_recurring: false
          }
        rescue ArgumentError => e
          raise ArgumentError, "Invalid datetime format: #{e.message}"
        end
      end

      def calculate_relative_schedule(context)
        # Relative scheduling based on another variable
        reference_time = if context[:relative_to].is_a?(String)
                          Time.parse(context[:relative_to]) rescue nil
                        else
                          context[:relative_to]
                        end

        raise ArgumentError, "Could not parse relative_to as datetime" if reference_time.nil?

        next_execution = reference_time + context[:offset].seconds

        {
          next_execution: next_execution,
          schedule_type: "relative",
          reference_time: reference_time.iso8601,
          offset_seconds: context[:offset],
          is_recurring: false
        }
      end

      def schedule_execution(context, schedule_result)
        # Generate schedule ID
        schedule_id = "sch_#{SecureRandom.hex(16)}"

        return schedule_result.merge(
          schedule_id: schedule_id,
          status: "skipped",
          job_id: nil
        ) if schedule_result[:skipped]

        # NOTE: In production, this would:
        # 1. Create a scheduled job using Sidekiq or similar
        # 2. Store the workflow execution state for resume
        # 3. Set up the callback for when the schedule fires

        job_id = "job_#{SecureRandom.hex(8)}"

        schedule_result.merge(
          schedule_id: schedule_id,
          status: "scheduled",
          job_id: job_id,
          will_resume_workflow: context[:resume_workflow]
        )
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

      def build_output(context, result)
        output_base = {
          scheduled: result[:status] == "scheduled",
          schedule_id: result[:schedule_id],
          schedule_type: context[:schedule_type]
        }

        data_base = {
          schedule_id: result[:schedule_id],
          status: result[:status],
          schedule_type: context[:schedule_type],
          timezone: context[:timezone],
          is_recurring: result[:is_recurring] || false,
          created_at: Time.current.iso8601
        }

        if result[:next_execution]
          output_base[:next_execution] = result[:next_execution].iso8601
          data_base[:next_execution] = result[:next_execution].iso8601
          data_base[:seconds_until_execution] = [(result[:next_execution] - Time.current).to_i, 0].max
        end

        if result[:skipped]
          data_base[:skipped] = true
          data_base[:skip_reason] = result[:reason]
        end

        if result[:is_recurring]
          data_base[:cron_expression] = result[:cron_expression]
          data_base[:max_executions] = result[:max_executions]
        end

        workflow_state = if result[:status] == "scheduled" && context[:resume_workflow]
                          "paused_for_schedule"
                        else
                          "continuing"
                        end

        {
          output: output_base,
          data: data_base.merge(
            job_id: result[:job_id],
            will_resume_workflow: context[:resume_workflow],
            duration_ms: ((Time.current - context[:started_at]) * 1000).round
          ),
          result: {
            scheduled: result[:status] == "scheduled",
            schedule_id: result[:schedule_id],
            next_execution: result[:next_execution]&.iso8601
          },
          metadata: {
            node_id: @node.node_id,
            node_type: "scheduler",
            executed_at: Time.current.iso8601,
            workflow_state: workflow_state
          }
        }
      end
    end
  end
end
