# frozen_string_literal: true

module Api
  module V1
    module Ai
      class SkillsController < ApplicationController
        include Paginatable
        include GloballyScopedContent

        before_action :authenticate_request
        before_action :set_skill, only: [:show, :update, :destroy, :activate, :deactivate, :agents]
        # clone needs create rights; update_from_source mutates the account copy.
        before_action -> { authorize_action!("ai.skills.create") }, only: [:perform_clone]
        before_action -> { authorize_action!("ai.skills.update") }, only: [:update_from_source]
        before_action -> { authorize_action!("ai.skills.read") }, only: [:update_from_source_preview]

        # The GloballyScopable model backing the clone / update_from_source actions.
        def content_model
          ::Ai::Skill
        end

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

          require_editable_content!(@skill)
          return if performed?

          result = skill_service.update_skill(
            skill_id: @skill.id,
            attributes: skill_params,
            mcp_server_ids: params.dig(:skill, :mcp_server_ids)
          )

          # require_editable_content! already blocks updating a global skill via
          # HTTP (clone via POST .../:id/clone first), so result[:cloned] is
          # normally false here — surfaced anyway in case an account's own
          # is_system-flagged row (edge case) triggers clone-on-write.
          response = { skill: result[:skill].skill_details }
          response[:cloned] = true if result[:cloned]
          render_success(response)
        rescue ::Ai::SkillService::ValidationError => e
          render_error(e.message, status: :unprocessable_content)
        end

        # DELETE /api/v1/ai/skills/:id
        def destroy
          authorize_action!("ai.skills.delete")
          return if performed?

          require_editable_content!(@skill)
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

          require_editable_content!(@skill)
          return if performed?

          skill = skill_service.toggle_skill(skill_id: @skill.id, enabled: true)

          render_success({ skill: skill.skill_summary })
        end

        # POST /api/v1/ai/skills/:id/deactivate
        def deactivate
          authorize_action!("ai.skills.update")
          return if performed?

          require_editable_content!(@skill)
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

        # Richer serialization for clone / update_from_source responses.
        def content_json(record)
          record.skill_details
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
            search: params[:search],
            scope: params[:scope]
          }.compact
        end
      end
    end
  end
end
