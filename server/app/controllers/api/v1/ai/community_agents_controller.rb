# frozen_string_literal: true

module Api
  module V1
    module Ai
      class CommunityAgentsController < ApplicationController
        include AuditLogging

        before_action :set_agent, only: %i[show update destroy publish unpublish rate report]

        # GET /api/v1/ai/community/agents
        # Discover community agents
        def index
          scope = CommunityAgent.published

          # Apply filters
          scope = scope.where(category: params[:category]) if params[:category].present?
          scope = scope.where("skills @> ?", [params[:skill]].to_json) if params[:skill].present?
          scope = scope.verified if params[:verified] == "true"

          # Search
          if params[:query].present?
            scope = scope.where(
              "name ILIKE :q OR description ILIKE :q OR skills::text ILIKE :q",
              q: "%#{params[:query]}%"
            )
          end

          # Sorting
          case params[:sort]
          when "popular"
            scope = scope.order(task_count: :desc)
          when "rating"
            scope = scope.order(avg_rating: :desc, rating_count: :desc)
          when "recent"
            scope = scope.order(created_at: :desc)
          else
            scope = scope.order(reputation_score: :desc)
          end

          # Pagination
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:public_summary),
            pagination: pagination_data(scope)
          )
        end

        # GET /api/v1/ai/community/agents/:id
        def show
          render_success(agent: @agent.public_details)
        end

        # POST /api/v1/ai/community/agents
        # Register a new community agent
        def create
          agent = CommunityAgent.new(agent_params)
          agent.owner_account = current_user.account
          agent.registered_by = current_user

          if agent.save
            render_success({ agent: agent.public_details }, status: :created)
            log_audit_event("ai.community_agents.register", agent)
          else
            render_error(agent.errors.full_messages, status: :unprocessable_entity)
          end
        end

        # PATCH/PUT /api/v1/ai/community/agents/:id
        def update
          unless @agent.owner_account_id == current_user.account_id
            render_error("You can only update your own agents", status: :forbidden)
            return
          end

          if @agent.update(agent_params)
            render_success(agent: @agent.public_details)
            log_audit_event("ai.community_agents.update", @agent)
          else
            render_error(@agent.errors.full_messages, status: :unprocessable_entity)
          end
        end

        # DELETE /api/v1/ai/community/agents/:id
        def destroy
          unless @agent.owner_account_id == current_user.account_id
            render_error("You can only delete your own agents", status: :forbidden)
            return
          end

          @agent.destroy!
          render_success(message: "Agent removed from community")
          log_audit_event("ai.community_agents.delete", @agent)
        end

        # POST /api/v1/ai/community/agents/:id/publish
        def publish
          unless @agent.owner_account_id == current_user.account_id
            render_error("You can only publish your own agents", status: :forbidden)
            return
          end

          @agent.publish!
          render_success(agent: @agent.public_details)
          log_audit_event("ai.community_agents.publish", @agent)
        end

        # POST /api/v1/ai/community/agents/:id/unpublish
        def unpublish
          unless @agent.owner_account_id == current_user.account_id
            render_error("You can only unpublish your own agents", status: :forbidden)
            return
          end

          @agent.unpublish!
          render_success(agent: @agent.public_details)
          log_audit_event("ai.community_agents.unpublish", @agent)
        end

        # POST /api/v1/ai/community/agents/:id/rate
        def rate
          rating = @agent.ratings.find_or_initialize_by(user: current_user)
          rating.assign_attributes(rating_params)

          if rating.save
            render_success(
              rating: rating.rating_summary,
              agent: @agent.reload.public_details
            )
            log_audit_event("ai.community_agents.rate", @agent)
          else
            render_error(rating.errors.full_messages, status: :unprocessable_entity)
          end
        end

        # POST /api/v1/ai/community/agents/:id/report
        def report
          report = @agent.reports.new(report_params)
          report.reporter = current_user

          if report.save
            render_success(
              message: "Report submitted successfully",
              report_id: report.id
            )
            log_audit_event("ai.community_agents.report", @agent)
          else
            render_error(report.errors.full_messages, status: :unprocessable_entity)
          end
        end

        # GET /api/v1/ai/community/agents/my_agents
        # List agents owned by current account
        def my_agents
          scope = CommunityAgent.where(owner_account: current_user.account)
          scope = scope.order(created_at: :desc)
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:owner_details),
            pagination: pagination_data(scope)
          )
        end

        # GET /api/v1/ai/community/agents/categories
        def categories
          render_success(
            categories: CommunityAgent.published
                                      .distinct
                                      .pluck(:category)
                                      .compact
                                      .sort
          )
        end

        # GET /api/v1/ai/community/agents/skills
        def skills
          # Extract unique skills from all published agents
          skills = CommunityAgent.published
                                 .pluck(:skills)
                                 .flatten
                                 .compact
                                 .uniq
                                 .sort

          render_success(skills: skills)
        end

        # POST /api/v1/ai/community/agents/discover
        # AI-powered agent discovery based on task description
        def discover
          unless params[:task_description].present?
            render_error("task_description is required", status: :unprocessable_entity)
            return
          end

          service = ::A2a::Skills::CommunitySkills.new(
            account: current_user.account,
            user: current_user
          )

          result = service.discover_agents(
            query: params[:task_description],
            category: params[:category],
            min_rating: params[:min_rating]&.to_f,
            limit: params[:limit]&.to_i || 10
          )

          render_success(
            agents: result[:agents],
            query_analyzed: result[:query_analyzed]
          )
        end

        private

        def set_agent
          @agent = CommunityAgent.find(params[:id])
        end

        def agent_params
          params.require(:agent).permit(
            :name,
            :description,
            :endpoint_url,
            :category,
            :visibility,
            :documentation_url,
            :source_code_url,
            :pricing_model,
            :price_per_task,
            skills: [],
            agent_card: {},
            configuration: {}
          )
        end

        def rating_params
          params.require(:rating).permit(:score, :review, :task_id)
        end

        def report_params
          params.require(:report).permit(:reason, :description, :evidence)
        end
      end
    end
  end
end
