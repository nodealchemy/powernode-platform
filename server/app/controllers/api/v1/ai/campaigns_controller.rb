# frozen_string_literal: true

module Api
  module V1
    module Ai
      # REST API for Autonomous Improvement Campaigns — backs the Campaigns dashboard panel.
      # (Agents drive campaigns via the platform.campaign_* MCP tools; this is the human surface.)
      class CampaignsController < ApplicationController
        before_action :require_read, only: %i[index show]
        before_action :require_manage, only: %i[create answer_question stop delegate]
        before_action :set_campaign, only: %i[show answer_question stop delegate]

        # GET /api/v1/ai/campaigns
        def index
          campaigns = current_user.account.ai_campaigns.recent(params.fetch(:limit, 50).to_i)
          campaigns = campaigns.where(status: params[:status]) if params[:status].present?

          render_success(campaigns: campaigns.map(&:summary), total_count: campaigns.size)
        end

        # GET /api/v1/ai/campaigns/:id
        def show
          render_success(serialize_detail(@campaign))
        end

        # POST /api/v1/ai/campaigns  (start a campaign + its dev-loop)
        def create
          result = driver.start(
            name: params[:name],
            description: params[:description],
            configuration: permitted_hash(:configuration),
            decision_authority: params[:decision_authority].presence || "trusted",
            stop_conditions: permitted_hash(:stop_conditions)
          )
          render_success(serialize_detail(result[:campaign]), status: :created)
        rescue ActiveRecord::RecordInvalid => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/campaigns/:id/answer_question
        def answer_question
          question = driver.answer_question(@campaign, question_id: params[:question_id], answer: params[:answer])
          render_success(question: question)
        rescue ActiveRecord::RecordNotFound
          render_error("Question not found", status: :not_found)
        end

        # POST /api/v1/ai/campaigns/:id/stop
        def stop
          render_success(driver.stop(@campaign, summary: params[:summary]))
        end

        # POST /api/v1/ai/campaigns/:id/delegate
        # Route the campaign's dev-loop to a driver (claude_code | platform_*).
        def delegate
          result = driver.delegate(@campaign, driver_kind: params[:driver_kind],
                                              target: permitted_hash(:target), holder: params[:holder])
          render_success(result)
        rescue ArgumentError => e
          render_error(e.message, status: :unprocessable_content)
        end

        private

        def require_read
          require_permission("ai.campaigns.read")
        end

        def require_manage
          require_permission("ai.campaigns.manage")
        end

        def set_campaign
          @campaign = current_user.account.ai_campaigns.find(params[:id])
        end

        def driver
          ::Ai::DevLoop::CampaignDriver.new(account: current_user.account, user: current_user)
        end

        def permitted_hash(key)
          raw = params[key]
          return {} if raw.blank?

          raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
        end

        def serialize_detail(campaign)
          campaign.summary.merge(
            description: campaign.description,
            configuration: campaign.configuration,
            stop_conditions: campaign.stop_conditions,
            open_questions_list: campaign.open_questions_list.map(&:summary),
            recent_decisions: campaign.campaign_decisions.recent(20).map(&:summary),
            activity: campaign.activity_feed(limit: 20),
            progress: campaign.progress_entries.latest_first.limit(20).map(&:summary),
            loops: campaign.ralph_loops.map do |l|
              { id: l.id, name: l.name, branch: l.branch, status: l.status,
                driver_kind: l.driver_kind, driver_target: l.driver_target, total_tasks: l.ralph_tasks.count }
            end
          )
        end
      end
    end
  end
end
