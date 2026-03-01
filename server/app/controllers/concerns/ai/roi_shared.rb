# frozen_string_literal: true

module Ai
  module RoiShared
    extend ActiveSupport::Concern

    private

    # ==========================================================================
    # AUTHORIZATION
    # ==========================================================================

    def validate_permissions
      case action_name
      when "dashboard", "summary", "trends", "daily_metrics", "by_workflow",
           "by_agent", "by_provider", "cost_breakdown", "attributions",
           "metrics", "show_metric", "projections", "recommendations", "compare"
        require_permission("ai.roi.read")
      when "calculate", "aggregate"
        require_permission("ai.roi.manage")
      end
    end

    # ==========================================================================
    # PARAMETER HANDLING
    # ==========================================================================

    def set_time_range
      range_param = params[:time_range]

      @time_range = case range_param
      when "7d", "1w" then 7.days
      when "14d", "2w" then 14.days
      when "30d", "1m" then 30.days
      when "60d", "2m" then 60.days
      when "90d", "3m" then 90.days
      when "180d", "6m" then 180.days
      when "365d", "1y" then 365.days
      else 30.days
      end
    end

    def time_range_info
      {
        start: @time_range.ago.to_date.iso8601,
        end: Date.current.iso8601,
        period: params[:time_range] || "30d",
        days: (@time_range / 1.day).to_i
      }
    end

    def pagination_data(collection)
      {
        current_page: collection.current_page,
        per_page: collection.limit_value,
        total_pages: collection.total_pages,
        total_count: collection.total_count
      }
    end
  end
end
