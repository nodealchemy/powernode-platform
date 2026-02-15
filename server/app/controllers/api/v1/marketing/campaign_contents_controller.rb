# frozen_string_literal: true

module Api
  module V1
    module Marketing
      class CampaignContentsController < ApplicationController
        before_action :set_campaign
        before_action :set_content, only: %i[show update destroy approve reject]

        # GET /api/v1/marketing/campaigns/:campaign_id/contents
        def index
          authorize_read!

          scope = @campaign.campaign_contents
          scope = scope.by_channel(params[:channel]) if params[:channel].present?
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.order(created_at: :desc)

          render_success(items: scope.map(&:content_summary))
        end

        # GET /api/v1/marketing/campaigns/:campaign_id/contents/:id
        def show
          authorize_read!

          render_success(content: @content.content_details)
        end

        # POST /api/v1/marketing/campaigns/:campaign_id/contents
        def create
          authorize_manage!

          content = @campaign.campaign_contents.build(content_params)
          content.status ||= "draft"

          if content.save
            render_success({ content: content.content_details }, status: :created)
          else
            render_error(content.errors.full_messages, status: :unprocessable_content)
          end
        end

        # PATCH/PUT /api/v1/marketing/campaigns/:campaign_id/contents/:id
        def update
          authorize_manage!

          if @content.update(content_params)
            render_success(content: @content.content_details)
          else
            render_error(@content.errors.full_messages, status: :unprocessable_content)
          end
        end

        # DELETE /api/v1/marketing/campaigns/:campaign_id/contents/:id
        def destroy
          authorize_manage!

          @content.destroy!
          render_success(message: "Content deleted successfully")
        end

        # POST /api/v1/marketing/campaigns/:campaign_id/contents/generate
        def generate
          authorize_manage!

          service = ::Marketing::CampaignContentGeneratorService.new(@campaign)
          contents = service.generate(
            channel: params[:channel] || "email",
            variant_count: params[:variant_count]&.to_i || 1,
            options: generate_options
          )

          render_success({ contents: contents.map(&:content_details) }, status: :created)
        rescue ::Marketing::CampaignContentGeneratorService::GenerationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/marketing/campaigns/:campaign_id/contents/:id/approve
        def approve
          authorize_approve!

          @content.approve!(current_user)
          render_success(content: @content.content_details)
        end

        # POST /api/v1/marketing/campaigns/:campaign_id/contents/:id/reject
        def reject
          authorize_approve!

          @content.reject!
          render_success(content: @content.content_details)
        end

        private

        def set_campaign
          @campaign = current_user.account.marketing_campaigns.find(params[:campaign_id])
        end

        def set_content
          @content = @campaign.campaign_contents.find(params[:id])
        end

        def content_params
          params.require(:content).permit(
            :channel, :variant_name, :subject, :preview_text,
            :body, :cta_text, :cta_url,
            media_urls: [],
            platform_specific: {}
          )
        end

        def generate_options
          params.permit(:subject, :preview_text, :body, :cta_text, :cta_url).to_h.symbolize_keys
        end

        def authorize_read!
          return if current_user.has_permission?("marketing.campaigns.read")

          render_error("Insufficient permissions", status: :forbidden)
        end

        def authorize_manage!
          return if current_user.has_permission?("marketing.campaigns.manage")

          render_error("Insufficient permissions", status: :forbidden)
        end

        def authorize_approve!
          return if current_user.has_permission?("marketing.content.approve")

          render_error("Insufficient permissions", status: :forbidden)
        end
      end
    end
  end
end
