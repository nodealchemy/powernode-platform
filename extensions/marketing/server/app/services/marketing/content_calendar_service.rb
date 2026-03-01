# frozen_string_literal: true

module Marketing
  class ContentCalendarService
    class CalendarError < StandardError; end

    def initialize(account)
      @account = account
    end

    # List calendar entries with optional date range
    def list(filters = {})
      scope = @account.marketing_content_calendars

      if filters[:start_date].present? && filters[:end_date].present?
        scope = scope.by_date_range(
          Date.parse(filters[:start_date]),
          Date.parse(filters[:end_date])
        )
      end

      scope = scope.by_type(filters[:entry_type]) if filters[:entry_type].present?
      scope = scope.where(status: filters[:status]) if filters[:status].present?
      scope = scope.where(campaign_id: filters[:campaign_id]) if filters[:campaign_id].present?

      scope.order(scheduled_date: :asc, scheduled_time: :asc)
    end

    # Create a calendar entry
    def create(params)
      entry = @account.marketing_content_calendars.build(params)
      entry.status ||= "planned"

      check_conflicts!(entry) if entry.valid?

      entry.save!
      entry
    end

    # Update a calendar entry
    def update(entry, params)
      entry.assign_attributes(params)

      check_conflicts!(entry) if entry.valid? && (entry.scheduled_date_changed? || entry.scheduled_time_changed?)

      entry.save!
      entry
    end

    # Destroy a calendar entry
    def destroy(entry)
      entry.destroy!
    end

    # Detect scheduling conflicts
    def detect_conflicts(date:, time: nil, entry_type: nil, exclude_id: nil)
      scope = @account.marketing_content_calendars.where(scheduled_date: date)
      scope = scope.where(scheduled_time: time) if time.present?
      scope = scope.where(entry_type: entry_type) if entry_type.present?
      scope = scope.where.not(id: exclude_id) if exclude_id.present?

      conflicts = scope.to_a

      {
        has_conflicts: conflicts.any?,
        count: conflicts.count,
        entries: conflicts.map(&:calendar_summary)
      }
    end

    # Get entries for a specific date range (for calendar view)
    def entries_for_range(start_date, end_date)
      entries = @account.marketing_content_calendars
                        .includes(:campaign)
                        .by_date_range(start_date, end_date)
                        .order(scheduled_date: :asc, scheduled_time: :asc)

      # Group by date for calendar rendering
      entries.group_by(&:scheduled_date).transform_values do |day_entries|
        day_entries.map(&:calendar_summary)
      end
    end

    private

    def check_conflicts!(entry)
      conflicts = detect_conflicts(
        date: entry.scheduled_date,
        time: entry.scheduled_time,
        entry_type: entry.entry_type,
        exclude_id: entry.persisted? ? entry.id : nil
      )

      return unless conflicts[:has_conflicts]

      Rails.logger.warn "[Marketing::Calendar] Scheduling conflict detected for #{entry.title} on #{entry.scheduled_date}"
    end
  end
end
