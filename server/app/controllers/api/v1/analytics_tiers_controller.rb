# frozen_string_literal: true

module Api
  module V1
    class AnalyticsTiersController < ApplicationController
      skip_before_action :authenticate_request, only: [ :index, :show ]
      before_action -> { require_permission("billing.read") }, only: [:current, :comparison, :feature_gates]
      before_action -> { require_permission("billing.manage") }, only: [:upgrade]

      # GET /api/v1/analytics/tiers
      def index
        tiers = AnalyticsTier.active.ordered

        render_success(
          data: tiers.map(&:comparison_data)
        )
      end

      # GET /api/v1/analytics/tiers/current
      def current
        service = AnalyticsTierService.new(account: current_account)
        tier = service.current_tier

        render_success(
          data: tier.summary
        )
      end

      # GET /api/v1/analytics/tiers/comparison
      def comparison
        service = AnalyticsTierService.new(account: current_account)
        data = service.tier_comparison

        render_success(data: data)
      end

      # GET /api/v1/analytics/tiers/feature_gates
      def feature_gates
        service = AnalyticsTierService.new(account: current_account)
        data = service.feature_gates

        render_success(data: data)
      end

      # POST /api/v1/analytics/tiers/upgrade
      def upgrade
        new_tier_slug = params[:tier]

        unless new_tier_slug.present?
          return render_error("Tier is required", status: :bad_request)
        end

        service = AnalyticsTierService.new(account: current_account)
        result = service.upgrade_tier(new_tier_slug)

        if result[:success]
          render_success(
            data: result[:tier],
            message: "Tier upgraded successfully"
          )
        else
          render_error(result[:error], status: :unprocessable_content)
        end
      end

      # GET /api/v1/analytics/tiers/:slug
      def show
        tier = AnalyticsTier.find_by(slug: params[:slug])

        if tier
          render_success(data: tier.comparison_data)
        else
          render_error("Tier not found", status: :not_found)
        end
      end
    end
  end
end
