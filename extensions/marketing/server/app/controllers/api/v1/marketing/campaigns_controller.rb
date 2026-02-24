# frozen_string_literal: true

module Api
  module V1
    module Marketing
      class CampaignsController < ApplicationController
        before_action :set_campaign, only: %i[show update destroy execute pause resume archive clone]

        # GET /api/v1/marketing/campaigns
        def index
          authorize_read!

          scope = current_user.account.marketing_campaigns

          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.by_type(params[:campaign_type]) if params[:campaign_type].present?
          scope = scope.where("name ILIKE ?", "%#{params[:search]}%") if params[:search].present?

          scope = scope.recent
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:campaign_summary),
            pagination: pagination_data(scope)
          )
        end

        # GET /api/v1/marketing/campaigns/:id
        def show
          authorize_read!

          render_success(campaign: @campaign.campaign_details)
        end

        # POST /api/v1/marketing/campaigns
        def create
          authorize_manage!

          service = ::Marketing::CampaignService.new(current_user.account)
          campaign = service.create(campaign_params, creator: current_user)

          render_success({ campaign: campaign.campaign_details }, status: :created)
        rescue ActiveRecord::RecordInvalid => e
          render_error(e.record.errors.full_messages, status: :unprocessable_content)
        end

        # PATCH/PUT /api/v1/marketing/campaigns/:id
        def update
          authorize_manage!

          service = ::Marketing::CampaignService.new(current_user.account)
          campaign = service.update(@campaign, campaign_params)

          render_success(campaign: campaign.campaign_details)
        rescue ActiveRecord::RecordInvalid => e
          render_error(e.record.errors.full_messages, status: :unprocessable_content)
        end

        # DELETE /api/v1/marketing/campaigns/:id
        def destroy
          authorize_manage!

          @campaign.destroy!
          render_success(message: "Campaign deleted successfully")
        end

        # POST /api/v1/marketing/campaigns/:id/execute
        def execute
          authorize_execute!

          service = ::Marketing::CampaignService.new(current_user.account)
          campaign = service.execute(@campaign)

          render_success(campaign: campaign.campaign_details)
        rescue ::Marketing::CampaignService::CampaignError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/marketing/campaigns/:id/pause
        def pause
          authorize_execute!

          service = ::Marketing::CampaignService.new(current_user.account)
          campaign = service.pause(@campaign)

          render_success(campaign: campaign.campaign_details)
        rescue ::Marketing::CampaignService::CampaignError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/marketing/campaigns/:id/resume
        def resume
          authorize_execute!

          service = ::Marketing::CampaignService.new(current_user.account)
          campaign = service.resume(@campaign)

          render_success(campaign: campaign.campaign_details)
        rescue ::Marketing::CampaignService::CampaignError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/marketing/campaigns/:id/archive
        def archive
          authorize_manage!

          service = ::Marketing::CampaignService.new(current_user.account)
          campaign = service.archive(@campaign)

          render_success(campaign: campaign.campaign_details)
        rescue ::Marketing::CampaignService::CampaignError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/marketing/campaigns/:id/clone
        def clone
          authorize_manage!

          service = ::Marketing::CampaignService.new(current_user.account)
          cloned = service.clone(@campaign, new_name: params[:name])

          render_success({ campaign: cloned.campaign_details }, status: :created)
        end

        # GET /api/v1/marketing/campaigns/statistics
        def statistics
          authorize_read!

          service = ::Marketing::CampaignService.new(current_user.account)
          stats = service.statistics

          render_success(statistics: stats)
        end

        private

        def set_campaign
          @campaign = current_user.account.marketing_campaigns.find(params[:id])
        end

        def campaign_params
          params.require(:campaign).permit(
            :name, :campaign_type, :status, :description,
            :budget_cents, :scheduled_at,
            target_audience: {},
            settings: {},
            channels: [],
            tags: []
          )
        end

        def apply_pagination(collection)
          page = params[:page]&.to_i || 1
          per_page = [params[:per_page]&.to_i || 25, 100].min
          collection.page(page).per(per_page)
        end

        def pagination_data(collection)
          {
            current_page: collection.current_page,
            per_page: collection.limit_value,
            total_pages: collection.total_pages,
            total_count: collection.total_count
          }
        end

        def authorize_read!
          return if current_user.has_permission?("marketing.campaigns.read")

          render_error("Insufficient permissions", status: :forbidden)
        end

        def authorize_manage!
          return if current_user.has_permission?("marketing.campaigns.manage")

          render_error("Insufficient permissions", status: :forbidden)
        end

        def authorize_execute!
          return if current_user.has_permission?("marketing.campaigns.execute")

          render_error("Insufficient permissions", status: :forbidden)
        end
      end
    end
  end
end
