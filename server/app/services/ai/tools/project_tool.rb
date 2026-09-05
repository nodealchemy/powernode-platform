# frozen_string_literal: true

module Ai
  module Tools
    # APO increment `app-4-project-noun` — the MCP read surface for Ai::Project.
    #
    #   platform.project_list             — this account's projects
    #   platform.project_get              — one project, by id OR slug
    #   platform.project_status           — a project plus the rollup of the
    #                                       missions it owns and the scaling
    #                                       window they run under
    #   platform.project_set_slo_targets  — declare the project's SLO targets
    #
    # THE READ-ONLY CLAIM THAT USED TO STAND HERE HAS EXPIRED, and it is worth
    # recording why rather than quietly deleting it. It said a write verb would
    # be "a second door onto the same row with no plan behind it", which was
    # true while CREATION was the only write: creation happens on the
    # provisioning path, and a second create door would have raced it.
    #
    # Declaring a target is not creation, and it had NO door at all. The
    # creation path passes account, name, status and creator and nothing else,
    # so every project in existence carried empty targets and a declaration
    # could not arrive by any route — including for the two utilization
    # ceilings that were already correctly wired into the bounds ladder. A
    # ladder rung nothing can populate is a rung nothing reaches.
    #
    # Creation stays where it is. This verb only declares targets on a project
    # that already exists.
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

      ACTIONS = %w[project_list project_get project_status project_set_slo_targets].freeze

      # The WRITE verb takes the manage permission, not the read floor: the
      # three reads stay at `ai.missions.read` and declaring a target is the
      # same class of operation as managing the mission it governs.
      WRITE_PERMISSION = "ai.missions.manage"
      ACTION_PERMISSIONS = { "project_set_slo_targets" => WRITE_PERMISSION }.freeze

      # The targets a project may declare. Keyed by the CANONICAL metric name a
      # sample carries, valued by the coercion rule — availability is a
      # percentage, a cost ceiling in dollars and a throughput floor in bytes
      # per second are unbounded above, and running them through one rule would
      # discard every realistic cost declaration.
      DECLARABLE_TARGETS = {
        ::Ai::Mission::AVAILABILITY_PCT_SLO_KEY => :percentage,
        ::Ai::Mission::COST_CEILING_USD_SLO_KEY => :positive_number,
        ::Ai::Mission::MIN_THROUGHPUT_SLO_KEY   => :positive_number,
        ::Ai::Mission::MAX_CPU_PCT_SLO_KEY      => :percentage,
        ::Ai::Mission::MAX_MEMORY_PCT_SLO_KEY   => :percentage
      }.freeze

      # Read-shaped, so `mutating: false` and no gate wiring: BaseTool#execute
      # routes straight to #call, where #authorization_error runs first.
      declare_action "project_list", mutating: false
      declare_action "project_get", mutating: false
      declare_action "project_status", mutating: false
      declare_action "project_set_slo_targets", mutating: true

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
          "project_set_slo_targets" => {
            description: "Declare a project's service-level targets. They resolve through the mission " \
                         "bounds ladder, so a target declared here governs every mission the project " \
                         "owns unless that mission declares its own. Merges: naming one target leaves " \
                         "the others alone, and an explicit null clears one. p99_latency_ms is REFUSED " \
                         "— nothing on this platform measures workload latency, so accepting one would " \
                         "store a target that is compared against nothing.",
            parameters: {
              project_id: { type: "string", required: true, description: "Project UUID or slug" },
              availability_pct: { type: "number", required: false,
                                  description: "Availability target, a percentage in (0, 100]" },
              cost_ceiling_usd: { type: "number", required: false,
                                  description: "Monthly cost ceiling in USD. Above this the project is cost-breaching" },
              min_throughput_bytes_per_s: { type: "number", required: false,
                                            description: "Throughput floor in bytes per second. Declared-only: no default floor exists" },
              max_cpu_pct: { type: "number", required: false,
                             description: "CPU ceiling, a percentage in (0, 100]. Above this the project is utilization-bound" },
              max_memory_pct: { type: "number", required: false,
                                description: "Memory ceiling, a percentage in (0, 100]" }
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
        when "project_list"            then project_list(params)
        when "project_get"             then project_get(params)
        when "project_status"          then project_status(params)
        when "project_set_slo_targets" then project_set_slo_targets(params)
        else error_result("Unknown action: #{params[:action]}")
        end
      end

      # Per ACTION, not per tool: the write verb must not be reachable on the
      # read floor. A name-keyed check on the tool alone would let a caller
      # holding only `ai.missions.read` smuggle the write action in through the
      # `action` parameter, which is how a sibling tool became an authorization
      # bypass (IMP-6fbfeff384fa).
      def authorization_error(params)
        return nil if internal?
        return nil if instance_authorized?

        required = ACTION_PERMISSIONS.fetch(params[:action].to_s, REQUIRED_PERMISSION)
        return nil if user.respond_to?(:has_permission?) && user.has_permission?(required) == true

        Rails.logger.warn(
          "[ProjectTool] permission denied: action=#{params[:action]} requires=#{required} user=#{user&.id}"
        )
        error_result("permission denied: #{required} required")
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

      # Declare targets on the project. MERGE, not replace: a caller naming one
      # target must not silently clear the others, and an explicit null is how
      # a target is cleared on purpose.
      #
      # AN UNUSABLE VALUE IS REFUSED, never stored. Stored, it would resolve to
      # NOT DECLARED through the ladder while reading back as accepted — the
      # write would look like it worked and the target would be observed by
      # nothing.
      def project_set_slo_targets(params)
        project = resolve_project(params)
        return project if project.is_a?(Hash)

        refusal = refuse_undeclarable(params)
        return refusal if refusal

        named = DECLARABLE_TARGETS.keys.select { |key| params.key?(key.to_sym) || params.key?(key) }
        if named.empty?
          return error_result(
            "name at least one target to declare: #{DECLARABLE_TARGETS.keys.join(', ')}"
          )
        end

        updates = {}
        named.each do |key|
          raw = params.key?(key.to_sym) ? params[key.to_sym] : params[key]
          if raw.nil?
            updates[key] = nil
            next
          end

          value = coerce_target(raw, DECLARABLE_TARGETS.fetch(key))
          unless value
            return error_result(
              "#{key}=#{raw.inspect} is not a usable #{DECLARABLE_TARGETS.fetch(key)} — refused " \
              "rather than stored, because a stored value that resolves to nothing reads back as accepted"
            )
          end

          updates[key] = value
        end

        persist_slo_targets!(project, updates)

        success_result(
          project_id: project.id,
          slo_targets: project.reload.slo_targets_hash,
          undeclarable: ::Ai::Mission::UNDECLARABLE_TARGETS.keys
        )
      end

      # The undeclarable targets are refused BY NAME at the write door, which is
      # where "undeclarable by design" stops being a comment and becomes a
      # control. See Ai::Mission::UNDECLARABLE_TARGETS for the reason.
      def refuse_undeclarable(params)
        named = ::Ai::Mission::UNDECLARABLE_TARGETS.keys.select do |key|
          params.key?(key.to_sym) || params.key?(key)
        end
        return nil if named.empty?

        reasons = named.map { |key| "#{key}: #{::Ai::Mission::UNDECLARABLE_TARGETS[key]}" }
        error_result("refused, these targets are undeclarable by design — #{reasons.join(' ')}")
      end

      def coerce_target(raw, rule)
        value = raw.is_a?(Numeric) ? raw.to_f : Float(raw.to_s.strip, exception: false)
        return nil unless value&.positive?
        return nil if rule == :percentage && value > 100.0

        value
      end

      # Merges into `configuration["slo_targets"]`, leaving every other section
      # (the watch_policies the scaling window reads, operator annotations) as
      # it was. A nil clears its key rather than storing a null the ladder would
      # then have to interpret.
      def persist_slo_targets!(project, updates)
        config = project.configuration.is_a?(Hash) ? project.configuration.deep_dup : {}
        targets = config[::Ai::Project::SLO_TARGETS_KEY]
        targets = targets.is_a?(Hash) ? targets.deep_stringify_keys : {}

        updates.each { |key, value| value.nil? ? targets.delete(key) : targets[key] = value }
        config[::Ai::Project::SLO_TARGETS_KEY] = targets
        project.update!(configuration: config)
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
