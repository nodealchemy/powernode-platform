# frozen_string_literal: true

module Ai
  module AgentSkillActions
    extend ActiveSupport::Concern

    # GET /api/v1/ai/agents/:id/skills
    def skills
      skills = @agent.agent_skills.includes(:skill).order(priority: :asc).map do |agent_skill|
        {
          id: agent_skill.skill.id,
          name: agent_skill.skill.name,
          slug: agent_skill.skill.slug,
          category: agent_skill.skill.category,
          is_active: agent_skill.is_active,
          priority: agent_skill.priority,
          command_count: agent_skill.skill.commands&.size || 0
        }
      end

      render_success(skills: skills)
    end

    # POST /api/v1/ai/agents/:id/assign_skill
    def assign_skill
      skill = ::Ai::Skill.find(params[:skill_id])
      agent_skill = @agent.agent_skills.build(
        ai_skill_id: skill.id,
        priority: params[:priority] || 0
      )

      if agent_skill.save
        render_success(
          agent_skill: {
            id: skill.id,
            name: skill.name,
            slug: skill.slug,
            category: skill.category,
            is_active: agent_skill.is_active,
            priority: agent_skill.priority,
            command_count: skill.commands&.size || 0
          }
        )
      else
        render_validation_error(agent_skill.errors)
      end
    rescue ActiveRecord::RecordNotFound
      render_error("Skill not found", status: :not_found)
    end

    # DELETE /api/v1/ai/agents/:id/skills/:skill_id
    def remove_skill
      agent_skill = @agent.agent_skills.find_by(ai_skill_id: params[:skill_id])

      if agent_skill
        agent_skill.destroy
        render_success(message: "Skill removed from agent")
      else
        render_error("Skill not assigned to this agent", status: :not_found)
      end
    end
  end
end
