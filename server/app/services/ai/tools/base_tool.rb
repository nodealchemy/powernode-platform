# frozen_string_literal: true

module Ai
  module Tools
    class BaseTool
      REQUIRED_PERMISSION = nil
      MAX_CALLS_PER_EXECUTION = 20

      # The `data` body of the third outcome #execute can produce: the autonomy
      # gate returned :pending, so the action was PARKED for an operator and
      # nothing was applied. Declared here, beside the site that builds it, and
      # read by Ai::Tools::McpPlatformToolRegistrar.default_output_schema so the
      # advertised outputSchema states the shape instead of leaving an agent to
      # infer "done" vs "parked" from the prose in `message` (IMP-e809396f9eda).
      PENDING_RESULT_PROPERTIES = {
        "pending" => {
          "type" => "boolean",
          "description" => "True when the action was parked for operator approval. " \
                           "Nothing has been applied; do not retry — poll the approval request."
        },
        "action_category" => {
          "type" => "string",
          "description" => "Autonomy-gate category that required approval, e.g. sdwan.network_create."
        },
        "deferred_operation_id" => {
          "type" => "string",
          "description" => "Ai::DeferredOperation UUID that will run on approval. May be null."
        },
        "approval_request_id" => {
          "type" => "string",
          "description" => "Ai::ApprovalRequest UUID an operator decides. May be null."
        },
        "message" => {
          "type" => "string",
          "description" => "Human-readable statement of what is awaiting approval."
        }
      }.freeze

      # === LIST PAGINATION (APO-8b, IMP-c5a62a32d3bb) ===
      #
      # Before this seam, a list action on the MCP surface answered in one of
      # three incompatible ways: it serialized every matching row, or it applied
      # a hard-coded cap, or it accepted a `limit` of its own invention. The
      # `count` beside the rows was worse than absent, because it did not mean
      # the same thing twice — some actions counted the UNCAPPED relation, some
      # counted the relation AFTER the cap (so a 100-row account and a
      # 10,000-row account answered identically), and some returned no count.
      # None offered a page two.
      #
      # This is core, not extension, because the defect is not extension-shaped:
      # any tool that serializes a relation has it, and a per-tool fix would
      # reproduce exactly the inconsistency that is the finding.
      #
      # THE CONTRACT every paginated action inherits:
      #   count       the UNCAPPED total matching the filters
      #   returned    rows in THIS page
      #   limit       the effective page size actually applied
      #   has_more    true when rows remain beyond this page
      #   next_cursor pass back as `cursor` to fetch them; null at the end
      #
      # KEYSET, NOT OFFSET. The cursor pins the position of the last row
      # returned on (sort key, id) and the next page asks for rows strictly past
      # it. Ids are UUIDv7 (uuidv7-everywhere), so the id tiebreak is
      # time-ordered and total: two rows sharing a sort value still have a
      # deterministic order, and a row inserted mid-walk cannot shift a page
      # boundary the way an OFFSET would.
      LIST_DEFAULT_LIMIT_SETTING = "ai_tools_list_default_limit"
      LIST_MAX_LIMIT_SETTING     = "ai_tools_list_max_limit"
      LIST_DEFAULT_LIMIT         = 100
      LIST_MAX_LIMIT             = 500

      # The fragment a paginated action splats into its declared parameters, so
      # the two names and their prose are written once. No `default:` key: the
      # effective default is operator config resolved per call, and freezing the
      # fallback into the advertised schema would state a number the platform
      # may not be using.
      PAGINATION_PARAMETERS = {
        limit: {
          type: "integer", required: false,
          description: "Maximum rows in this page. Omit for the operator-configured default page size. " \
                       "A value above the configured maximum is clamped down, not refused."
        },
        cursor: {
          type: "string", required: false,
          description: "Opaque keyset cursor taken from a previous page's `next_cursor`. Omit for the first page. " \
                       "Read `count` (the total matching your filters, NOT this page's size) and `has_more` to tell " \
                       "a complete answer from a truncated one."
        }
      }.freeze

      # One page plus the numbers a caller needs to know what it is holding.
      ListPage = Struct.new(:records, :total, :limit, :next_cursor) do
        def envelope
          {
            count:       total,
            returned:    records.size,
            limit:       limit,
            has_more:    !next_cursor.nil?,
            next_cursor: next_cursor
          }
        end
      end

      # A cursor the platform did not issue, or a limit that is not a number.
      # Raised only INSIDE #paginated_result, which converts it to an
      # error_result — SdwanTool#call and SystemPackageRepositoryTool#call do
      # not rescue ArgumentError, so a raise escaping a list action would reach
      # the agent as a JSON-RPC -32603 internal error instead of a refusal it
      # can read and correct.
      class InvalidPageRequest < StandardError; end

      class << self
        # Operator-configured page size, with the constant as the fallback.
        # A non-positive configured value is ignored rather than honoured: a
        # zero would make every list action answer with an empty page and no
        # way to walk past it.
        def default_list_limit
          positive_setting(LIST_DEFAULT_LIMIT_SETTING, LIST_DEFAULT_LIMIT)
        end

        # The ceiling a caller-supplied `limit` is clamped to.
        def max_list_limit
          positive_setting(LIST_MAX_LIMIT_SETTING, LIST_MAX_LIMIT)
        end

        def positive_setting(key, fallback)
          value = ::SiteSetting.get(key).to_i
          value.positive? ? value : fallback
        end
        private :positive_setting

        # THE ONE BUILDER for the body PENDING_RESULT_PROPERTIES describes
        # (APO-1f, IMP-117b34656921).
        #
        # Three producers emit this envelope — #run_through_autonomy_gate's
        # :pending arm below, SdwanTool#gated_result, and (through
        # System::Ai::Skills::BaseSkillExecutor#gate_action!) every
        # approval-gated system skill — and Ai::Provisioning::SkillCompositionRunner
        # READS it to decide a composed step parked rather than completed. A
        # second spelling of the shape is what let the same parked category
        # answer "pending" through one door and "failed" through another, so the
        # keys are built here, once, beside the constant the outputSchema
        # advertises and the fidelity spec pins them against.
        #
        # A tool may still splat its own extra keys alongside (SdwanTool's
        # `pending_extra`); this is the floor, not the ceiling.
        def pending_payload(action_category:, deferred_operation: nil,
                            approval_request: nil, message: nil)
          {
            pending: true,
            action_category: action_category,
            deferred_operation_id: deferred_operation&.id,
            approval_request_id: approval_request&.id,
            message: message.presence || "Approval required: #{action_category}"
          }
        end

        def definition
          raise NotImplementedError, "#{name} must implement .definition"
        end

        # Returns per-action tool definitions keyed by external registry name.
        # Single-action tools inherit this default which strips the :action param.
        # Multi-action tools override to provide focused per-action schemas.
        def action_definitions
          defn = definition
          params = (defn[:parameters] || {}).except(:action)
          { defn[:name] => { description: defn[:description], parameters: params } }
        end

        def permitted?(agent:)
          return true unless self::REQUIRED_PERMISSION
          return true unless agent
          return true unless agent.respond_to?(:account) && agent.account

          # A tool is permitted for an agent when any user in its account holds the
          # required permission. Use the canonical resolution (User#has_permission?) so
          # CODE-DEFINED role grants count — a raw RolePermission query only sees DB
          # grants and silently hides every code-defined-role permission (e.g.
          # ai.campaigns.*) from all agents, including the concierge. Accounts are small
          # (single-user in core mode), so the per-user check is cheap.
          agent.account.users.any? { |user| user.has_permission?(self::REQUIRED_PERMISSION) }
        rescue StandardError
          # If permission check fails, allow the tool — execution is already
          # gated by the triggering user's API-level authorization.
          true
        end

        def tool_name
          definition[:name]
        end

        # GOVERNANCE REGISTRY (IMP-d410a587d6bf) — a tool DECLARES what each of
        # its actions does; BaseTool#execute is what acts on the declaration.
        #
        # Why a declaration and not a gate call in the action body: the MCP half
        # of instance lifecycle shipped with ZERO Ai::AutonomyGate references
        # while its REST twin gated every arm, and the reason is that gating was
        # a per-call-site habit. SdwanTool carries 31 hand-placed gate sites and
        # is still the only tool that has any — a site you must remember to add
        # is a site that is missing wherever nobody remembered. The same lesson
        # produced #enforce_instance_deny_overlay! one hop above this
        # (IMP-0e6b216de843): the control belongs at the chokepoint every caller
        # already passes, not at the arms.
        #
        # This is the chokepoint. MANY sites construct a tool and call
        # `.execute(params:)` without going through McpPlatformToolRegistrar —
        # concierge_tool_bridge, dev_loop_tool, growth/cross_post_service,
        # system/platform/volumes_controller, storage_migrations_controller,
        # crud_factory and a spread of skill executors (grep `\.execute(params`
        # for the current set; it grows). They arrive HERE, which is why the
        # registrar is the wrong altitude for this and #execute is right.
        #
        # NO exemptions. Ai::Tools::FederationTool used to override this method
        # without super — the tool that proxies arbitrary remote tool names,
        # outside the registry, the deny overlay and validate_params! —
        # and IMP-149b35e5f16f moved its body to #call. That no class serving
        # a PlatformApiToolRegistry action overrides this method is asserted
        # positively — over every registry-backed class, not as a pin on the
        # one known offender — in spec/services/ai/tools/
        # action_declaration_completeness_spec.rb, so a new override cannot
        # reappear unnoticed and read as coverage. (A tool outside that
        # registry is outside the assertion, as it is outside the equality.)
        #
        # `mutating:` is INTENT for the registry: it can carry the fail-closed
        # invariant "an undeclared action is refused" (IMP-439d31353f9b owns
        # that flip). Nothing enforces it today.
        #
        # APO-1a (IMP-1e58753b3b6c) closed the gap that blocked the flip: every
        # action Ai::Tools::PlatformApiToolRegistry.all_tools advertises now
        # carries a declaration, asserted by set EQUALITY (both directions) in
        # spec/services/ai/tools/action_declaration_completeness_spec.rb. An
        # existence check could not do that job — a declaration keyed on the
        # registry key rather than the ALIASED name #execute dispatches on
        # reads as coverage while the action still runs undeclared.
        #
        # Those bulk declarations pass `mutating:` and NOTHING ELSE, on
        # purpose. #gated_action? below needs action_category, executor_class,
        # gate_context and on_proceed as well, so a `mutating:`-only
        # declaration cannot arm the gate: #execute still takes `return
        # call(params)`, and a tool that enforces per-action permissions inside
        # #call (SystemFleetTool#action_permitted?) keeps that check. That is
        # what makes the increment non-enforcing, and it is why
        # action_category is absent rather than guessed: Ai::InterventionPolicy
        # keeps a REGISTERED category vocabulary (see its STATIC_CATEGORIES and
        # .register_category!), and a category no active policy row matches
        # resolves to Ai::InterventionPolicyService#default_policy —
        # "require_approval". A guessed category is therefore not inert: it
        # would park real actions behind an approval nobody wrote a policy for.
        # A category is only meaningful paired with the executor that can
        # replay the action, so both are the gate-wiring increment's work.
        #
        # CORE PURITY: core never names an extension class. `executor_class` is
        # a STRING supplied by the declaring tool (which may live in an
        # extension), and the two hooks are method names resolved on the tool
        # instance. Nothing extension-shaped is referenced from this file.
        #
        # @param name            [String] the routed action name (what
        #                        #effective_action_name returns), not the tool name
        # @param mutating        [Boolean] does this action write?
        # @param action_category [String, nil] Ai::InterventionPolicy category
        # @param executor_class  [String, nil] fully-qualified executor name;
        #                        AutonomyGate replays THIS on approval, so it —
        #                        not the action body — must be the actor
        # @param gate_context    [Symbol, nil] tool method (params) => {
        #                        executor_params:, description:, source_type:,
        #                        source_id: }
        # @param on_proceed      [Symbol, nil] tool method (params, gate_result)
        #                        => the tool's own success payload
        # @param ungated_when    [Symbol, nil] tool method (params) => true when
        #                        THIS call is the action's read-shaped arm and
        #                        must dispatch to #call as an ungated action
        #                        would (HIER-P2B-ENG: system_deploy_platform
        #                        with no `mode` returns the wizard card and
        #                        provisions nothing; parking a form read as an
        #                        approval is wrong). Decided on the tool's own
        #                        method, never from a caller-supplied name, and
        #                        a predicate the tool does not define never
        #                        opens the arm — the call stays gated. The
        #                        action still counts as gate-routed
        #                        (#gated_action? ignores it).
        def declare_action(name, mutating:, action_category: nil, executor_class: nil,
                           gate_context: nil, on_proceed: nil, ungated_when: nil)
          declared_actions[name.to_s] = {
            mutating: mutating,
            action_category: action_category,
            executor_class: executor_class,
            gate_context: gate_context,
            on_proceed: on_proceed,
            ungated_when: ungated_when
          }.freeze
        end

        def declared_actions
          @declared_actions ||= {}
        end

        # Is this name actual MCP registry surface? The allowlist that bounds
        # undeclared-execution telemetry cardinality (see the private
        # UNDECLARED-EXECUTION TELEMETRY block) — a caller-supplied
        # params[:action] is an arbitrary string and must never become a cache
        # key or an audit row on its own authority.
        #
        # Reads .all_tools rather than TOOLS + extension_tools so it cannot
        # drift from the registry's own definition of its surface, and is
        # deliberately NOT memoized: a memo would freeze the extension half at
        # whatever was registered on first use. The cost is one merge of a
        # ~600-entry frozen hash on a path that is already doing database work.
        def registered_action_name?(name)
          ::Ai::Tools::PlatformApiToolRegistry.all_tools.key?(name) ||
            ::Ai::Tools::McpPlatformToolRegistrar::ACTION_ALIASES.value?(name)
        end

        # Walks the ancestry so a subclass inherits its parent's declarations
        # without re-declaring them.
        def declared_action(name)
          key = name.to_s
          klass = self
          while klass.respond_to?(:declared_actions)
            found = klass.declared_actions[key]
            return found if found

            klass = klass.superclass
          end
          nil
        end
      end

      # `internal: true` marks an in-process system caller (autonomy
      # reconcilers, skill executors running without a user) that is trusted to
      # skip a tool's per-action permission gate. It must be passed EXPLICITLY:
      # a nil @user does NOT imply "internal", because an MCP instance
      # principal (mTLS node cert) also arrives with no user, and tools that
      # inferred "internal" from `user.nil?` silently handed those principals
      # every per-action permission. (IMP-9030413bc292)
      def initialize(account:, agent: nil, user: nil, internal: false)
        @account = account
        @agent = agent
        @user = user
        @internal = internal
      end

      # Optionally injected post-construction by McpPlatformToolRegistrar for an
      # instance principal (mTLS node cert; no User/Agent) so DevLoopTool#claimant_ref
      # can scope claims as "instance:<id>". Public writer (external caller);
      # nil for user/agent callers, whose paths are unchanged. (BUG-S)
      attr_writer :node_instance

      # Set by Ai::Executors::DeferredToolCall when it re-invokes a tool call an
      # operator has APPROVED (APO-1b; docs/concepts/deferred-tool-call-replay.md).
      # The gate already ran for this call, so #execute must not park it a second
      # time — see #approved_replay?, which is where the bypass is decided.
      #
      # Deliberately the OPERATION and not a boolean. A `replaying = true` flag
      # would be a gate bypass any in-process caller could set, which is exactly
      # the hole #run_through_autonomy_gate refuses to open for `internal: true`.
      # Taking the row means the bypass exists only where an approved
      # Ai::DeferredOperation naming that executor exists.
      attr_writer :replaying_operation

      # Set by McpPlatformToolRegistrar when the caller is an instance principal
      # whose SPECIFIC tool name already passed Mcp::Principal#may_invoke? in
      # the streamable controller. Lets a tool tell a grant-gated instance call
      # apart from a bare no-user call — indistinguishable while both were just
      # "@user is nil". (IMP-9030413bc292; sibling of the BUG-S writer above.)
      attr_writer :instance_authorized

      def execute(params:)
        # Ahead of validation: the refusal is unconditional, so a malformed
        # destroy-shaped call must not come back as a params error instead.
        enforce_instance_deny_overlay!(params)
        validate_params!(params)
        enforce_guardrails!

        action_name = routed_action_name(params)
        declaration = self.class.declared_action(action_name)

        # UNDECLARED PATH. Behaviourally `return call(params)` — which is what
        # an undeclared action always did, since gated_action?(nil) is false —
        # plus one sighting recorded in an `ensure` AFTER the body has run.
        #
        # AFTER, not before (D4): AuditLog's integrity chain serializes every
        # insert behind pg_advisory_xact_lock(SEQUENCE_LOCK_KEY), and an
        # advisory *xact* lock is only released by the OUTERMOST transaction's
        # commit. Emitting first meant that, inside a caller's transaction, the
        # global audit-sequence lock was held across the whole of #call —
        # provider/HTTP latency for a fleet tool — with every audit write on the
        # platform queued behind it.
        #
        # `ensure`, so a raising tool still records its sighting. That makes an
        # exception escaping the telemetry able to REPLACE the tool's own return
        # value or exception, so #record_undeclared_action carries an outermost
        # rescue. Not a silent swallow: it logs at ERROR level.
        if declaration.nil?
          begin
            return call(params)
          ensure
            record_undeclared_action(action_name)
          end
        end

        return call(params) unless gated_action?(declaration)
        # The declared READ arm of a gate-routed action (see `ungated_when` on
        # .declare_action): dispatched exactly as an ungated action, so the
        # tool's own per-action permission check inside #call still runs.
        return call(params) if ungated_read_arm?(declaration, params)

        # A gated action never reaches #call, and tools that enforce per-action
        # permissions INSIDE #call (SystemFleetTool#action_permitted?) would
        # lose that check the moment an action is declared — a privilege
        # escalation introduced by a safety control. #authorization_error is the
        # seam that keeps the two in step.
        refusal = authorization_error(params)
        return refusal if refusal

        # APPROVED REPLAY. Everything above this line still runs — the deny
        # overlay, #validate_params!, #enforce_guardrails! and the tool's own
        # #authorization_error — because a decision made hours ago does not
        # re-authorise a principal that has changed since. Only the gate is
        # skipped, and only because it already ran and an operator answered it.
        # Without this the replayed call would park a second approval, forever.
        return call(params) if approved_replay?

        run_through_autonomy_gate(declaration, params)
      end

      protected

      # SECURITY (IMP-0e6b216de843): re-arm Mcp::Principal's destructive deny
      # overlay against the action that ACTUALLY runs, at every depth.
      #
      # The overlay is documented in mcp/principal.rb as the last remaining
      # control on an instance principal, and it is checked against a tool NAME
      # — once, in the streamable controller, for the FIRST tool invoked. Below
      # that hop it had no reach: a tool that delegates to a skill executor
      # (SdwanTool, SystemIngressTool) forwarded only `user:`, so the executor
      # saw a nil user, called every nested tool `internal: true`, and no nested
      # name was ever name-checked. A grant for one benign name therefore
      # reached whatever those executors nest — including a destroy-shaped tool
      # the overlay refuses unconditionally, by name, at the first hop.
      # Executors now carry the provenance (System::Ai::Skills::
      # BaseSkillExecutor#tool), and this is the fence it re-arms.
      #
      # Grant globs are deliberately NOT re-checked here. The operator granted a
      # composer; the steps that composer runs are its implementation, not
      # separately-granted surface, and re-checking them would make a production
      # grant depend on composer internals — it would break at runtime, silently,
      # whenever a composer changed a step. The overlay is the right bound for
      # nested work: deny wins over any grant, at any depth.
      #
      # At the first hop this is a no-op (the controller already refused the
      # name, and McpPlatformToolRegistrar#enforce_action_scope! pins the action
      # to it) — which also means it holds the line if that pin is ever removed.
      def enforce_instance_deny_overlay!(params)
        return unless instance_authorized?

        name = effective_action_name(params)
        return unless ::Mcp::Principal.destructive_tool?(name)

        Rails.logger.warn(
          "[BaseTool] Refused destroy-shaped action for instance principal: " \
          "tool=#{self.class.name} action=#{name}"
        )
        raise ::Mcp::ProtocolService::PermissionDeniedError,
              "Action '#{name}' is destroy-shaped and is denied to every instance " \
              "principal, whatever it was granted"
      end

      # The tool's own pre-dispatch authorization, hoisted so a gated action —
      # which bypasses #call — is authorized exactly as an ungated one is.
      # Returns an error_result to refuse, nil to allow. Default: nothing to
      # add, because a single-action tool's permission is enforced by
      # .permitted? / the MCP layer before construction.
      def authorization_error(_params)
        nil
      end

      # True only for a call Ai::Executors::DeferredToolCall is re-invoking on
      # behalf of an APPROVED operation, in THIS tool's account.
      #
      # Every clause is load-bearing. The row must name that executor (nothing
      # else stamps this writer), it must be past the approval decision
      # (#execute_now! moves it to :executing before calling the executor), and
      # it must belong to the account the tool is running in — otherwise a row
      # from another tenant would license a bypass here.
      def approved_replay?
        operation = @replaying_operation
        return false if operation.nil?
        return false unless operation.respond_to?(:executor_class) &&
                            operation.respond_to?(:status) &&
                            operation.respond_to?(:account_id)
        return false unless operation.executor_class.to_s == ::Ai::Executors::DeferredToolCall.name
        return false unless ::Ai::Executors::DeferredToolCall::REPLAYABLE_STATUSES
                              .include?(operation.status.to_s)

        !account.nil? && operation.account_id == account.id
      end

      # THE generic `gate_context` (APO-1b). A tool wires an action to the gate
      # with:
      #
      #   declare_action "system_terminate_instance",
      #                  mutating: true,
      #                  action_category: "system.instance.terminate",
      #                  executor_class: "Ai::Executors::DeferredToolCall",
      #                  gate_context: :deferred_tool_call_context,
      #                  on_proceed: :deferred_tool_call_result
      #
      # and needs no executor of its own. `source_type`/`source_id` are
      # deliberately absent: this seam does not know which of a caller's params
      # names a row, and Ai::DeferredOperation#assert_source_within_account!
      # no-ops for an unrecorded pair rather than guessing. The executor's own
      # params-level scoping remains the anchor for what it touches.
      def deferred_tool_call_context(params)
        action = routed_action_name(params)
        descriptor = caller_principal_descriptor(action)

        # VALIDATE FIRST, so a call that could only ever be refused on replay
        # does not park an approval an operator then has to dispose of. An
        # "unattributed" caller (a federation principal, or any restricted
        # principal arriving without a node instance) is exactly that: the
        # executor's rehydrate step returns nil for it and refuses. Raising
        # ArgumentError is the seam #run_through_autonomy_gate already rescues
        # around the context build, and it converts to the caller's error
        # envelope BEFORE Ai::AutonomyGate.evaluate is reached.
        if descriptor["kind"] == "unattributed"
          raise ArgumentError,
                "Action #{action} is approval-gated and cannot be parked for an unattributed " \
                "caller (#{descriptor['detail']}): an approval granted for it could never be replayed"
        end

        {
          executor_params: ::Ai::Executors::DeferredToolCall.pack(
            tool_class: self.class.name,
            action: action,
            tool_params: params,
            principal: descriptor
          ),
          description: deferred_tool_call_description(params)
        }
      end

      # Override for a better approval-card line. Keep it free of caller param
      # VALUES — Ai::SensitiveParams covers the APPROVAL-CARD copy
      # (Ai::AutonomyGate writes `request_data` through the filter) and NOT the
      # executor params on the operation row, which the replay needs verbatim.
      # A description that interpolates a param value therefore lands outside
      # the only cover there is.
      def deferred_tool_call_description(params)
        "#{routed_action_name(params)} via #{self.class.name}"
      end

      # THE generic `on_proceed`. On the auto-approve branch the executor has
      # already replayed the call, so this SERIALIZES what it returned — the
      # tool's own envelope, byte-identical to an ungated call — and must not
      # repeat the work.
      def deferred_tool_call_result(_params, gate_result)
        return gate_result.result if gate_result.result.is_a?(::Hash)

        success_result(replayed: true)
      end

      # WHO is calling, in the shape Ai::Executors::DeferredToolCall rebuilds.
      #
      # Minted from this tool's OWN constructor state, never from params, so a
      # caller cannot describe itself. Order matters: an instance principal
      # carries no User, and a nil user is NOT evidence of an in-process caller
      # (IMP-9030413bc292) — `internal:` has to have been passed explicitly.
      #
      # Anything else is recorded as "unattributed"; #deferred_tool_call_context
      # refuses to park such a call at all. That arm is reachable: a FEDERATION
      # principal arrives here `instance_authorized` with no node instance,
      # because the controller passes `restricted?` rather than `instance?`.
      #
      # `internal` rides ALONGSIDE the kind rather than as a kind of its own,
      # because the two are orthogonal at depth: a skill executor nests every
      # tool with `internal: internal_caller?` while still forwarding the
      # caller's user/agent, so a nested hop is routinely BOTH `agent` and
      # internal. Recording only the kind would rebuild a strictly WEAKER tool
      # on replay, and a tool enforcing per-action permissions with
      # `return true if internal?` would then refuse the action an operator had
      # just approved — the approval silently becoming a no-op.
      def caller_principal_descriptor(action = nil)
        if instance_authorized?
          if node_instance
            return { "kind" => "instance", "node_instance_id" => node_instance.id,
                     "granted_tool_name" => granted_tool_name_for(action) }
          end

          { "kind" => "unattributed", "detail" => "restricted principal with no node instance" }
        elsif user
          { "kind" => "user", "user_id" => user.id, "agent_id" => agent&.id, "internal" => internal? }
        elsif agent
          { "kind" => "agent", "agent_id" => agent.id, "internal" => internal? }
        elsif internal?
          { "kind" => "internal" }
        else
          { "kind" => "unattributed", "detail" => "no user, agent or explicit internal flag" }
        end
      end

      # WHICH NAME the instance grant was actually checked against on the first
      # hop. StreamableHttpController asks `may_invoke?("platform.<tool_name>")`
      # — the advertised REGISTRY KEY — and McpPlatformToolRegistrar#
      # enforce_action_scope! then pins the action to
      # `ACTION_ALIASES.fetch(tool_name, tool_name)`, i.e. the alias TARGET. For
      # the 25 aliased keys the routed action is therefore NOT the granted name:
      # a call granted as "platform.code_upsert_node" runs as "upsert_node", and
      # re-asking `may_invoke?("platform.upsert_node")` on replay matches no
      # realistic glob and would refuse every approved replay of an aliased
      # mutating action. Inverting the table (values are unique) recovers the
      # name the grant was read against; an unaliased action is its own name.
      def granted_tool_name_for(action)
        return nil if action.blank?

        ::Ai::Tools::McpPlatformToolRegistrar::ACTION_ALIASES.key(action.to_s) || action.to_s
      end

      # A declaration is GATED only when it can actually be replayed. Ai::
      # AutonomyGate defers by storing `executor_class` and re-invoking it after
      # approval, so a declaration without an executor could park an approval
      # that, once granted, performs nothing. Declaring `mutating: true` alone
      # therefore records intent for the registry without arming a gate that
      # cannot complete.
      def gated_action?(declaration)
        return false unless declaration
        return false unless declaration[:mutating]

        declaration[:action_category].present? &&
          declaration[:executor_class].present? &&
          declaration[:gate_context].present? &&
          declaration[:on_proceed].present?
      end

      # True only when the declaration names a read-arm predicate, the tool
      # DEFINES it, and it answers true for these params. Fail closed: an
      # undefined predicate is logged and the call stays gated rather than
      # slipping past the gate on a typo.
      def ungated_read_arm?(declaration, params)
        predicate = declaration[:ungated_when]
        return false if predicate.blank?

        unless respond_to?(predicate, true)
          Rails.logger.error(
            "[BaseTool] ungated_when #{predicate.inspect} is not defined on #{self.class.name}; " \
            "keeping #{declaration[:action_category]} gated"
          )
          return false
        end

        send(predicate, params) == true
      end

      # The executor — never the action body — is the actor on BOTH branches.
      #
      # This is forced by AutonomyGate's contract, not a preference: on
      # auto_approve/notify_and_proceed the gate itself calls
      # DeferredOperation#execute_now!, and on approval the worker replays the
      # same executor. An action body that also did the work would run it twice
      # on the proceed branch. `on_proceed` therefore SERIALIZES what the
      # executor did; it must not repeat it. (Same shape as SdwanTool's
      # gated_result block, which reads the executor's result rather than
      # writing.)
      #
      # There is deliberately NO `internal: true` bypass. An in-process caller
      # that legitimately needs an ungated mutation calls the underlying service
      # directly; a bypass keyed on a constructor flag is exactly the hole this
      # chokepoint exists to close.
      def run_through_autonomy_gate(declaration, params)
        misdeclaration = gate_declaration_defect(declaration)
        return misdeclaration if misdeclaration

        # SCOPED to the context build, deliberately. A gated action returns
        # before #call and so no longer benefits from a tool's own rescue there,
        # and these two are what resolving the caller's target realistically
        # raises — callers expect the error ENVELOPE, not an escaping exception.
        #
        # It must NOT span the gate or #on_proceed. Past AutonomyGate.evaluate
        # the executor may already have destroyed the resource, and swallowing a
        # raise from the serialization hook would report `success: false` for an
        # operation that COMPLETED — an agent reads that as "not terminated" and
        # retries. A post-execution failure has to surface as a failure.
        context =
          begin
            send(declaration[:gate_context], params) || {}
          rescue ActiveRecord::RecordNotFound, ArgumentError => e
            return error_result(e.message)
          end

        gate = ::Ai::AutonomyGate.evaluate(
          action_category: declaration[:action_category],
          executor_class: declaration[:executor_class],
          params: context[:executor_params] || {},
          account: account,
          agent: agent,
          requested_by: user,
          source_type: context[:source_type],
          source_id: context[:source_id],
          description: context[:description]
        )

        case gate.decision
        when :proceed
          send(declaration[:on_proceed], params, gate)
        when :pending
          success_result(
            self.class.pending_payload(
              action_category: declaration[:action_category],
              deferred_operation: gate.deferred_operation,
              approval_request: gate.approval_request
            )
          )
        else
          error_result(gate.error || "Action #{declaration[:action_category]} is blocked by policy")
        end
      end

      # Fail CLOSED on a broken declaration. A typo'd hook name would otherwise
      # raise NoMethodError out of #execute, and — worse — a typo'd
      # executor_class passes the .present? test in #gated_action?, parks a real
      # approval, and then performs NOTHING when someone approves it. Refusing
      # is the safe reading of "this action is declared mutating and its gate is
      # not wired".
      def gate_declaration_defect(declaration)
        %i[gate_context on_proceed].each do |hook|
          next if respond_to?(declaration[hook], true)

          return gate_misdeclared(declaration, "#{hook} method #{declaration[hook].inspect} is not defined")
        end

        return nil if declaration[:executor_class].safe_constantize

        gate_misdeclared(declaration, "executor_class #{declaration[:executor_class].inspect} does not resolve")
      end

      def gate_misdeclared(declaration, reason)
        Rails.logger.error(
          "[BaseTool] Refusing declared mutating action — misdeclared gate: " \
          "tool=#{self.class.name} category=#{declaration[:action_category]} #{reason}"
        )
        error_result("Action #{declaration[:action_category]} is declared approval-gated " \
                     "but its gate is misconfigured; refusing.")
      end

      # Build a skill executor with THIS tool's caller context and hand it the
      # instance provenance. EVERY tool that routes an MCP action to a skill
      # executor must come through here.
      #
      # An executor built any other way sees only a nil user, cannot tell a
      # grant-gated instance principal from an in-process reconciler, and so
      # calls every tool it nests `internal: true` — silently re-opening the
      # bypass this closed. That is not hypothetical: the same drop existed
      # independently in three tools (SdwanTool, SystemIngressTool and
      # SystemFleetTool's seven sites), which is why it is one funnel now rather
      # than a rule to remember at each call site.
      #
      # `account:` is overridable because a call site may resolve the account
      # differently; everything else is fixed by construction.
      # (IMP-0e6b216de843)
      def build_skill_executor(executor_class, account: @account, **overrides)
        mark_instance_provenance(
          executor_class.new(account: account, agent: @agent, user: @user, **overrides)
        )
      end

      # Hand this call's INSTANCE provenance to a delegate the tool routes to
      # (a skill executor). Guarded, so reconciler and user calls are untouched
      # and their paths stay byte-for-byte unchanged. Without it the delegate
      # sees only a nil user and cannot tell a grant-gated instance principal
      # from an in-process caller — which is how a name-scoped grant turned into
      # a blanket internal bypass one hop down. (IMP-0e6b216de843)
      def mark_instance_provenance(target)
        return target unless instance_authorized?

        target.instance_authorized = true
        target.node_instance = node_instance if node_instance
        target
      end

      # What the deny overlay must be matched against: the routed action for a
      # multi-action tool, the tool's own name otherwise.
      #
      # OVERRIDABLE, and overridden — SystemFleetTool widens it to the
      # destroy-shaped INNER op of a composer wrapper so the overlay refuses the
      # work that would actually run. That widening is correct for a DENY and
      # wrong for a registry lookup, which is why the governance registry keys
      # off #routed_action_name instead: a caller who set both `action:
      # system_terminate_instance` and a destructive inner key would otherwise
      # resolve to the inner name, match no declaration, and reach #call — which
      # dispatches on params[:action] — with the gate skipped.
      def effective_action_name(params)
        routed_action_name(params)
      end

      # The action #call will actually dispatch on. Deliberately NOT overridable
      # for widening: this is the key the governance registry and the gate use,
      # and it must name the same work the tool is about to do.
      def routed_action_name(params)
        # ActionController::Parameters is NOT a Hash and reaches #execute from
        # controller call sites. Degrading to the tool name for those is
        # exactly the "matches no declaration -> reaches #call ungated" failure
        # this method exists to prevent, so accept both shapes.
        supplied =
          if params.is_a?(Hash) || params.respond_to?(:to_unsafe_h)
            params[:action] || params["action"]
          end
        supplied.to_s.presence || self.class.definition[:name].to_s
      end

      def call(params)
        raise NotImplementedError, "#{self.class.name} must implement #call"
      end

      def validate_params!(params)
        param_def = self.class.definition[:parameters]
        return unless param_def.is_a?(Hash)

        # Skip JSON Schema-style definitions (have :type key) — validated at action level
        return if param_def.key?(:type)

        required = param_def.select { |_, v| v.is_a?(Hash) && v[:required] }.keys
        missing = required.select { |k| params[k].blank? }
        raise ArgumentError, "Missing required parameters: #{missing.join(', ')}" if missing.any?
      end

      def enforce_guardrails!
        validate_account_context!
      end

      def validate_account_context!
        return unless account

        unless account.is_a?(Account) && account.persisted?
          raise ArgumentError, "Invalid account context for tool execution"
        end
      end

      def success_result(data)
        { success: true, data: data }
      end

      def error_result(message)
        { success: false, error: message }
      end

      # True only when the caller explicitly declared itself an in-process
      # system caller via `internal: true`.
      def internal?
        @internal == true
      end

      # True only when McpPlatformToolRegistrar marked this call as an instance
      # principal that already cleared the per-tool grant gate.
      def instance_authorized?
        @instance_authorized == true
      end

      private

      attr_reader :account, :agent, :user, :node_instance

      # === LIST PAGINATION — the call side of the contract above ===

      # THE ONE BUILDER for a paginated list payload. Returns a finished tool
      # result: success_result carrying the serialized rows under `key`, any
      # per-action `extra` keys, and the shared page envelope — or error_result
      # when the caller's limit/cursor cannot be honoured.
      #
      # Takes the relation UNORDERED and imposes its own order, because the
      # keyset predicate and the ORDER BY have to agree exactly; a caller that
      # ordered first would silently get a cursor pointing into a different
      # sequence than the one it is walking.
      #
      # @param key       [Symbol] payload key the rows go under
      # @param relation  [ActiveRecord::Relation] already filtered, NOT ordered
      # @param params    [Hash] the action params (reads :limit and :cursor)
      # @param sort      [Symbol] column the page is ordered by; :id walks in
      #                  UUIDv7 (creation) order
      # @param direction [:asc, :desc]
      # @param extra     [Hash] additional payload keys for this action
      # @yield [record] serializer for one row
      def paginated_result(key, relation, params, sort: :id, direction: :desc, **extra, &serializer)
        page = paginate_list(relation, params, sort: sort, direction: direction)
        success_result(
          { key => page.records.map(&serializer) }.merge(extra).merge(page.envelope)
        )
      rescue InvalidPageRequest => e
        error_result(e.message)
      end

      def paginate_list(relation, params, sort: :id, direction: :desc)
        sort      = sort.to_sym
        direction = direction.to_sym == :asc ? :asc : :desc
        limit     = resolve_list_limit(params[:limit])

        # A NULL sort value makes the row comparison in #apply_list_cursor NULL
        # — never true — so a nullable sort column would silently DROP every
        # such row from page two onward and the walk would end short of `count`
        # with nothing to show for it. Refused here as the call-site bug it is,
        # rather than left to produce a quietly incomplete answer. Order by :id
        # (UUIDv7, and a primary key) when the natural sort column is nullable.
        assert_sortable_column!(relation.klass, sort) unless sort == :id

        # UNCAPPED, and computed off the relation BEFORE the cursor narrows it:
        # `count` answers "how many match my filters", which is the question a
        # caller deciding whether to keep walking is actually asking.
        total = relation.count

        scoped = apply_list_cursor(relation, params[:cursor], sort, direction)
        order  = sort == :id ? { id: direction } : { sort => direction, :id => direction }

        # One row past the page: the only way to know whether a cursor is owed
        # without a second COUNT over the narrowed scope.
        rows = scoped.reorder(order).limit(limit + 1).to_a
        more = rows.size > limit
        rows = rows.first(limit)

        ListPage.new(rows, total, limit, more ? encode_list_cursor(rows.last, sort) : nil)
      end

      def assert_sortable_column!(model, sort)
        column = model.columns_hash[sort.to_s]
        return if column && !column.null

        raise ArgumentError,
              "paginate_list: #{model.name}.#{sort} is #{column ? 'nullable' : 'not a column'} and cannot " \
              "carry a keyset cursor — sort by :id instead"
      end

      def resolve_list_limit(raw)
        return self.class.default_list_limit if raw.nil? || raw.to_s.strip.empty?

        value = Integer(raw.to_s.strip, 10)
        raise InvalidPageRequest, "limit: must be a positive integer" unless value.positive?

        [ value, self.class.max_list_limit ].min
      rescue ArgumentError, TypeError
        raise InvalidPageRequest, "limit: must be a positive integer"
      end

      def apply_list_cursor(relation, raw, sort, direction)
        return relation if raw.nil? || raw.to_s.strip.empty?

        model  = relation.klass
        cursor = decode_list_cursor(raw, model, sort)
        table  = model.quoted_table_name
        id_col = "#{table}.#{model.connection.quote_column_name(model.primary_key)}"
        op     = direction == :asc ? ">" : "<"

        if sort == :id
          relation.where("#{id_col} #{op} ?", cursor[:id])
        else
          # Row comparison, so the sort column and the UUIDv7 tiebreak are one
          # strict ordering rather than two clauses that can disagree on ties.
          sort_col = "#{table}.#{model.connection.quote_column_name(sort)}"
          relation.where("(#{sort_col}, #{id_col}) #{op} (?, ?)", cursor[:value], cursor[:id])
        end
      end

      # Opaque by construction only — a base64 JSON pair. Deliberately not
      # signed: it carries no authority, the relation it is applied to is still
      # account-scoped by the caller, and a forged cursor can do nothing but
      # start the walk somewhere else in rows the caller could already read.
      def encode_list_cursor(record, sort)
        value = record.public_send(sort)
        value = value.utc.iso8601(6) if value.respond_to?(:utc) && value.respond_to?(:iso8601)
        Base64.urlsafe_encode64({ "v" => value, "i" => record.id }.to_json, padding: false)
      end

      def decode_list_cursor(raw, model, sort)
        parsed = JSON.parse(Base64.urlsafe_decode64(raw.to_s))
        # Shape check before the read: valid base64 of valid JSON is not yet a
        # cursor, and `5["i"]` is a NoMethodError this rescue would not catch.
        raise InvalidPageRequest, cursor_refusal unless parsed.is_a?(Hash)

        id = parsed["i"].to_s
        raise InvalidPageRequest, cursor_refusal if id.empty?

        # SHAPE-CHECK THE ID AGAINST THE PRIMARY KEY'S TYPE, not merely for
        # emptiness. A non-empty id that is not a UUID is bound straight into
        # `(sort, id) < (?, ?)` against a uuid column, and Postgres answers
        # `invalid input syntax for type uuid` — an ActiveRecord::StatementInvalid
        # that #paginated_result does not rescue and no tool's #call rescues
        # either, so it escapes to the JSON-RPC handler as -32603 "Internal
        # error". That is precisely the raise-instead-of-refuse this seam exists
        # to prevent, so the refusal happens here where the message is useful.
        raise InvalidPageRequest, cursor_refusal unless valid_cursor_id?(model, id)

        value = sort == :id ? id : model.type_for_attribute(sort.to_s).cast(parsed["v"])

        # A cursor whose sort value casts to NULL cannot satisfy the row
        # comparison either — it would return an empty page forever rather than
        # an error. Refused for the same reason.
        raise InvalidPageRequest, cursor_refusal if sort != :id && value.nil?

        { value: value, id: id }
      rescue ArgumentError, TypeError, JSON::ParserError
        raise InvalidPageRequest, cursor_refusal
      end

      UUID_CURSOR_ID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

      def valid_cursor_id?(model, id)
        column = model.columns_hash[model.primary_key.to_s]
        return true unless column&.type == :uuid

        UUID_CURSOR_ID.match?(id)
      end

      def cursor_refusal
        "cursor: not a cursor this action issued — omit it to start at the first page"
      end

      # UNDECLARED-EXECUTION TELEMETRY (IMP-a0553dda1ec3) — measure the real
      # breakage set BEFORE the fail-closed flip (IMP-439d31353f9b).
      #
      # 605 of the 606 registry actions execute with no declaration today. The
      # flip's invariant ("an undeclared action is refused") would refuse every
      # one of them, and nothing on the platform currently records WHICH of
      # those 605 actually run, under which kind of principal. That is the
      # number the flip has to be sized against, so this produces it from real
      # traffic instead of from a guess.
      #
      # WHY HERE: this is the same chokepoint the declaration registry itself
      # keys off, so the telemetry's notion of "the action" is #execute's, not
      # a parallel one that could drift — and, since IMP-149b35e5f16f closed the
      # last #execute override on a registry-backed tool, with no such tool
      # exempt from the measurement. (A tool outside PlatformApiToolRegistry is
      # outside both that assertion and this measurement, exactly as it is
      # outside the equality — the same bound recorded at declare_action above.)
      #
      # PRIVATE, not protected: #principal_kind is what keeps identity out of
      # both sinks, and a protected hook is one an extension subclass could
      # override to put identity back in.
      #
      # PRIVACY: principal SHAPE only — the kind of caller, never who. No user,
      # no email, no token, no node identity. See #principal_kind.
      #
      # CARDINALITY IS BOUNDED BY THE REGISTRY, NOT BY THE CALLER. The action
      # name reaching #execute is NOT drawn from the 606-key registry: for a
      # user or agent principal McpPlatformToolRegistrar#action_pinned_to_name?
      # is false and enforce_action_scope! early-returns for a non-dispatched
      # tool, so params[:action] is an arbitrary caller-supplied string that
      # #routed_action_name returns verbatim. Feeding that to a cache key and an
      # AuditLog row would let one authenticated caller mint an unbounded number
      # of first-sightings — a row per call, each serialized behind the global
      # audit-sequence advisory lock, with no retention job. So only a name that
      # is actually a registry key (or an ACTION_ALIASES target) is emitted;
      # everything else buckets under one sentinel. The sentinel is kept
      # DISTINCT rather than dropped so an operator can still see that
      # unregistered traffic exists and go looking for it.
      #
      # Fidelity cost, stated: an in-process caller that invokes a tool with an
      # internal action name that is neither a registry key nor an alias target
      # also buckets under the sentinel. The flip acts on the registry surface,
      # which is exactly what stays resolved.
      #
      # VOLUME: this fires on nearly all traffic. It is deduped per (account,
      # principal_kind, action) over a window — never per action alone, since
      # losing which actions execute undeclared destroys the entire point — and
      # a FIRST sighting is never dropped: the dedupe check fails OPEN (emit)
      # whenever the cache is unavailable.
      #
      # WHY AuditLog IS THE SINK ANYWAY. mcp_protocol_service_spec.rb records an
      # investigated objection to it for tool traffic: every insert serializes
      # behind one global Postgres advisory lock for its hash-chain sequence
      # number (Audit::LogIntegrityService::SEQUENCE_LOCK_KEY), and there is no
      # retention job — "built for low-volume compliance events, not a firehose
      # of tool calls". That objection is about a row PER CALL. The registry
      # bound plus the dedupe is what answers it: the write rate is capped by
      # the number of DISTINCT (account, principal_kind, registry action) tuples
      # per window, none of which a caller can inflate. If the flip ever wants
      # per-call fidelity it needs the purpose-built table that spec describes.
      UNDECLARED_ACTION_AUDIT_ACTION = "mcp.tools.undeclared_action"

      # Every caller-supplied action name that is not registry surface.
      UNREGISTERED_ACTION_LABEL = "<unregistered>"

      # How long one (account, principal_kind, action) tuple stays deduped. Long
      # enough that a hot action costs one row per hour, short enough that the
      # set stays a live picture rather than a one-time census.
      UNDECLARED_ACTION_DEDUPE_WINDOW = 1.hour

      # Defence in depth for the two sinks (D2). The registry allowlist above
      # already means only bounded, code-defined names are emitted; this makes
      # that guarantee LOCAL, so a future edit that widens the allowlist cannot
      # forge a log line with an embedded newline or push an unbounded blob into
      # jsonb and the cache key.
      TELEMETRY_TOKEN_MAX = 120

      # One structured sighting per (account, principal_kind, action) per window.
      #
      # The Rails.logger line is emitted FIRST and is not itself guarded, so the
      # sighting exists even if the durable row cannot be written. The row is
      # guarded, and so is the whole method — but by rescues that LOG at error
      # level, never ones that return quietly. That is required by the `ensure`
      # this runs in: an exception escaping here would replace the tool's own
      # return value or exception, breaking exactly the undeclared calls this
      # exists to observe.
      def record_undeclared_action(action_name)
        principal = principal_kind
        label = telemetry_action_label(action_name)
        return unless first_undeclared_sighting?(label, principal)

        Rails.logger.info(
          "[BaseTool] Undeclared action executed: " \
          "action=#{label} tool=#{telemetry_token(self.class.name)} principal=#{principal}"
        )
        persist_undeclared_action_audit(label, principal)
      rescue StandardError => e
        Rails.logger.error(
          "[BaseTool] Undeclared-action telemetry failed: " \
          "tool=#{self.class.name} error=#{e.class}: #{e.message}"
        )
      end

      # The name to emit: the real one when it is registry surface, one sentinel
      # otherwise. See the cardinality note above — this is the bound.
      def telemetry_action_label(action_name)
        name = telemetry_token(action_name)
        ::Ai::Tools::BaseTool.registered_action_name?(name) ? name : UNREGISTERED_ACTION_LABEL
      end

      # Strip anything that could forge a log line and clamp the length.
      def telemetry_token(value)
        value.to_s.gsub(/[[:cntrl:]]/, " ").slice(0, TELEMETRY_TOKEN_MAX).to_s
      end

      # The KIND of caller, never its identity. Ordered by how much the flip
      # will care: an instance principal is the one whose only remaining bound
      # is the deny overlay, so it is named first even when some other ivar is
      # also set.
      def principal_kind
        return "instance" if instance_authorized?
        return "user" if user
        return "agent" if agent
        return "internal" if internal?

        "none"
      end

      # Account-scoped (D7): without it one account's sighting suppresses every
      # other account's for the window, and the single row that survives names
      # the wrong account.
      #
      # Fails OPEN — an unavailable cache means EMIT, never drop. A first
      # sighting is the whole value of this telemetry; deduplication is only a
      # volume concession and must never be the reason an action goes unseen.
      def first_undeclared_sighting?(label, principal)
        key = "ai:tools:undeclared_action:#{account&.id}:#{principal}:#{label}"
        return false if Rails.cache.read(key)

        Rails.cache.write(key, true, expires_in: UNDECLARED_ACTION_DEDUPE_WINDOW)
        true
      rescue StandardError => e
        Rails.logger.warn(
          "[BaseTool] Undeclared-action dedupe unavailable (#{e.class}); emitting anyway: #{e.message}"
        )
        true
      end

      # SAVEPOINT, not just a rescue (D3). `rescue StandardError` does not undo a
      # Postgres transaction abort: if this INSERT fails while #execute is inside
      # a caller's open transaction, catching the error leaves the transaction
      # aborted and the caller's NEXT statement raises PG::InFailedSqlTransaction
      # — the tool then fails where it previously succeeded, which is precisely
      # the overreach this change must not commit. requires_new: true issues a
      # SAVEPOINT, so the failure rolls back to it and the caller's transaction
      # stays usable.
      #
      # `resource_id` is varchar(36) and 16 of the registry's action names are
      # longer, so the action name lives in metadata (jsonb, unbounded) and the
      # resource pair follows AuditLog.log_system_event's precedent for an event
      # with no natural record: a real type (the tool class, queryable) plus a
      # synthetic id. The breakage set is then:
      #   AuditLog.by_action("mcp.tools.undeclared_action")
      #           .distinct.pluck(Arel.sql("metadata->>'action_name'"))
      #
      # `user: nil` is deliberate — the audit row carries principal SHAPE only.
      def persist_undeclared_action_audit(label, principal)
        return unless account.is_a?(Account) && account.persisted?

        ::ActiveRecord::Base.transaction(requires_new: true) do
          ::AuditLog.create!(
            account: account,
            user: nil,
            action: UNDECLARED_ACTION_AUDIT_ACTION,
            resource_type: telemetry_token(self.class.name),
            resource_id: "undeclared_action",
            source: "system",
            severity: "low",
            risk_level: "low",
            metadata: {
              action_name: label,
              tool_class: telemetry_token(self.class.name),
              principal_kind: principal
            }
          )
        end
      rescue StandardError => e
        Rails.logger.error(
          "[BaseTool] Failed to persist undeclared-action audit: " \
          "action=#{label} tool=#{self.class.name} principal=#{principal} " \
          "error=#{e.class}: #{e.message}"
        )
      end
    end
  end
end
