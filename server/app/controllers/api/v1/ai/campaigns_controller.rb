# frozen_string_literal: true

module Api
  module V1
    module Ai
      # REST API for Autonomous Improvement Campaigns — backs the Campaigns dashboard panel.
      # (Agents drive campaigns via the platform.campaign_* MCP tools; this is the human surface.)
      class CampaignsController < ApplicationController
        # First for resume: a worker token holding the permission would otherwise pass
        # require_manage and reach set_campaign with no user.
        before_action :require_human_session, only: %i[resume]
        before_action :require_read, only: %i[index show]
        before_action :require_manage, only: %i[create answer_question stop delegate resume]
        before_action :set_campaign, only: %i[show answer_question stop delegate resume]
        # Kill-switch: create/delegate/resume arm autonomous loops — refuse while AI is suspended.
        before_action :reject_if_ai_suspended, only: %i[create delegate resume]

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

        # POST /api/v1/ai/campaigns/:id/resume
        # Reopen a completed or paused campaign and adjust its stop conditions: the human
        # door onto CampaignDriver#resume, the same service the MCP verb calls. Every
        # refusal the service names comes back as a 422 carrying that reason.
        def resume
          raw = params[:stop_conditions]
          unless raw.nil? || raw.is_a?(ActionController::Parameters) || raw.is_a?(Hash)
            return render_error("stop_conditions must be an object", status: :unprocessable_content)
          end

          render_success(driver.resume(@campaign, reason: params[:reason], stop_conditions: permitted_hash(:stop_conditions)))
        rescue ArgumentError, ActiveRecord::RecordInvalid => e
          render_error(e.message, status: :unprocessable_content)
        end

        private

        # A resume re-arms a campaign past a stop that fired, so it is a human decision
        # (security review §9): only a user's own JWT session may make it. A worker token
        # has no user, and an impersonation session is an administrator acting as the user
        # it names, so the decision row would name the wrong person.
        def require_human_session
          return if current_user && current_worker.nil? && !impersonating? && current_jwt_payload&.dig(:type) == "access"

          render_error("Resuming a campaign requires a user's own session", status: :forbidden)
        end

        def require_read
          require_permission("ai.campaigns.read")
        end

        def require_manage
          require_permission("ai.campaigns.manage")
        end

        def reject_if_ai_suspended
          return unless current_user.account.ai_suspended?

          render_error("AI activity is suspended for this account", status: :conflict)
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
