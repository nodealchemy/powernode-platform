# frozen_string_literal: true

# AnalyticsQueryable Concern
# Provides standardized analytics query helpers for API controllers
# Consolidates duplicate analytics patterns across controllers
#
# Usage:
#   include AnalyticsQueryable
#
#   def analytics
#     days = analytics_days_param(default: 30, max: 90)
#     records = in_analytics_period(@resource.deliveries, days)
#
#     render_success(data: build_analytics_data(records, days: days))
#   end
#
module AnalyticsQueryable
  extend ActiveSupport::Concern

  # Get normalized days parameter
  # @param default [Integer] Default number of days
  # @param max [Integer] Maximum allowed days
  # @param param_name [Symbol] Parameter name (default: :days)
  # @return [Integer] Normalized days value
  def analytics_days_param(default: 30, max: 90, param_name: :days)
    [ [ (params[param_name]&.to_i || default), 1 ].max, max ].min
  end

  # Filter collection to records within N days
  # @param collection [ActiveRecord::Relation] The collection
  # @param days [Integer] Number of days
  # @param date_column [Symbol] Column to filter on (default: :created_at)
  # @return [ActiveRecord::Relation] Filtered collection
  def in_analytics_period(collection, days, date_column: :created_at)
    collection.where("#{date_column} > ?", days.days.ago)
  end

  # Group by day using Groupdate gem
  # @param collection [ActiveRecord::Relation] The collection
  # @param date_column [Symbol] Column to group on
  # @param days [Integer] Number of days for the range
  # @return [Hash] Day-grouped counts
  def group_by_day(collection, date_column, days = 30)
    collection.group_by_day(date_column, last: days).count
  end

  # Group by a column
  # @param collection [ActiveRecord::Relation] The collection
  # @param column [Symbol] Column to group on
  # @return [Hash] Grouped counts
  def group_by_column(collection, column)
    collection.group(column).count
  end

  # Build standard analytics data structure
  # @param collection [ActiveRecord::Relation] The collection
  # @param date_column [Symbol] Column for date grouping (default: :created_at)
  # @param group_columns [Array<Symbol>] Additional columns to group by
  # @param days [Integer] Number of days for the range (default: 30)
  # @return [Hash] Analytics data
  def build_analytics_data(collection, date_column: :created_at, group_columns: [], days: 30)
    data = {
      total: collection.count,
      by_day: group_by_day(collection, date_column, days)
    }

    group_columns.each do |column|
      data["by_#{column}".to_sym] = group_by_column(collection, column)
    end

    data
  end

  # Calculate percentage change between two periods
  # @param current [Numeric] Current period value
  # @param previous [Numeric] Previous period value
  # @return [Float] Percentage change
  def percentage_change(current, previous)
    return 0.0 if previous.zero?
    ((current - previous).to_f / previous * 100).round(2)
  end

  # Build period comparison data
  # @param collection [ActiveRecord::Relation] The collection
  # @param days [Integer] Number of days for each period
  # @param date_column [Symbol] Column to use for date filtering
  # @return [Hash] Period comparison data
  def build_period_comparison(collection, days: 30, date_column: :created_at)
    current_period = collection.where("#{date_column} > ?", days.days.ago)
    previous_period = collection.where(
      "#{date_column} > ? AND #{date_column} <= ?",
      (days * 2).days.ago,
      days.days.ago
    )

    current_count = current_period.count
    previous_count = previous_period.count

    {
      current_period: current_count,
      previous_period: previous_count,
      change: current_count - previous_count,
      change_percentage: percentage_change(current_count, previous_count)
    }
  end
end
