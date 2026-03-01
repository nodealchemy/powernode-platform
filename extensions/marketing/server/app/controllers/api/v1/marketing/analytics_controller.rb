# frozen_string_literal: true

module Api
  module V1
    module Marketing
      class AnalyticsController < ApplicationController
        before_action :authorize_analytics!

        # GET /api/v1/marketing/analytics/overview
        def overview
          service = analytics_service
          result = service.overview(date_range: date_range_params)

          render_success(overview: result)
        end

        # GET /api/v1/marketing/analytics/campaigns/:id
        def campaign_detail
          service = analytics_service
          result = service.campaign_detail(params[:id])

          render_success(campaign_analytics: result)
        rescue ActiveRecord::RecordNotFound
          render_error("Campaign not found", status: :not_found)
        end

        # GET /api/v1/marketing/analytics/channels
        def channels
          service = analytics_service
          result = service.channels

          render_success(channels: result)
        end

        # GET /api/v1/marketing/analytics/roi
        def roi
          service = analytics_service
          result = service.roi(date_range: date_range_params)

          render_success(roi: result)
        end

        # GET /api/v1/marketing/analytics/top_performers
        def top_performers
          service = analytics_service
          result = service.top_performers(
            limit: params[:limit]&.to_i || 10,
            metric: params[:metric] || "conversions"
          )

          render_success(top_performers: result)
        end

        private

        def analytics_service
          ::Marketing::CampaignAnalyticsService.new(current_user.account)
        end

        def date_range_params
          return nil unless params[:start_date].present? && params[:end_date].present?

          {
            start_date: Date.parse(params[:start_date]),
            end_date: Date.parse(params[:end_date])
          }
        rescue Date::Error
          nil
        end

        def authorize_analytics!
          return if current_user.has_permission?("marketing.analytics.read")

          render_error("Insufficient permissions", status: :forbidden)
        end
      end
    end
  end
end
