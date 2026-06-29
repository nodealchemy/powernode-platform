# frozen_string_literal: true

module Ai
  module Tools
    class SkillTool < BaseTool
      REQUIRED_PERMISSION = "ai.skills.read"

      def self.definition
        {
          name: "skill_management",
          description: "Manage and discover AI skills: list, get details, discover relevant skills, create/update/delete/toggle skills, get enriched context, and check skill graph health",
          parameters: {
            action: { type: "string", required: true, description: "Action: list_skills, get_skill, discover_skills, get_skill_context, skill_health, skill_metrics, create_skill, update_skill, delete_skill, toggle_skill" },
            skill_id: { type: "string", required: false, description: "Skill ID (for get_skill, update_skill, delete_skill, toggle_skill)" },
            name: { type: "string", required: false, description: "Skill name (for create_skill, update_skill)" },
            description: { type: "string", required: false, description: "Skill description (for create_skill, update_skill)" },
            system_prompt: { type: "string", required: false, description: "System prompt template (for create_skill, update_skill)" },
            commands: { type: "array", required: false, description: "Slash commands array (for create_skill, update_skill)" },
            tags: { type: "array", required: false, description: "Tags array (for create_skill, update_skill)" },
            status: { type: "string", required: false, description: "Filter by status: active/inactive/draft (for list_skills)" },
            category: { type: "string", required: false, description: "Filter by category (for list_skills, create_skill)" },
            search: { type: "string", required: false, description: "Search query for skill name/description (for list_skills)" },
            enabled: { type: "boolean", required: false, description: "Filter by enabled: true/false (for list_skills); or boolean to set (for toggle_skill)" },
            page: { type: "integer", required: false, description: "Page number (for list_skills, default 1)" },
            per_page: { type: "integer", required: false, description: "Results per page (for list_skills, default 20)" },
            task_context: { type: "string", required: false, description: "Task description to discover relevant skills (for discover_skills)" },
            mode: { type: "string", required: false, description: "Traversal mode: auto/manifest (for discover_skills/get_skill_context, default auto)" },
            token_budget: { type: "integer", required: false, description: "Max token budget for context (for discover_skills/get_skill_context, default 2000)" },
            input_text: { type: "string", required: false, description: "Input text for context enrichment (for get_skill_context)" },
            agent_id: { type: "string", required: false, description: "Agent ID for manifest mode (for get_skill_context)" }
          }
        }
      end

      def self.action_definitions
        {
          "list_skills" => {
            description: "List AI skills with optional filters and pagination",
            parameters: {
              category: { type: "string", required: false, description: "Filter by category" },
              status: { type: "string", required: false, description: "Filter by status: active/inactive/draft" },
              enabled: { type: "boolean", required: false, description: "Filter by enabled: true/false" },
              search: { type: "string", required: false, description: "Search query for name/description" },
              page: { type: "integer", required: false, description: "Page number (default 1)" },
              per_page: { type: "integer", required: false, description: "Results per page (default 20)" }
            }
          },
          "get_skill" => {
            description: "Get detailed information about a specific AI skill",
            parameters: {
              skill_id: { type: "string", required: true, description: "Skill ID" }
            }
          },
          "discover_skills" => {
            description: "Discover relevant AI skills for a given task using graph traversal",
            parameters: {
              task_context: { type: "string", required: true, description: "Task description to discover relevant skills" },
              mode: { type: "string", required: false, description: "Traversal mode: auto/manifest (default: auto)" },
              token_budget: { type: "integer", required: false, description: "Max token budget (default 2000)" }
            }
          },
          "get_skill_context" => {
            description: "Get enriched context for an input text using skill graph",
            parameters: {
              input_text: { type: "string", required: true, description: "Input text for context enrichment" },
              agent_id: { type: "string", required: false, description: "Agent ID for manifest mode" },
              mode: { type: "string", required: false, description: "Traversal mode: auto/manifest (default: auto)" },
              token_budget: { type: "integer", required: false, description: "Max token budget (default 2000)" }
            }
          },
          "skill_health" => {
            description: "Get a comprehensive health report for the skill graph",
            parameters: {}
          },
          "skill_metrics" => {
            description: "Get skill graph health score and metrics",
            parameters: {}
          },
          "create_skill" => {
            description: "Create a new AI skill",
            parameters: {
              name: { type: "string", required: true, description: "Skill name" },
              description: { type: "string", required: false, description: "Skill description" },
              category: { type: "string", required: false, description: "Skill category" },
              system_prompt: { type: "string", required: false, description: "System prompt template" },
              commands: { type: "array", required: false, description: "Slash commands array" },
              tags: { type: "array", required: false, description: "Tags array" }
            }
          },
          "update_skill" => {
            description: "Update an existing AI skill's configuration",
            parameters: {
              skill_id: { type: "string", required: true, description: "Skill ID" },
              name: { type: "string", required: false, description: "New skill name" },
              description: { type: "string", required: false, description: "New skill description" },
              category: { type: "string", required: false, description: "Skill category" },
              system_prompt: { type: "string", required: false, description: "System prompt template" },
              commands: { type: "array", required: false, description: "Slash commands array" },
              tags: { type: "array", required: false, description: "Tags array" }
            }
          },
          "delete_skill" => {
            description: "Delete an AI skill permanently",
            parameters: {
              skill_id: { type: "string", required: true, description: "Skill ID to delete" }
            }
          },
          "toggle_skill" => {
            description: "Enable or disable an AI skill",
            parameters: {
              skill_id: { type: "string", required: true, description: "Skill ID" },
              enabled: { type: "boolean", required: true, description: "Set to true or false" }
            }
          },
          "attach_skill_to_agent" => {
            description: "Bind a skill to an agent — adds an Ai::AgentSkill row that lets the agent invoke the skill. Idempotent: re-attach updates priority/is_active.",
            parameters: {
              skill_id: { type: "string", required: true, description: "Skill UUID or slug" },
              agent_id: { type: "string", required: true, description: "Agent UUID, slug, or name" },
              priority: { type: "integer", required: false, description: "Priority order (default 0)" },
              is_active: { type: "boolean", required: false, description: "Active flag (default true)" }
            }
          },
          "detach_skill_from_agent" => {
            description: "Unbind a skill from an agent — destroys the Ai::AgentSkill row.",
            parameters: {
              skill_id: { type: "string", required: true, description: "Skill UUID or slug" },
              agent_id: { type: "string", required: true, description: "Agent UUID, slug, or name" }
            }
          }
        }
      end

      protected

      def call(params)
        case params[:action]
        when "list_skills" then list_skills(params)
        when "get_skill" then get_skill(params)
        when "discover_skills" then discover_skills(params)
        when "get_skill_context" then get_skill_context(params)
        when "skill_health" then skill_health
        when "skill_metrics" then skill_metrics
        when "create_skill" then create_skill(params)
        when "update_skill" then update_skill(params)
        when "delete_skill" then delete_skill(params)
        when "toggle_skill" then toggle_skill(params)
        when "attach_skill_to_agent" then attach_skill_to_agent(params)
        when "detach_skill_from_agent" then detach_skill_from_agent(params)
        else { success: false, error: "Unknown action: #{params[:action]}" }
        end
      end

      private

      def resolve_skill(skill_id)
        Ai::Skill.where(account_id: account.id).find_by(id: skill_id) ||
          Ai::Skill.where(account_id: account.id).find_by(slug: skill_id)
      end

      def resolve_agent_by_any(agent_id)
        ::Ai::Agent.for_account(account.id).find_by(id: agent_id) ||
          account.ai_agents.find_by(slug: agent_id) ||
          account.ai_agents.find_by(name: agent_id)
      end

      def attach_skill_to_agent(params)
        skill = resolve_skill(params[:skill_id])
        return { success: false, error: "Skill not found" } unless skill
        agent_rec = resolve_agent_by_any(params[:agent_id])
        return { success: false, error: "Agent not found" } unless agent_rec

        binding = Ai::AgentSkill.find_or_initialize_by(ai_agent_id: agent_rec.id, ai_skill_id: skill.id)
        binding.priority = params[:priority] if params.key?(:priority)
        binding.is_active = params.key?(:is_active) ? !!params[:is_active] : true
        binding.save!
        { success: true, attached: true, skill_id: skill.id, agent_id: agent_rec.id,
          priority: binding.priority, is_active: binding.is_active }
      rescue ActiveRecord::RecordInvalid => e
        { success: false, error: e.message }
      end

      def detach_skill_from_agent(params)
        skill = resolve_skill(params[:skill_id])
        return { success: false, error: "Skill not found" } unless skill
        agent_rec = resolve_agent_by_any(params[:agent_id])
        return { success: false, error: "Agent not found" } unless agent_rec

        binding = Ai::AgentSkill.find_by(ai_agent_id: agent_rec.id, ai_skill_id: skill.id)
        return { success: false, error: "Skill #{skill.name} is not attached to agent #{agent_rec.name}" } unless binding

        binding.destroy!
        { success: true, detached: true, skill_id: skill.id, agent_id: agent_rec.id }
      end

      private

      def list_skills(params)
        filters = {}
        filters[:category] = params[:category] if params[:category].present?
        filters[:status] = params[:status] if params[:status].present?
        filters[:enabled] = params[:enabled] if params[:enabled].present?
        filters[:search] = params[:search] if params[:search].present?

        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 20).to_i.clamp(1, 50)

        skills = skill_service.list_skills(filters: filters, page: page, per_page: per_page)

        {
          success: true,
          count: skills.total_count,
          page: page,
          per_page: per_page,
          total_pages: skills.total_pages,
          skills: skills.map(&:skill_summary)
        }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def get_skill(params)
        return { success: false, error: "skill_id is required" } if params[:skill_id].blank?

        skill = skill_service.find_skill(skill_id: params[:skill_id])
        { success: true, skill: skill.skill_details }
      rescue Ai::SkillService::NotFoundError => e
        { success: false, error: e.message }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def discover_skills(params)
        return { success: false, error: "task_context is required" } if params[:task_context].blank?

        result = traversal_service.traverse(
          task_context: params[:task_context],
          mode: (params[:mode] || "auto").to_sym,
          token_budget: (params[:token_budget] || 2000).to_i
        )

        { success: true, **result }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def get_skill_context(params)
        return { success: false, error: "input_text is required" } if params[:input_text].blank?

        agent = params[:agent_id].present? ? ::Ai::Agent.for_account(account.id).find_by(id: params[:agent_id]) : nil

        result = context_enrichment_service.enrich(
          agent: agent,
          input_text: params[:input_text],
          mode: (params[:mode] || "auto").to_sym,
          token_budget: (params[:token_budget] || 2000).to_i
        )

        { success: true, **result }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def skill_health
        report = health_score_service.comprehensive_report
        { success: true, **report }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def skill_metrics
        metrics = health_score_service.calculate
        { success: true, **metrics }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def create_skill(params)
        return { success: false, error: "name is required" } if params[:name].blank?

        attributes = { name: params[:name] }
        attributes[:description] = params[:description] if params[:description].present?
        attributes[:category] = params[:category] if params[:category].present?
        attributes[:system_prompt] = params[:system_prompt] if params[:system_prompt].present?
        attributes[:commands] = Array(params[:commands]) if params[:commands].present?
        attributes[:tags] = Array(params[:tags]) if params[:tags].present?

        skill = skill_service.create_skill(attributes: attributes)
        { success: true, skill: skill.skill_details }
      rescue Ai::SkillService::ValidationError => e
        { success: false, error: e.message }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def update_skill(params)
        return { success: false, error: "skill_id is required" } if params[:skill_id].blank?

        attributes = {}
        attributes[:name] = params[:name] if params[:name].present?
        attributes[:description] = params[:description] if params[:description].present?
        attributes[:category] = params[:category] if params[:category].present?
        attributes[:system_prompt] = params[:system_prompt] if params[:system_prompt].present?
        attributes[:commands] = Array(params[:commands]) if params.key?(:commands)
        attributes[:tags] = Array(params[:tags]) if params.key?(:tags)

        skill = skill_service.update_skill(skill_id: params[:skill_id], attributes: attributes)
        { success: true, skill: skill.skill_details }
      rescue Ai::SkillService::NotFoundError, Ai::SkillService::ValidationError => e
        { success: false, error: e.message }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def delete_skill(params)
        return { success: false, error: "skill_id is required" } if params[:skill_id].blank?

        skill_service.delete_skill(skill_id: params[:skill_id])
        { success: true, message: "Skill deleted successfully" }
      rescue Ai::SkillService::NotFoundError, Ai::SkillService::ValidationError => e
        { success: false, error: e.message }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def toggle_skill(params)
        return { success: false, error: "skill_id is required" } if params[:skill_id].blank?

        enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
        skill = skill_service.toggle_skill(skill_id: params[:skill_id], enabled: enabled)
        { success: true, skill_id: skill.id, enabled: skill.is_enabled }
      rescue Ai::SkillService::NotFoundError => e
        { success: false, error: e.message }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      def skill_service
        @skill_service ||= Ai::SkillService.new(account: account)
      end

      def traversal_service
        @traversal_service ||= Ai::SkillGraph::TraversalService.new(account)
      end

      def context_enrichment_service
        @context_enrichment_service ||= Ai::SkillGraph::ContextEnrichmentService.new(account)
      end

      def health_score_service
        @health_score_service ||= Ai::SkillGraph::HealthScoreService.new(account)
      end
    end
  end
end
