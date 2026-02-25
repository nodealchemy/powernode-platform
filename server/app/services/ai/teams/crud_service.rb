# frozen_string_literal: true

module Ai
  module Teams
    class CrudService
      attr_reader :account

      def initialize(account:)
        @account = account
      end

      # ============================================================================
      # TEAM MANAGEMENT
      # ============================================================================

      def list_teams(filters = {})
        teams = account.ai_agent_teams.where.not(team_type: "workspace")
        teams = teams.where(status: filters[:status]) if filters[:status].present?
        teams = teams.where(team_topology: filters[:topology]) if filters[:topology].present?
        teams = teams.order(created_at: :desc)
        teams = teams.page(filters[:page]).per(filters[:per_page]) if filters[:page].present?
        teams
      end

      def get_team(team_id)
        account.ai_agent_teams.find(team_id)
      end

      def create_team(params, user: nil)
        account.ai_agent_teams.create!(
          name: params[:name],
          description: params[:description],
          goal_description: params[:goal_description],
          team_type: params[:team_type] || "hierarchical",
          team_topology: params[:team_topology] || "hierarchical",
          coordination_strategy: params[:coordination_strategy] || "manager_led",
          communication_pattern: params[:communication_pattern] || "hub_spoke",
          max_parallel_tasks: params[:max_parallel_tasks] || 3,
          task_timeout_seconds: params[:task_timeout_seconds] || 300,
          escalation_policy: params[:escalation_policy] || {},
          shared_memory_config: params[:shared_memory_config] || {},
          human_checkpoint_config: params[:human_checkpoint_config] || {},
          team_config: params[:team_config] || {},
          status: "active"
        )
      end

      def create_team_from_template(template_id, name: nil, user: nil)
        template = Ai::TeamTemplate.find(template_id)
        template.create_team!(account: account, name: name, user: user)
      end

      def update_team(team_id, params)
        team = get_team(team_id)
        team.update!(params.slice(
          :name, :description, :goal_description, :team_topology,
          :coordination_strategy, :communication_pattern, :max_parallel_tasks,
          :task_timeout_seconds, :escalation_policy, :shared_memory_config,
          :human_checkpoint_config, :team_config, :status
        ))
        team
      end

      def delete_team(team_id)
        team = get_team(team_id)
        team.destroy!
      end

      # ============================================================================
      # COMPOSITION HEALTH
      # ============================================================================

      def composition_health(team_id)
        team = get_team(team_id)
        members = team.members.includes(:agent)
        lead_count = members.where(role: "manager").or(members.where(is_lead: true)).count
        worker_count = members.where.not(role: "manager").where(is_lead: false).count
        total = members.count
        ratio = lead_count.positive? ? (worker_count.to_f / lead_count).round(1) : worker_count.to_f

        warnings = []
        recommendations = []

        if team.team_topology == "hierarchical" && lead_count.zero? && total.positive?
          warnings << "Hierarchical team has no lead/manager role"
          recommendations << "Assign a manager role to coordinate workers"
        end

        if lead_count.positive?
          if ratio > 9
            warnings << "Workers-per-lead ratio is #{ratio}:1 (unhealthy)"
            recommendations << "Add more leads or reduce workers"
          elsif ratio > 5
            warnings << "Workers-per-lead ratio is #{ratio}:1 (needs attention)"
          end
        end

        if team.team_topology == "pipeline" && total < 2
          warnings << "Pipeline teams need at least 2 members"
          recommendations << "Add more members for meaningful pipeline execution"
        end

        unless members.where(role: "reviewer").exists?
          recommendations << "Consider adding a reviewer role for quality assurance"
        end

        status = if warnings.empty?
                   "healthy"
        elsif warnings.any? { |w| w.include?("unhealthy") }
                   "unhealthy"
        else
                   "warning"
        end

        {
          status: status,
          member_count: total,
          lead_count: lead_count,
          worker_count: worker_count,
          workers_per_lead: ratio,
          warnings: warnings,
          recommendations: recommendations
        }
      end

      # ============================================================================
      # ROLE PROFILES
      # ============================================================================

      def list_role_profiles(filters = {})
        profiles = Ai::RoleProfile.for_account(account.id)
        profiles = profiles.by_role_type(filters[:role_type]) if filters[:role_type].present?
        profiles = profiles.system_profiles if filters[:is_system]
        profiles.order(:name)
      end

      def get_role_profile(profile_id)
        Ai::RoleProfile.for_account(account.id).find(profile_id)
      end

      def apply_role_profile(team_id, role_id, profile_id)
        team = get_team(team_id)
        role = team.ai_team_roles.find(role_id)
        profile = Ai::RoleProfile.for_account(account.id).find(profile_id)
        profile.apply_to_role(role)
        role
      end

      # ============================================================================
      # TRAJECTORIES (delegates to TrajectoryService)
      # ============================================================================

      def list_trajectories(filters = {})
        Ai::TrajectoryService.new(account: account).list_trajectories(filters)
      end

      def get_trajectory(trajectory_id)
        Ai::TrajectoryService.new(account: account).get_trajectory(trajectory_id)
      end

      def search_trajectories(query, filters = {})
        Ai::TrajectoryService.new(account: account).search_relevant(
          query: query,
          agent_id: filters[:agent_id],
          tags: filters[:tags],
          limit: filters[:limit] || 10
        )
      end

      # ============================================================================
      # REVIEWS (delegates to ReviewWorkflowService)
      # ============================================================================

      def list_task_reviews(task_id)
        Ai::ReviewWorkflowService.new(account: account).list_reviews(task_id)
      end

      def get_task_review(review_id)
        Ai::ReviewWorkflowService.new(account: account).get_review(review_id)
      end

      def process_review(review_id, action:, notes: nil)
        review_service = Ai::ReviewWorkflowService.new(account: account)
        review = review_service.get_review(review_id)
        review_service.process_review(review, result: action, notes: notes)
      end

      def configure_team_review(team_id, config)
        team = get_team(team_id)
        team.update!(review_config: config)
        team
      end
    end
  end
end
