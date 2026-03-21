# frozen_string_literal: true

module System
  class OperationSerializer
    def initialize(operation)
      @operation = operation
    end

    def as_json
      {
        id: @operation.id,
        command: @operation.command,
        status: @operation.status,
        description: @operation.description,
        progress: @operation.progress,
        scheduled_at: @operation.scheduled_at,
        started_at: @operation.started_at,
        completed_at: @operation.completed_at,
        exclusive: @operation.exclusive,
        events: @operation.events,
        options: @operation.options,
        error_message: @operation.error_message,
        operable_type: @operation.operable_type,
        operable_id: @operation.operable_id,
        operable_name: operable_name,
        initiated_by_id: @operation.initiated_by_id,
        initiated_by_name: @operation.initiated_by&.full_name,
        duration: @operation.duration,
        duration_formatted: @operation.duration_formatted,
        active: @operation.active?,
        finished: @operation.finished?,
        created_at: @operation.created_at,
        updated_at: @operation.updated_at
      }
    end

    private

    def operable_name
      return nil unless @operation.operable
      @operation.operable.respond_to?(:name) ? @operation.operable.name : @operation.operable_type
    end
  end
end
