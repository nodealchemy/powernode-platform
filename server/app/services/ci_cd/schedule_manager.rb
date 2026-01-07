# frozen_string_literal: true

module CiCd
  # Manages scheduled pipeline executions
  class ScheduleManager
    class ScheduleError < StandardError; end

    class << self
      # Find all schedules that are due for execution
      # @param account [Account, nil] Optional account to scope
      # @return [ActiveRecord::Relation] Due schedules
      def due_schedules(account: nil)
        scope = CiCd::Schedule.active.due
        scope = scope.joins(:pipeline).where(ci_cd_pipelines: { account_id: account.id }) if account
        scope.includes(pipeline: :ai_config)
      end

      # Trigger all due schedules
      # @param account [Account, nil] Optional account to scope
      # @return [Array<CiCd::PipelineRun>] Created pipeline runs
      def trigger_due_schedules(account: nil)
        due = due_schedules(account: account)

        due.map do |schedule|
          trigger_schedule(schedule)
        rescue StandardError => e
          Rails.logger.error "Failed to trigger schedule #{schedule.id}: #{e.message}"
          nil
        end.compact
      end

      # Trigger a specific schedule
      # @param schedule [CiCd::Schedule] The schedule to trigger
      # @return [CiCd::PipelineRun] The created pipeline run
      def trigger_schedule(schedule)
        unless schedule.is_active?
          raise ScheduleError, "Schedule is not active"
        end

        unless schedule.pipeline.is_active?
          raise ScheduleError, "Pipeline is not active"
        end

        run = schedule.pipeline.pipeline_runs.create!(
          status: :pending,
          trigger_type: :schedule,
          trigger_context: build_schedule_context(schedule)
        )

        # Update schedule last/next run times
        schedule.update!(
          last_run_at: Time.current,
          next_run_at: schedule.calculate_next_run
        )

        # Queue async execution
        # CiCd::PipelineExecutionJob.perform_async(run.id)

        run
      end

      # Calculate when a schedule should next run
      # @param schedule [CiCd::Schedule] The schedule
      # @return [Time] The next run time
      def calculate_next_run(schedule)
        schedule.calculate_next_run
      end

      # Validate a cron expression
      # @param cron_expression [String] The cron expression
      # @return [Hash] Validation result
      def validate_cron(cron_expression)
        cron = Fugit::Cron.parse(cron_expression)

        if cron
          next_runs = 5.times.map do |i|
            cron.next_time(Time.current + i.hours).to_local_time
          end

          {
            valid: true,
            expression: cron_expression,
            description: describe_cron(cron_expression),
            next_runs: next_runs
          }
        else
          { valid: false, error: "Invalid cron expression" }
        end
      rescue StandardError => e
        { valid: false, error: e.message }
      end

      # Get a human-readable description of a cron expression
      # @param cron_expression [String] The cron expression
      # @return [String] Human-readable description
      def describe_cron(cron_expression)
        # Simple cron description
        parts = cron_expression.split
        return "Invalid cron" unless parts.length >= 5

        minute, hour, day, month, weekday = parts

        description = []

        # Time
        if minute == "*" && hour == "*"
          description << "every minute"
        elsif minute == "0" && hour == "*"
          description << "every hour"
        elsif minute != "*" && hour != "*"
          description << "at #{hour}:#{minute.rjust(2, '0')}"
        elsif minute != "*"
          description << "at minute #{minute}"
        end

        # Day of week
        days_map = {
          "0" => "Sunday", "1" => "Monday", "2" => "Tuesday",
          "3" => "Wednesday", "4" => "Thursday", "5" => "Friday",
          "6" => "Saturday", "*" => nil
        }

        if weekday != "*"
          day_names = weekday.split(",").map { |d| days_map[d] }.compact
          description << "on #{day_names.join(', ')}" if day_names.any?
        end

        # Day of month
        if day != "*"
          description << "on day #{day}"
        end

        # Month
        months_map = {
          "1" => "January", "2" => "February", "3" => "March",
          "4" => "April", "5" => "May", "6" => "June",
          "7" => "July", "8" => "August", "9" => "September",
          "10" => "October", "11" => "November", "12" => "December"
        }

        if month != "*"
          month_names = month.split(",").map { |m| months_map[m] }.compact
          description << "in #{month_names.join(', ')}" if month_names.any?
        end

        description.join(" ").presence || cron_expression
      end

      # Recalculate next_run_at for all active schedules
      # @param account [Account, nil] Optional account to scope
      def recalculate_all_schedules(account: nil)
        scope = CiCd::Schedule.active
        scope = scope.joins(:pipeline).where(ci_cd_pipelines: { account_id: account.id }) if account

        scope.find_each do |schedule|
          schedule.update!(next_run_at: schedule.calculate_next_run)
        rescue StandardError => e
          Rails.logger.error "Failed to recalculate schedule #{schedule.id}: #{e.message}"
        end
      end

      private

      def build_schedule_context(schedule)
        {
          schedule_id: schedule.id,
          schedule_name: schedule.name,
          cron_expression: schedule.cron_expression,
          timezone: schedule.timezone,
          inputs: schedule.inputs,
          scheduled_at: Time.current.iso8601
        }
      end
    end
  end
end
