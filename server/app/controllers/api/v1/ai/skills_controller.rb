# frozen_string_literal: true

module Api
  module V1
    module Ai
      class SkillsController < ApplicationController
        before_action :authenticate_request
        before_action :set_skill, only: [:show, :update, :destroy, :activate, :deactivate, :agents]

        # GET /api/v1/ai/skills
        def index
          authorize_action!("ai.skills.read")
          return if performed?

          skills = skill_service.list_skills(
            filters: skill_filters,
            **pagination_params
          )

          render_success({
            skills: skills.map(&:skill_summary),
            pagination: pagination_meta(skills)
          })
        end

        # GET /api/v1/ai/skills/:id
        def show
          authorize_action!("ai.skills.read")
          return if performed?

          render_success({ skill: @skill.skill_details })
        end

        # POST /api/v1/ai/skills
        def create
          authorize_action!("ai.skills.create")
          return if performed?

          skill = skill_service.create_skill(
            attributes: skill_params,
            knowledge_base_id: params.dig(:skill, :knowledge_base_id),
            mcp_server_ids: params.dig(:skill, :mcp_server_ids) || []
          )

          render_success({ skill: skill.skill_details }, status: :created)
        rescue ::Ai::SkillService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # PATCH /api/v1/ai/skills/:id
        def update
          authorize_action!("ai.skills.update")
          return if performed?

          skill = skill_service.update_skill(
            skill_id: @skill.id,
            attributes: skill_params,
            mcp_server_ids: params.dig(:skill, :mcp_server_ids)
          )

          render_success({ skill: skill.skill_details })
        rescue ::Ai::SkillService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # DELETE /api/v1/ai/skills/:id
        def destroy
          authorize_action!("ai.skills.delete")
          return if performed?

          skill_service.delete_skill(skill_id: @skill.id)

          render_success(message: "Skill deleted")
        rescue ::Ai::SkillService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # POST /api/v1/ai/skills/:id/activate
        def activate
          authorize_action!("ai.skills.update")
          return if performed?

          skill = skill_service.toggle_skill(skill_id: @skill.id, enabled: true)

          render_success({ skill: skill.skill_summary })
        end

        # POST /api/v1/ai/skills/:id/deactivate
        def deactivate
          authorize_action!("ai.skills.update")
          return if performed?

          skill = skill_service.toggle_skill(skill_id: @skill.id, enabled: false)

          render_success({ skill: skill.skill_summary })
        end

        # GET /api/v1/ai/skills/:id/agents
        def agents
          authorize_action!("ai.skills.read")
          return if performed?

          skill_agents = @skill.agents.includes(:creator, :provider).map do |agent|
            { id: agent.id, name: agent.name, slug: agent.slug, agent_type: agent.agent_type, status: agent.status }
          end

          render_success({ agents: skill_agents })
        end

        # GET /api/v1/ai/skills/categories
        def categories
          authorize_action!("ai.skills.read")
          return if performed?

          render_success({ categories: ::Ai::Skill::CATEGORIES })
        end

        private

        def set_skill
          @skill = skill_service.find_skill(skill_id: params[:id])
        rescue ::Ai::SkillService::NotFoundError
          render_not_found("Skill")
        end

        def skill_service
          @skill_service ||= ::Ai::SkillService.new(account: current_account)
        end

        def skill_params
          params.require(:skill).permit(
            :name, :description, :category, :status,
            :system_prompt, :version,
            commands: [:name, :description, :argument_hint, workflow_steps: []],
            activation_rules: {},
            metadata: {},
            tags: []
          )
        end

        def skill_filters
          {
            category: params[:category],
            status: params[:status],
            enabled: params[:enabled],
            search: params[:search]
          }.compact
        end

        def authorize_action!(permission)
          return if current_user.has_permission?(permission)

          render_forbidden("You don't have permission to perform this action")
        end

        def pagination_meta(collection)
          {
            current_page: collection.current_page,
            total_pages: collection.total_pages,
            total_count: collection.total_count,
            per_page: collection.limit_value
          }
        end
      end
    end
  end
end
