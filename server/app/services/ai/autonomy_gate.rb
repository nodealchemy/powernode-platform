# frozen_string_literal: true

module Ai
  # The policy DECISION function for a mutating operation that might require
  # human approval. Read the next paragraph before trusting the word "central".
  #
  # THIS CLASS IS NOT A CHOKE POINT, and calling itself one is part of why a
  # coverage gap went unnoticed for so long (IMP-439d31353f9b). It decides; it
  # does not intercept. Reaching it is a per-call-site obligation, and coverage
  # is therefore whatever the call sites happen to be: SdwanTool carries 31
  # hand-placed `evaluate` calls while SystemFleetTool carried none across
  # ~4700 lines, and nothing in this file could tell you that.
  #
  # The actual chokepoint is Ai::Tools::BaseTool#execute, which every tool call
  # passes through — including the seven call sites that construct a tool and
  # call `.execute` directly, bypassing McpPlatformToolRegistrar. It already
  # hosts one control hoisted there for exactly this reason
  # (enforce_instance_deny_overlay!, moved by IMP-0e6b216de843 after
  # per-call-site coverage failed at depth) and now consults `declare_action`
  # declarations to decide whether to route a call through this gate.
  #
  # The chokepoint fails CLOSED on undeclared actions (APO-1e): an action with
  # no declaration is refused, never run. A DECLARED action still reaches this
  # gate only when its declaration wires it (action_category, executor_class,
  # gate_context, on_proceed); a `mutating:`-only declaration runs ungated. An
  # audit of this file will not reveal which; only the declarations will.
  #
  # Callers dispatch on the returned `decision`:
  #
  #   :proceed  → executor ran synchronously; result is in `result.result`
  #   :pending  → ApprovalRequest created; caller should return HTTP 202
  #   :blocked  → policy denied the action; caller should return 422
  #
  # The gate creates a `Ai::DeferredOperation` row in every case (audit trail).
  # Auto-approved operations execute immediately via `DeferredOperation#execute_now!`.
  # Pending operations resume via the worker job after the ApprovalRequest
  # completes (see `Ai::ApprovalRequest#notify_source_of_decision`).
  class AutonomyGate
    # `exception` carries the error the rescue below swallowed, so a caller can
    # tell a POLICY block from an executor that raised (IMP-1836bb0021b1).
    # Additive and nil on every other branch: nothing that reads :decision or
    # :error changes behaviour, and the rescue keeps returning :blocked exactly
    # as before — this only stops the cause from being unrecoverable. The one
    # consumer today is Ai::GatedActions#gate_update!, which renders an
    # ActiveRecord::RecordInvalid as field-level errors instead of the generic
    # "Gate evaluation failed" 422 that loses them.
    # `promotion_grant` is the Ai::PromotionGrant a :proceed ran under in
    # place of parking; nil on every other path.
    Result = Struct.new(:decision, :deferred_operation, :result, :error, :exception, :promotion_grant,
                        keyword_init: true) do
      def proceed?; decision == :proceed; end
      def pending?; decision == :pending; end
      def blocked?; decision == :blocked; end
      def approval_request; deferred_operation&.approval_request; end
    end

    DEFAULT_APPROVAL_TIMEOUT_HOURS = 4

    def self.evaluate(**kwargs)
      new(account: kwargs.fetch(:account)).evaluate(**kwargs.except(:account))
    end

    def initialize(account:)
      @account = account
      @policy_service = ::Ai::InterventionPolicyService.new(account: account)
    end

    # @param action_category [String] e.g. "sdwan.peer_delete", "system.task.terminate"
    # @param executor_class  [String] fully-qualified class name implementing
    #                                  `self.execute(params, deferred_operation:)`
    # @param params          [Hash]   serializable params passed to executor
    # @param agent           [Ai::Agent, nil] when action is agent-initiated
    # @param requested_by    [User, nil]      when action is user-initiated
    # @param source_type     [String, nil]    polymorphic source for cross-ref
    # @param source_id       [String, nil]
    # @param description     [String, nil]    human-readable summary for the UI
    # @param environment     [Ai::Environment, String, nil] the plane the
    #                        operation acts on; resolved from `params` through
    #                        Ai::EnvironmentResolution when not given. The
    #                        resolved environment can only ESCALATE the verdict
    #                        (Ai::EnvironmentPolicyOverlay), never relax it.
    # @param requires_human_session [Boolean] a human-only tool action (MCP
    #                        identity plan R2). It parks for a person's own
    #                        session whatever the policy says: an auto_approve
    #                        or notify_and_proceed verdict becomes
    #                        require_approval, and a block stays a block. The
    #                        request it opens carries the flag that the
    #                        decision doors and the replay read.
    # @param call_origin     [String, nil] the tool door the call came through
    #                        (Ai::Tools::CallOrigin). The request it opens is
    #                        marked with it, so its requester never decides it
    #                        through a tool door (MCP identity plan D1, guard a).
    #                        nil for a call from a person's own session.
    # @param grant_subject   [Hash, nil] what the call acts on, for a promotion
    #                        grant ({ module_id:, version_id: }). Built by the
    #                        verb's gate context from rows it resolved, never
    #                        from caller params. nil ⇒ no grant can apply.
    def evaluate(action_category:, executor_class:, params: {}, agent: nil,
                 requested_by: nil, source_type: nil, source_id: nil, description: nil,
                 environment: nil, requires_human_session: false, call_origin: nil, agent_initiated: false,
                 grant_subject: nil)
      call_origin = ::Ai::Tools::CallOrigin.validate!(call_origin)
      resolved_environment = ::Ai::EnvironmentResolution.resolve(
        account: @account, params: params, environment: environment
      )
      # Only worth estimating when a plane (and so a ceiling) applies.
      blast_radius = resolved_environment && ::Ai::EnvironmentResolution.blast_radius(account: @account, params: params)
      # `agent_initiated` (MCP identity plan #5): a machine's call resolves in
      # the agent audience even when it carries no agent (BaseTool#machine_call?).
      policy_match = @policy_service.resolve(
        action_category: action_category, agent: agent, user: requested_by,
        environment: resolved_environment, blast_radius: blast_radius, agent_initiated: agent_initiated
      )

      deferred = create_deferred_operation!(
        action_category: action_category, executor_class: executor_class,
        params: with_default_principal(params, agent: agent, requested_by: requested_by), agent: agent, requested_by: requested_by,
        source_type: source_type, source_id: source_id, description: description,
        environment: resolved_environment
      )

      policy = policy_match[:policy]
      # No policy row may proceed a human-only action. Proceeding would run it
      # with no person confirming it, which is exactly what R2 forbids.
      policy = "require_approval" if requires_human_session && %w[auto_approve notify_and_proceed].include?(policy)

      case policy
      when "auto_approve", "notify_and_proceed"
        result_data = deferred.execute_now!
        Result.new(decision: :proceed, deferred_operation: deferred, result: result_data)
      when "require_approval"
        # THE one place a promotion grant acts: a verdict that would PARK
        # (a policy row, the unmatched default, or an environment escalation)
        # proceeds instead when an active grant matches on every axis. Only
        # this arm: block/silent below and the unknown-verb arm never consult one.
        grant = consume_promotion_grant(deferred, action_category: action_category, agent: agent,
                                                  requires_human_session: requires_human_session,
                                                  grant_subject: grant_subject, requested_by: requested_by,
                                                  call_origin: call_origin)
        if grant
          result_data = deferred.execute_now!
          Result.new(decision: :proceed, deferred_operation: deferred, result: result_data, promotion_grant: grant)
        else
          require_approval_or_proceed(deferred, policy_match[:record], action_category,
                                      escalation: policy_match[:environment_escalation],
                                      blast_radius: policy_match[:blast_radius],
                                      requires_human_session: requires_human_session,
                                      call_origin: call_origin)
        end
      when "block", "silent"
        deferred.update!(status: "rejected", error_message: "Blocked by policy")
        Result.new(decision: :blocked, deferred_operation: deferred,
                   error: "Action #{action_category} is blocked by policy")
      else
        # Unknown policy — fail safe to require_approval
        Rails.logger.warn("[AutonomyGate] Unknown policy '#{policy_match[:policy]}' for #{action_category}, defaulting to require_approval")
        require_approval_or_proceed(deferred, policy_match[:record], action_category,
                                    escalation: policy_match[:environment_escalation],
                                    blast_radius: policy_match[:blast_radius],
                                    requires_human_session: requires_human_session,
                                    call_origin: call_origin)
      end
    rescue StandardError => e
      Rails.logger.error("[AutonomyGate] evaluate(#{action_category}) failed: #{e.class}: " \
                         "#{::Ai::SensitiveParams.filter_text(e.message)}")
      Result.new(decision: :blocked, error: "Gate evaluation failed: #{::Ai::SensitiveParams.filter_text(e.message)}", exception: e)
    end

    private

    # An Ai::PromotionGrant standing in for a person's approval, or nil (the
    # operation then parks exactly as it would have). A grant never applies to
    #   * a call with no agent, or no subject from the verb's gate context;
    #   * a category off Ai::PromotionGrant::CATEGORIES, or no resolved plane;
    #   * a human-only call (requires_human_session), whatever else holds;
    #   * an account under the kill switch (emergency halt), read fresh;
    #   * a request that would need a person's own session for any reason
    #     OTHER than its plane being protected: the account's own mark, a
    #     destructive tool call, a category on the operator's list
    #     (Ai::Approvals::HumanSessionPolicy). The protected plane is the one
    #     reason a grant answers, because the grant is itself a person's
    #     own-session decision about exactly that plane.
    # Consumption is atomic (Ai::PromotionGrants::Ledger.consume!).
    def consume_promotion_grant(deferred, action_category:, agent:, requires_human_session:, grant_subject:,
                                requested_by: nil, call_origin: nil)
      return nil if agent.nil? || grant_subject.blank? || requires_human_session
      return nil unless ::Ai::PromotionGrant::CATEGORIES.include?(action_category.to_s)
      return nil if deferred.environment.nil?
      return nil if ::Ai::Autonomy::KillSwitchService.halted_now?(@account.id)

      probe = { action_category: deferred.action_category, params: ::Ai::SensitiveParams.filter(deferred.params) }
      return nil if ::Ai::Approvals::HumanSessionPolicy.required_beyond_protected_environment?(
        account_id: @account.id, request_data: probe
      )

      ::Ai::PromotionGrants::Ledger.consume!(
        account: @account, agent: agent, action_category: action_category, environment: deferred.environment,
        subject: grant_subject, deferred_operation: deferred,
        # Who drove the call: the person (if any), the door, and the park
        # principal the operation was stamped with.
        driver: requested_by, call_origin: call_origin,
        principal: deferred.params.is_a?(::Hash) ? deferred.params[::Ai::Approvals::ParkPrincipal::KEY] : nil
      )
    end

    # Every park records WHO asked (Ai::Approvals::ParkPrincipal), including the
    # REST controllers and services that call the gate with only
    # requested_by/agent. A principal the caller already stamped (a tool, a
    # skill executor) is kept as-is; with no user and no agent there is nothing
    # to derive from, so the params are left alone.
    #
    # TRUST: a `principal` already in the params is believed. That is sound
    # because only server-side code builds gate params: tools and skill
    # executors stamp their own, and the REST controllers pass explicit or
    # nested values, never the request's top level. A new caller that forwards
    # raw request params into this gate would let a client name its own
    # principal — don't (pinned by peers_destroy_principal_spec).
    def with_default_principal(params, agent:, requested_by:)
      return params if requested_by.nil? && agent.nil?

      raw = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params
      return params unless raw.is_a?(::Hash)
      return params if raw.any? { |key, value| key.to_s == ::Ai::Approvals::ParkPrincipal::KEY && stamped_principal?(value) }

      ::Ai::Approvals::ParkPrincipal.stamp(raw, ::Ai::Approvals::ParkPrincipal.for_session(user: requested_by, agent: agent))
    end

    # A caller-stamped principal counts only when it names a kind: a blank value,
    # or a hash whose kind is blank, would otherwise park unattributed.
    def stamped_principal?(value)
      return false if value.blank?
      return true unless value.is_a?(::Hash)

      value.any? { |key, kind| key.to_s == "kind" && kind.present? }
    end

    def create_deferred_operation!(action_category:, executor_class:, params:, agent:,
                                   requested_by:, source_type:, source_id:, description:,
                                   environment: nil)
      ::Ai::DeferredOperation.create!(
        account: @account,
        action_category: action_category,
        executor_class: executor_class,
        params: params || {},
        ai_agent: agent,
        requested_by: requested_by,
        source_type: source_type,
        source_id: source_id,
        description: description,
        environment: environment
      )
    end

    # Bridges the require_approval policy decision to the approval-chain
    # workflow. The `elsif`/`else` arms are a historical fall-through from
    # when Ai::ApprovalChain lived in the business extension; the chain
    # models are CORE now, so `defined?` is always true and every deployment
    # parks here. The parked request is decidable on every deployment too —
    # the decision side of Ai::Autonomy::ApprovalWorkflowService is not
    # capability-gated (IMP-27e2f8e59ce0). Left in place rather than deleted
    # so the branch's spec history stays legible; do not read either as a
    # live core-mode path.
    #
    # Without this fork the require_approval path raised NameError on every
    # core-mode evaluation, the rescue caught it, and the gate returned
    # :blocked + 422 — which broke `tasks_controller create`,
    # `sdwan/networks destroy`, and every other AutonomyGate-protected
    # request spec running without business loaded.
    #
    # IMP-c16864f5a1cd — the final `else` used to auto-proceed the action
    # when Ai::ApprovalChain was undefined: exactly the "core mode fails
    # open on a missing policy" shape the operator ruled must never happen.
    # It never actually fired (verified: the comment above, a static check of
    # config for any conditional autoload/eager_load exclusion of
    # approval_chain.rb, an empirical `defined?` check, an executed spec
    # against a real gated call site, and two further probes closing the
    # only shapes that could plausibly have made this branch live: `defined?`
    # reports "constant" for a merely PENDING Zeitwerk autoload — a
    # lazily-loading env before first reference does NOT read as undefined —
    # and it continues to report "constant" even after that autoload's file
    # has RAISED, so a load-time failure in approval_chain.rb does not fall
    # into this branch either. The only way in is Zeitwerk never registering
    # the constant at all), but a dead branch that still auto-proceeds is a
    # live trap for whoever next moves ApprovalChain out of core or copies
    # this pattern elsewhere. Hardened to fail CLOSED instead, in the same
    # shape the `requires_human_session` arm above it already uses. Do NOT
    # restore the auto-proceed as a convenience if this branch is ever
    # observed firing — that is precisely the condition it exists to refuse.
    def require_approval_or_proceed(deferred, policy_record, action_category, escalation: nil, blast_radius: nil,
                                    requires_human_session: false, call_origin: nil)
      if defined?(::Ai::ApprovalChain)
        request = create_approval_request!(deferred, policy_record, escalation: escalation, blast_radius: blast_radius,
                                           requires_human_session: requires_human_session, call_origin: call_origin)
        deferred.update!(approval_request: request)
        Result.new(decision: :pending, deferred_operation: deferred)
      elsif requires_human_session
        # Nothing to park on means nothing a person could confirm, so refuse.
        # Never take the auto-proceed arm below.
        deferred.update!(status: "rejected", error_message: "No approval chain to park a human-only action on")
        Result.new(decision: :blocked, deferred_operation: deferred,
                   error: "Action #{action_category} needs a person's confirmation and cannot be parked here")
      else
        Rails.logger.error(
          "[AutonomyGate] require_approval policy with no Ai::ApprovalChain available — " \
          "this branch is expected to be unreachable on every real deployment " \
          "(IMP-c16864f5a1cd); refusing rather than auto-proceeding for #{action_category}"
        )
        deferred.update!(status: "rejected", error_message: "No approval chain available to park this action on")
        Result.new(decision: :blocked, deferred_operation: deferred,
                   error: "Action #{action_category} requires approval but no approval chain is available")
      end
    end

    def create_approval_request!(deferred, policy_record, escalation: nil, blast_radius: nil, requires_human_session: false,
                                 call_origin: nil)
      chain = resolve_chain(deferred, policy_record)
      environment = deferred.environment
      chain.create_request!(
        source_type: "Ai::DeferredOperation",
        source_id: deferred.id,
        description: deferred.description.presence || deferred.action_category,
        request_data: {
          action_category: deferred.action_category,
          executor_class: deferred.executor_class,
          # The plane and, when the overlay parked this, WHY — so the card says
          # "parked because prod is protected" rather than just "parked".
          environment: environment && {
            id: environment.id, slug: environment.slug, is_protected: environment.protected?
          },
          environment_escalation: escalation,
          blast_radius: blast_radius,
          # Redacted copy. The operation's own params are redacted too now
          # (Ai::DeferredOperation seals the original for the executor replay),
          # but request_data is still built here from the masked reader so the
          # two copies can never drift. This is the single boundary every gated
          # call site crosses, so every producer of secret-bearing params is
          # covered here rather than one at a time.
          params: ::Ai::SensitiveParams.filter(deferred.params),
          agent_id: deferred.ai_agent_id,
          agent_name: deferred.ai_agent&.name,
          requested_by_id: deferred.requested_by_id,
          source_type: deferred.source_type,
          source_id: deferred.source_id
          # Only when set, so every other request keeps its exact shape. Read by
          # Ai::ApprovalRequest#requires_human_session? and #tool_door_request?.
        }.merge(requires_human_session ? { requires_human_session: true } : {})
         .merge(call_origin ? { call_origin: call_origin } : {}),
        requested_by: deferred.requested_by
      )
    end

    # Use the policy's assigned chain when set, otherwise a per-agent default
    # chain ("<Agent Name> Actions" or "Manual Operations").
    def resolve_chain(deferred, policy_record)
      return policy_record.approval_chain if policy_record&.approval_chain_id

      chain_name = if deferred.ai_agent
        "#{deferred.ai_agent.name} Actions"
      else
        "Manual Operations"
      end

      ::Ai::ApprovalChain.find_or_strengthen!(
        account: @account, name: chain_name, step_name: "Operator Approval",
        approvers: [ "*" ], required_approvals: 1,
        defaults: {
          trigger_type: "autonomy_action", status: "active", is_sequential: true,
          timeout_hours: DEFAULT_APPROVAL_TIMEOUT_HOURS, timeout_action: "reject"
        }
      )
    end
  end
end
