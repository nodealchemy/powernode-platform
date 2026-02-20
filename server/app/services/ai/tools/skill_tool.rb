# frozen_string_literal: true

module Ai
  module Tools
    class SkillTool < BaseTool
      REQUIRED_PERMISSION = "ai.skills.read"

      def self.definition
        {
          name: "skill_management",
          description: "Manage and discover AI skills: list, get details, discover relevant skills for a task, get enriched context, and check skill graph health",
          parameters: {
            action: { type: "string", required: true, description: "Action: list_skills, get_skill, discover_skills, get_skill_context, skill_health, skill_metrics" },
            skill_id: { type: "string", required: false, description: "Skill ID (for get_skill)" },
            status: { type: "string", required: false, description: "Filter by status: active/inactive/draft (for list_skills)" },
            category: { type: "string", required: false, description: "Filter by category (for list_skills)" },
            search: { type: "string", required: false, description: "Search query for skill name/description (for list_skills)" },
            enabled: { type: "string", required: false, description: "Filter by enabled: true/false (for list_skills)" },
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

      protected

      def call(params)
        case params[:action]
        when "list_skills" then list_skills(params)
        when "get_skill" then get_skill(params)
        when "discover_skills" then discover_skills(params)
        when "get_skill_context" then get_skill_context(params)
        when "skill_health" then skill_health
        when "skill_metrics" then skill_metrics
        else { success: false, error: "Unknown action: #{params[:action]}. Valid actions: list_skills, get_skill, discover_skills, get_skill_context, skill_health, skill_metrics" }
        end
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

        agent = params[:agent_id].present? ? account.ai_agents.find_by(id: params[:agent_id]) : nil

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
