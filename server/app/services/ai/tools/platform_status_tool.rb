# frozen_string_literal: true

module Ai
  module Tools
    # THE AGENT'S VIEW OF THE COMPONENT STATUS PLANE (campaign 01a08c9b, A4).
    #
    # Three reads over Platform::ComponentStatus, answering the same questions
    # the operator screen asks — what is unhealthy, what is the evidence, and
    # who breaks next — through Platform::Status::Query and
    # Platform::Status::Rollup, the same code the REST door uses. A tool that
    # re-implemented the filter would eventually disagree with the page about
    # whether something is down, and the agent would be the one that is wrong
    # in the incident review.
    #
    # ── READ-ONLY, AND DECLARED SO ──────────────────────────────────────────
    #
    # All three actions are `declare_action ..., mutating: false`. Nothing here
    # writes: the sweep is the one producer (design §4.3) and reaches the rows
    # through the mTLS worker route. Actuation lives behind
    # Platform::RemediationRouter (A5) and behind each row's own `actions`
    # entries, every one of which names its own permission.
    #
    # The impact verb is `get_component_impact`, not `component_impact`, and
    # the `get_` is load-bearing rather than stylistic: Mcp::ToolCatalog
    # derives the wire `readOnlyHint` from the action name's FIRST underscore
    # segment (READ_ONLY_ACTION_PREFIXES), so a name outside that vocabulary
    # ships a read verb with NO read-only hint however it is declared. Design
    # §8 E2 moves annotations onto `declared_actions`; until then the name is
    # the only thing the annotation reads, so the name has to be right.
    #
    # ── WIRE NAME: `not_measured`, NEVER `unknown` ──────────────────────────
    #
    # The absent-measurement verdict travels under one name end to end (design
    # §4.1). An agent that saw `unknown` would have to guess whether the
    # platform failed to look or looked and could not tell.
    class PlatformStatusTool < BaseTool
      REQUIRED_PERMISSION = "platform.status.read"

      # Every action floors on the same read permission — there is no write in
      # this tool to ladder up to. Stated explicitly rather than left implicit
      # so a future write action cannot inherit the read floor silently (the
      # IMP-48abfa2f9e74 failure shape).
      ACTION_PERMISSIONS = {
        "list_component_status" => "platform.status.read",
        "get_component_status" => "platform.status.read",
        "get_component_impact" => "platform.status.read"
      }.freeze

      declare_action "list_component_status", mutating: false
      declare_action "get_component_status", mutating: false
      declare_action "get_component_impact", mutating: false

      VERDICT_DESCRIPTION = "One of ok | held | progressing | not_measured | degraded | down. " \
                            "`held` is operator intent (cordoned, paused, drained), not a failure. " \
                            "`not_measured` is an ABSENT measurement — the platform did not get a " \
                            "reading — and is never collapsed into ok."

      ENVIRONMENT_DESCRIPTION = "Environment slug or Ai::Environment id. THREE-VALUED: omit for every " \
                               "component; pass `none` for the components that belong to no plane " \
                               "(most core kinds and the platform's own subsystems); pass a plane to " \
                               "get that plane's components PLUS the plane-less ones, each row " \
                               "labelled `plane: \"in\" | \"none\"`. Another plane's rows are never " \
                               "included. A plane this account does not have is refused, not ignored."

      def self.definition
        {
          name: "platform_status",
          description: "Read the component status plane: one row per component of the platform and " \
                       "fleet, with its verdict, the typed conditions the verdict was derived from, " \
                       "its dependency edges and its remediation state.",
          parameters: { type: "object", properties: {} }
        }
      end

      def self.action_definitions
        {
          "list_component_status" => {
            description: "List component statuses for this account plus the shared (process-wide) " \
                         "components, worst verdict first. Filter by kind, verdict and environment. " \
                         "Rows are compact — call get_component_status for one component's conditions, " \
                         "dependencies, links and actions. Read-only.",
            parameters: {
              kind: { type: "string", required: false,
                      description: "component_kind filter (ai_provider, docker_host, node_instance, platform_subsystem, ...)" },
              verdict: { type: "string", required: false, enum: ::Platform::ComponentStatus::VERDICTS,
                         description: VERDICT_DESCRIPTION },
              unhealthy_only: { type: "boolean", required: false,
                                description: "Only components a person should look at: not_measured, degraded or down. " \
                                             "Ignored when `verdict` is given." },
              environment: { type: "string", required: false, description: ENVIRONMENT_DESCRIPTION },
              **PAGINATION_PARAMETERS
            }
          },
          "get_component_status" => {
            description: "One component in full: verdict, the typed conditions with their reason tokens " \
                         "and evidence, dependency edges, remediation state, links, the actions the " \
                         "operator page offers (each naming its OWN permission — this tool grants none " \
                         "of them) and an impact summary. Read-only.",
            parameters: {
              id: { type: "string", required: false, description: "Platform::ComponentStatus id" },
              component_kind: { type: "string", required: false, description: "With component_ref, an alternative to id" },
              component_ref: { type: "string", required: false, description: "With component_kind, an alternative to id" }
            }
          },
          "get_component_impact" => {
            description: "Who breaks if this component stays broken, and what most likely broke it. " \
                         "Returns the dependents reached over the dependency graph with their worst " \
                         "verdict, plus ranked root-cause candidates. The ranking is a HEURISTIC over " \
                         "correlation — `heuristic: true` is in the payload and must be repeated to a " \
                         "person; it is not proof of causation. Read-only.",
            parameters: {
              id: { type: "string", required: false, description: "Platform::ComponentStatus id" },
              component_kind: { type: "string", required: false, description: "With component_ref, an alternative to id" },
              component_ref: { type: "string", required: false, description: "With component_kind, an alternative to id" },
              depth: { type: "integer", required: false,
                       description: "How many dependency hops to walk (default 4, max 4). Cycle-safe." }
            }
          }
        }
      end

      def call(params)
        action = params[:action].to_s
        return error_result("permission denied: #{required_perm_for(action)} required") unless action_permitted?(action)

        case action
        when "list_component_status" then list_component_status(params)
        when "get_component_status"  then get_component_status(params)
        when "get_component_impact" then get_component_impact(params)
        else error_result("Unknown action: #{action}")
        end
      end

      private

      def required_perm_for(action)
        ACTION_PERMISSIONS[action] || REQUIRED_PERMISSION
      end

      def action_permitted?(action)
        return true if internal?
        return true if instance_authorized?
        return false unless user.respond_to?(:has_permission?)

        user.has_permission?(required_perm_for(action)) == true
      end

      def list_component_status(params)
        query = build_query(params)
        return error_result("Unknown verdict '#{query.verdict}'") unless query.known_verdict?
        return environment_refusal(query) if query.unknown_environment?

        relation = query.rows
        relation = relation.unhealthy if unhealthy_only?(params) && !query.verdict?

        paginated_result(
          :component_statuses,
          # paginate_list imposes its own keyset order; handing it an ordered
          # relation would put the cursor's predicate and the ORDER BY out of
          # agreement. The severity order lives in the REST list, which pages
          # by offset; here `unhealthy_only` is how a caller gets the outages.
          relation.reorder(nil),
          params,
          sort: :id,
          direction: :asc,
          filters: query.applied_filters
        ) { |row| ::Platform::ComponentStatusSerializer.summary(row) }
      end

      def get_component_status(params)
        row = find_component(params)
        return not_found_result(params) unless row

        neighbourhood = neighbourhood_rows(row)
        success_result(
          component_status: ::Platform::ComponentStatusSerializer.detail(row),
          impact: serialize_impact(::Platform::Status::Rollup.impact(row, rows: neighbourhood))
        )
      end

      def get_component_impact(params)
        row = find_component(params)
        return not_found_result(params) unless row

        neighbourhood = neighbourhood_rows(row)
        depth = resolve_depth(params[:depth])
        candidates = ::Platform::Status::Rollup.root_cause_candidates(row, rows: neighbourhood, depth: depth)

        success_result(
          component_status: ::Platform::ComponentStatusSerializer.summary(row),
          impact: serialize_impact(::Platform::Status::Rollup.impact(row, rows: neighbourhood, depth: depth)),
          root_cause_candidates: ::Platform::ComponentStatusSerializer.summary_collection(candidates),
          heuristic: true,
          heuristic_basis: "upstream-most unhealthy components, ranked by unhealthy-dependent count then earliest transition",
          depth: depth
        )
      end

      # ── helpers ───────────────────────────────────────────────────────────

      def build_query(params)
        ::Platform::Status::Query.new(
          account: account,
          kind: params[:kind],
          verdict: params[:verdict],
          environment: params[:environment]
        )
      end

      def unhealthy_only?(params)
        value = params[:unhealthy_only]
        value == true || value.to_s == "true"
      end

      def environment_refusal(query)
        error_result("environment '#{query.environment_param}' not found in this account")
      end

      # Scoped to this account plus the shared rows, exactly like the REST
      # door. Another tenant's component reads as absent.
      def scope
        ::Platform::ComponentStatus.where(account_id: [ account.id, nil ])
      end

      def find_component(params)
        return scope.find_by(id: params[:id].to_s) if params[:id].present?

        kind = params[:component_kind].to_s
        ref = params[:component_ref].to_s
        return nil if kind.empty? || ref.empty?

        scope.find_by(component_kind: kind, component_ref: ref)
      end

      def not_found_result(params)
        if params[:id].blank? && (params[:component_kind].blank? || params[:component_ref].blank?)
          return error_result("give either `id`, or both `component_kind` and `component_ref`")
        end

        error_result("component status not found in this account")
      end

      def neighbourhood_rows(row)
        ::Platform::ComponentStatus.where(account_id: [ row.account_id, nil ].uniq).to_a
      end

      def resolve_depth(raw)
        return ::Platform::Status::Rollup::DEFAULT_DEPTH if raw.blank?

        value = raw.to_i
        return ::Platform::Status::Rollup::DEFAULT_DEPTH unless value.positive?

        [ value, ::Platform::Status::Rollup::DEFAULT_DEPTH ].min
      end

      def serialize_impact(result)
        {
          count: result[:count],
          worst_verdict: result[:worst_verdict],
          components: ::Platform::ComponentStatusSerializer.summary_collection(result[:components])
        }
      end
    end
  end
end
