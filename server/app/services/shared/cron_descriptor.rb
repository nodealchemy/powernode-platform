# frozen_string_literal: true

module Shared
  # Converts cron expressions to human-readable descriptions
  # Used by Schedulable concern and schedule-related UI components.
  #
  # Example usage:
  #   Shared::CronDescriptor.describe("0 9 * * 1-5")
  #   # => "At 09:00 on Monday through Friday"
  #
  class CronDescriptor
    WEEKDAYS = {
      "0" => "Sunday",
      "1" => "Monday",
      "2" => "Tuesday",
      "3" => "Wednesday",
      "4" => "Thursday",
      "5" => "Friday",
      "6" => "Saturday",
      "7" => "Sunday"
    }.freeze

    WEEKDAY_RANGES = {
      "1-5" => "Monday through Friday",
      "0-6" => "every day",
      "1-7" => "Monday through Sunday",
      "6,0" => "weekends",
      "0,6" => "weekends"
    }.freeze

    MONTHS = {
      "1" => "January",
      "2" => "February",
      "3" => "March",
      "4" => "April",
      "5" => "May",
      "6" => "June",
      "7" => "July",
      "8" => "August",
      "9" => "September",
      "10" => "October",
      "11" => "November",
      "12" => "December"
    }.freeze

    class << self
      # Describe a cron expression in human-readable format
      #
      # @param cron_expression [String] The cron expression
      # @return [String] Human-readable description
      def describe(cron_expression)
        new(cron_expression).describe
      end
    end

    def initialize(cron_expression)
      @cron_expression = cron_expression.to_s.strip
      @parts = @cron_expression.split(/\s+/)
    end

    def describe
      return "Invalid cron expression" unless valid?

      minute, hour, day, month, weekday = @parts[0..4]

      parts = []
      parts << time_description(minute, hour)
      parts << day_description(day, weekday)
      parts << month_description(month)

      parts.compact.join(" ").strip.presence || @cron_expression
    end

    private

    def valid?
      @parts.length >= 5
    end

    def time_description(minute, hour)
      if minute == "*" && hour == "*"
        "Every minute"
      elsif minute == "*/5" && hour == "*"
        "Every 5 minutes"
      elsif minute == "*/10" && hour == "*"
        "Every 10 minutes"
      elsif minute == "*/15" && hour == "*"
        "Every 15 minutes"
      elsif minute == "*/30" && hour == "*"
        "Every 30 minutes"
      elsif minute == "0" && hour == "*"
        "Every hour"
      elsif minute == "0" && hour == "*/2"
        "Every 2 hours"
      elsif minute == "0" && hour == "*/4"
        "Every 4 hours"
      elsif minute == "0" && hour == "*/6"
        "Every 6 hours"
      elsif minute == "0" && hour == "*/12"
        "Every 12 hours"
      elsif minute != "*" && hour != "*"
        formatted_hour = hour.rjust(2, "0")
        formatted_minute = minute.rjust(2, "0")
        "At #{formatted_hour}:#{formatted_minute}"
      elsif minute != "*" && hour == "*"
        "At minute #{minute} of every hour"
      elsif minute == "*" && hour != "*"
        "Every minute during hour #{hour}"
      else
        nil
      end
    end

    def day_description(day, weekday)
      if day != "*" && weekday == "*"
        ordinal = ordinal_suffix(day.to_i)
        "on the #{day}#{ordinal}"
      elsif day == "*" && weekday != "*"
        weekday_desc(weekday)
      elsif day != "*" && weekday != "*"
        ordinal = ordinal_suffix(day.to_i)
        "on the #{day}#{ordinal} and #{weekday_desc(weekday)}"
      else
        nil
      end
    end

    def weekday_desc(weekday)
      # Check for common ranges
      return "on #{WEEKDAY_RANGES[weekday]}" if WEEKDAY_RANGES.key?(weekday)

      # Handle comma-separated days
      if weekday.include?(",")
        days = weekday.split(",").map { |d| WEEKDAYS[d.strip] }.compact
        return "on #{days.join(', ')}" if days.any?
      end

      # Handle range notation (e.g., "1-5")
      if weekday.include?("-")
        start_day, end_day = weekday.split("-").map { |d| WEEKDAYS[d.strip] }
        return "on #{start_day} through #{end_day}" if start_day && end_day
      end

      # Single day
      day_name = WEEKDAYS[weekday]
      day_name ? "on #{day_name}" : nil
    end

    def month_description(month)
      return nil if month == "*"

      # Handle comma-separated months
      if month.include?(",")
        months = month.split(",").map { |m| MONTHS[m.strip] }.compact
        return "in #{months.join(', ')}" if months.any?
      end

      # Handle range notation
      if month.include?("-")
        start_month, end_month = month.split("-").map { |m| MONTHS[m.strip] }
        return "from #{start_month} to #{end_month}" if start_month && end_month
      end

      # Single month
      month_name = MONTHS[month]
      month_name ? "in #{month_name}" : nil
    end

    def ordinal_suffix(number)
      if (11..13).include?(number % 100)
        "th"
      else
        case number % 10
        when 1 then "st"
        when 2 then "nd"
        when 3 then "rd"
        else "th"
        end
      end
    end
  end
end
