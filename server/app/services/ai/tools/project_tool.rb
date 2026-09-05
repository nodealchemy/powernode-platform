# frozen_string_literal: true

module Ai
  module Tools
    # APO increment `app-4-project-noun` — the MCP read surface for Ai::Project.
    #
    #   platform.project_list    — this account's projects
    #   platform.project_get     — one project, by id OR slug
    #   platform.project_status  — a project plus the rollup of the missions it
    #                              owns and the scaling window they run under
    #
    # ALL THREE ARE READS. Nothing here writes: creation happens on the
    # provisioning path (Ai::Tools::ProvisioningTool#capture_brief attaches the
    # project to the mission it creates), so a write verb on this surface would
    # be a second door onto the same row with no plan behind it.
    #
    # PERMISSION. `ai.missions.read`, an EXISTING permission that the `member`
    # role already grants. No new permission was minted: an undefined permission
    # degrades to admin-only (recall `undefined-permissions-reachable-only-by-
    # admin`), and one that nothing grants and nothing checks is a filed defect
    # class here rather than a control. `ai.missions.read` is the right floor
    # because a project is the container its missions are read through — the
    # same operator who may read a mission may read the project that owns it,
    # and every field these verbs return is derived from missions or from the
    # project's own declarations.
    #
    # ACCOUNT SCOPING is not left to the caller. Every lookup goes through
    # `Ai::Project.find_for_account`, which takes the account in the same query
    # as the identifier — a slug is a guessable handle, and a cross-tenant read
    # is a repeatedly-filed defect class in this codebase.
    class ProjectTool < BaseTool
      REQUIRED_PERMISSION = "ai.missions.read"

      ACTIONS = %w[project_list project_get project_status].freeze

      # Read-shaped, so `mutating: false` and no gate wiring: BaseTool#execute
      # routes straight to #call, where #authorization_error runs first.
      declare_action "project_list", mutating: false
      declare_action "project_get", mutating: false
      declare_action "project_status", mutating: false

      def self.definition
        {
          name: "project",
          description: "Read the platform's PROJECT noun: the durable owner of a fleet of missions, " \
                       "its repository, template, owning team, budget/bounds and SLO targets. " \
                       "Projects outlive the missions done for them.",
          parameters: {
            action: { type: "string", required: true,
                      description: "project_list | project_get | project_status" },
            project_id: { type: "string", required: false,
                          description: "Project UUID or slug (project_get, project_status)" },
            status: { type: "string", required: false,
                      description: "Filter by status: active | paused | archived (project_list)" },
            limit: { type: "integer", required: false,
                     description: "Max rows (project_list, default 100)" }
          }
        }
      end

      def self.action_definitions
        {
          "project_list" => {
            description: "List this account's projects, newest first. Returns each project's id, slug, " \
                         "status, repository, owning team and template reference.",
            parameters: {
              status: { type: "string", required: false,
                        description: "Filter by status: active | paused | archived" },
              limit: { type: "integer", required: false, description: "Max rows (default 100)" }
            }
          },
          "project_get" => {
            description: "Get one project by UUID or slug, including its declared watch_policies " \
                         "(scaling window) and slo_targets (availability, latency, cost ceiling, " \
                         "utilization ceilings).",
            parameters: {
              project_id: { type: "string", required: true, description: "Project UUID or slug" }
            }
          },
          "project_status" => {
            description: "Operational rollup for one project: the missions it owns grouped by status, " \
                         "the ones still in flight, and the scaling window those missions resolve — " \
                         "which may come from the project's own declaration or from a rung above it.",
            parameters: {
              project_id: { type: "string", required: true, description: "Project UUID or slug" }
            }
          }
        }
      end

      protected

      # Enforced HERE as well as by the MCP registrar. These actions are
      # ungated (`mutating: false`), so BaseTool#execute takes `return
      # call(params)` and never reaches its own #authorization_error hoist —
      # and many in-process callers construct a tool and call #execute without
      # passing through the registrar at all. A check that only exists on the
      # registrar path is a check the other callers do not have.
      def call(params)
        refusal = authorization_error(params)
        return refusal if refusal

        case params[:action]
        when "project_list"   then project_list(params)
        when "project_get"    then project_get(params)
        when "project_status" then project_status(params)
        else error_result("Unknown action: #{params[:action]}")
        end
      end

      def authorization_error(_params)
        return nil if internal?
        return nil if instance_authorized?
        return nil if user.respond_to?(:has_permission?) &&
                      user.has_permission?(REQUIRED_PERMISSION) == true

        Rails.logger.warn(
          "[ProjectTool] permission denied: requires=#{REQUIRED_PERMISSION} user=#{user&.id}"
        )
        error_result("permission denied: #{REQUIRED_PERMISSION} required")
      end

      private

      def project_list(params)
        scope = account.ai_projects
        status = params[:status].presence
        if status
          return error_result("Unknown status '#{status}' — expected one of #{::Ai::Project::STATUSES.join(', ')}") unless ::Ai::Project::STATUSES.include?(status)

          scope = scope.where(status: status)
        end

        limit = normalized_limit(params[:limit])
        projects = scope.recent.limit(limit).to_a

        success_result(
          projects: projects.map(&:project_summary),
          count: projects.size
        )
      end

      def project_get(params)
        project = resolve_project(params)
        return project if project.is_a?(Hash)

        success_result(project: project.project_details)
      end

      def project_status(params)
        project = resolve_project(params)
        return project if project.is_a?(Hash)

        rollup = project.status_rollup
        success_result(
          project: project.project_details,
          mission_count: rollup[:mission_count],
          missions_by_status: rollup[:missions_by_status],
          in_progress_mission_ids: rollup[:in_progress_mission_ids],
          missions: mission_rows(project),
          scaling_bounds: resolved_scaling_bounds(project)
        )
      end

      # Returns the project, or an error_result Hash the caller passes straight
      # back. Never raises RecordNotFound: an agent reading a stale id must get
      # a refusal it can act on, not a -32603.
      def resolve_project(params)
        identifier = params[:project_id].presence
        return error_result("project_id is required (a project UUID or slug)") unless identifier

        project = ::Ai::Project.find_for_account(account.id, identifier)
        return error_result("Project not found: #{identifier}") unless project

        project
      end

      # `.includes` because each row reads the mission's template through the
      # bounds ladder and its repository name.
      def mission_rows(project)
        project.missions
               .includes(:mission_template, :repository)
               .order(created_at: :desc)
               .map do |mission|
          {
            id: mission.id,
            name: mission.name,
            mission_type: mission.mission_type,
            status: mission.status,
            current_phase: mission.current_phase,
            repository: mission.repository&.full_name
          }
        end
      end

      # The window the project's missions actually resolve — which is NOT
      # necessarily what the project declared. The project is one rung of
      # `Ai::Mission`'s ladder, so a mission may narrow it and a template or
      # SiteSetting may supply a half the project left open. Reading it off a
      # real mission is therefore the honest answer; a project with no missions
      # yet has nothing to resolve and reports its own declaration instead.
      def resolved_scaling_bounds(project)
        mission = project.missions.order(:created_at).first
        return declared_bounds(project) unless mission

        bounds = mission.scaling_bounds
        { min: bounds.min, max: bounds.max, auto_scale_out: bounds.auto_scale_out? }
      end

      def declared_bounds(project)
        policies = project.watch_policies_hash
        {
          declared_only: true,
          min: policies[::Ai::Mission::MIN_REPLICAS_POLICY_KEY],
          max: policies[::Ai::Mission::MAX_REPLICAS_POLICY_KEY]
        }
      end

      def normalized_limit(raw)
        value = raw.to_i
        return self.class.default_list_limit unless value.positive?

        [ value, self.class.max_list_limit ].min
      end
    end
  end
end
