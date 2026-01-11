# frozen_string_literal: true

module Devops
  class ScheduleSerializer
    def initialize(schedule, options = {})
      @schedule = schedule
      @options = options
    end

    def as_json
      {
        id: @schedule.id,
        name: @schedule.name,
        cron_expression: @schedule.cron_expression,
        timezone: @schedule.timezone,
        inputs: @schedule.inputs,
        next_run_at: @schedule.next_run_at,
        last_run_at: @schedule.last_run_at,
        is_active: @schedule.is_active,
        cron_description: @schedule.cron_description,
        is_due: @schedule.due?,
        pipeline_name: @schedule.pipeline.name,
        pipeline_slug: @schedule.pipeline.slug,
        created_at: @schedule.created_at,
        updated_at: @schedule.updated_at
      }
    end

    def serializable_hash
      { data: { attributes: as_json } }
    end

    def self.serialize(schedule, options = {})
      new(schedule, options).as_json
    end

    def self.serialize_collection(schedules, options = {})
      schedules.map { |schedule| serialize(schedule, options) }
    end
  end
end
