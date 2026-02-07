# frozen_string_literal: true

module Api
  module V1
    module Ai
      class AgentCardsController < ApplicationController
        include AuditLogging
        include ::Ai::ResourceFiltering

        before_action :set_agent_card, only: %i[show update destroy publish deprecate refresh_metrics]
        before_action :validate_permissions

        # GET /api/v1/ai/agent_cards
        # List/discover agent cards
        def index
          scope = ::Ai::AgentCard.visible_to_account(current_user.account_id)

          # Apply filters
          scope = scope.with_skill_record(params[:skill]) if params[:skill].present?
          scope = scope.with_tag(params[:tag]) if params[:tag].present?
          scope = scope.where("name ILIKE ?", "%#{params[:query]}%") if params[:query].present?
          scope = scope.where(visibility: params[:visibility]) if params[:visibility].present?
          scope = scope.where(status: params[:status]) if params[:status].present?

          # Sorting
          scope = apply_sorting(scope)

          # Pagination
          scope = apply_pagination(scope)

          render_success(
            items: scope.map(&:card_summary),
            pagination: pagination_data(scope)
          )
          log_audit_event("ai.agent_cards.list", current_user.account)
        end

        # GET /api/v1/ai/agent_cards/:id
        def show
          render_success(agent_card: @agent_card.card_details)
          log_audit_event("ai.agent_cards.read", @agent_card)
        end

        # GET /api/v1/ai/agent_cards/:id/a2a
        # Get A2A-compliant agent card JSON
        def a2a
          @agent_card = find_agent_card
          return unless @agent_card

          render json: @agent_card.to_a2a_json
        end

        # POST /api/v1/ai/agent_cards
        def create
          @agent_card = current_user.account.ai_agent_cards.build(agent_card_params)

          if @agent_card.save
            render_success({ agent_card: @agent_card.card_details }, status: :created)
            log_audit_event("ai.agent_cards.create", @agent_card)
          else
            render_validation_error(@agent_card.errors)
          end
        end

        # PATCH /api/v1/ai/agent_cards/:id
        def update
          if @agent_card.update(agent_card_update_params)
            render_success(agent_card: @agent_card.card_details)
            log_audit_event("ai.agent_cards.update", @agent_card)
          else
            render_validation_error(@agent_card.errors)
          end
        end

        # DELETE /api/v1/ai/agent_cards/:id
        def destroy
          @agent_card.destroy
          render_success(message: "Agent card deleted successfully")
          log_audit_event("ai.agent_cards.delete", current_user.account)
        end

        # POST /api/v1/ai/agent_cards/:id/publish
        def publish
          @agent_card.sync_skills_from_agent!
          @agent_card.publish!
          render_success(agent_card: @agent_card.card_details, message: "Agent card published")
          log_audit_event("ai.agent_cards.publish", @agent_card)
        end

        # POST /api/v1/ai/agent_cards/:id/deprecate
        def deprecate
          @agent_card.deprecate!(reason: params[:reason])
          render_success(agent_card: @agent_card.card_details, message: "Agent card deprecated")
          log_audit_event("ai.agent_cards.deprecate", @agent_card)
        end

        # POST /api/v1/ai/agent_cards/:id/refresh_metrics
        def refresh_metrics
          @agent_card.refresh_metrics!
          render_success(agent_card: @agent_card.card_details, message: "Metrics refreshed")
        end

        # GET /api/v1/ai/agent_cards/discover
        # Discover agents for a task
        def discover
          service = ::Ai::A2a::Service.new(account: current_user.account, user: current_user)
          result = service.discover_agents(
            skill: params[:skill],
            tag: params[:tag],
            query: params[:query],
            protocol_version: params[:protocol_version],
            page: params[:page]&.to_i || 1,
            per_page: params[:per_page]&.to_i || 20
          )

          render_success(result)
        end

        # POST /api/v1/ai/agent_cards/find_for_task
        # Find agents capable of handling a task
        def find_for_task
          service = ::Ai::A2a::Service.new(account: current_user.account, user: current_user)
          agents = service.find_agents_for_task(params[:description], limit: params[:limit]&.to_i || 10)

          render_success(agents: agents)
        end

        private

        def set_agent_card
          @agent_card = find_agent_card
        end

        def find_agent_card
          card = ::Ai::AgentCard.visible_to_account(current_user.account_id).find_by(id: params[:id])
          card ||= ::Ai::AgentCard.visible_to_account(current_user.account_id).find_by(name: params[:id])

          unless card
            render_error("Agent card not found", status: :not_found)
            return
          end

          card
        end

        def validate_permissions
          return if current_worker || current_service

          permission_map = {
            %w[index show a2a discover find_for_task] => "ai.agents.read",
            %w[create] => "ai.agents.create",
            %w[update publish deprecate refresh_metrics] => "ai.agents.update",
            %w[destroy] => "ai.agents.delete"
          }

          permission_map.each do |actions, permission|
            return require_permission(permission) if actions.include?(action_name)
          end
        end

        def agent_card_params
          params.require(:agent_card).permit(
            :ai_agent_id, :name, :description, :visibility, :endpoint_url,
            :provider_name, :provider_url, :documentation_url,
            capabilities: {}, authentication: {},
            default_input_modes: [], default_output_modes: [], tags: []
          )
        end

        def agent_card_update_params
          params.require(:agent_card).permit(
            :name, :description, :visibility, :status, :endpoint_url,
            :provider_name, :provider_url, :documentation_url,
            capabilities: {}, authentication: {},
            default_input_modes: [], default_output_modes: [], tags: []
          )
        end

        def apply_sorting(scope)
          case params[:sort]
          when "name" then scope.order(:name)
          when "created_at" then scope.order(created_at: :desc)
          when "task_count" then scope.order(task_count: :desc)
          when "success_rate" then scope.order(Arel.sql("CASE WHEN task_count > 0 THEN success_count::float / task_count ELSE 0 END DESC"))
          else scope.order(updated_at: :desc)
          end
        end
      end
    end
  end
end
