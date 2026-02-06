# frozen_string_literal: true

module Ai
  class SkillService
    attr_reader :account

    class ValidationError < StandardError; end
    class NotFoundError < StandardError; end

    def initialize(account:)
      @account = account
    end

    def list_skills(filters: {}, page: 1, per_page: 20)
      skills = Ai::Skill.for_account(account&.id)

      skills = skills.by_category(filters[:category]) if filters[:category].present?
      skills = skills.where(status: filters[:status]) if filters[:status].present?
      skills = skills.where(is_enabled: filters[:enabled] == "true") if filters[:enabled].present?

      if filters[:search].present?
        query = "%#{sanitize_sql_like(filters[:search])}%"
        skills = skills.where("name ILIKE :q OR description ILIKE :q", q: query)
      end

      skills.order(is_system: :desc, name: :asc)
            .page(page).per(per_page)
    end

    def find_skill(skill_id:)
      Ai::Skill.for_account(account&.id).find(skill_id)
    rescue ActiveRecord::RecordNotFound
      raise NotFoundError, "Skill not found"
    end

    def create_skill(attributes:, knowledge_base_id: nil, mcp_server_ids: [])
      skill = Ai::Skill.new(attributes)
      skill.account = account
      skill.ai_knowledge_base_id = knowledge_base_id if knowledge_base_id.present?

      Ai::Skill.transaction do
        skill.save!
        attach_mcp_servers(skill, mcp_server_ids) if mcp_server_ids.present?
      end

      skill
    rescue ActiveRecord::RecordInvalid => e
      raise ValidationError, e.message
    end

    def update_skill(skill_id:, attributes:, mcp_server_ids: nil)
      skill = find_skill(skill_id: skill_id)
      raise ValidationError, "Cannot modify system skills" if skill.is_system && account.present?

      Ai::Skill.transaction do
        skill.update!(attributes)
        if mcp_server_ids
          validated_ids = scoped_mcp_servers.where(id: mcp_server_ids).pluck(:id)
          skill.mcp_server_ids = validated_ids
        end
      end

      skill.reload
    rescue ActiveRecord::RecordInvalid => e
      raise ValidationError, e.message
    end

    def delete_skill(skill_id:)
      skill = find_skill(skill_id: skill_id)
      raise ValidationError, "Cannot delete system skills" if skill.is_system

      skill.destroy!
    end

    def toggle_skill(skill_id:, enabled:)
      skill = find_skill(skill_id: skill_id)

      if enabled
        skill.activate!
      else
        skill.deactivate!
      end

      skill
    end

    def assign_to_agent(skill_id:, agent_id:, priority: 0)
      skill = find_skill(skill_id: skill_id)
      agent = account.ai_agents.find(agent_id)

      agent_skill = Ai::AgentSkill.create!(
        ai_agent_id: agent.id,
        ai_skill_id: skill.id,
        priority: priority
      )
      agent_skill
    rescue ActiveRecord::RecordInvalid => e
      raise ValidationError, e.message
    rescue ActiveRecord::RecordNotFound
      raise NotFoundError, "Agent not found"
    end

    def remove_from_agent(skill_id:, agent_id:)
      agent_skill = Ai::AgentSkill.find_by!(ai_agent_id: agent_id, ai_skill_id: skill_id)
      agent_skill.destroy!
    rescue ActiveRecord::RecordNotFound
      raise NotFoundError, "Agent-skill assignment not found"
    end

    def agent_skills(agent_id:)
      agent = account.ai_agents.find(agent_id)
      agent.agent_skills.includes(:skill).order(priority: :asc)
    rescue ActiveRecord::RecordNotFound
      raise NotFoundError, "Agent not found"
    end

    def skill_agents(skill_id:)
      skill = find_skill(skill_id: skill_id)
      skill.agents.includes(:creator, :provider)
    end

    private

    def attach_mcp_servers(skill, mcp_server_ids)
      servers = scoped_mcp_servers.where(id: mcp_server_ids)
      skill.mcp_servers << servers
    end

    def scoped_mcp_servers
      McpServer.where(account_id: [account&.id, nil])
    end

    def sanitize_sql_like(string)
      string.to_s.gsub(/[%_\\]/) { |m| "\\#{m}" }
    end
  end
end
