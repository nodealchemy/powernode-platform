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
  # Until every mutating action is declared and the chokepoint fails CLOSED on
  # undeclared ones, an unreferenced action is still an ungated one — silently.
  # An audit of this file will not reveal that; only the declaration registry's
  # coverage will.
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
    Result = Struct.new(:decision, :deferred_operation, :result, :error, :exception,
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
    def evaluate(action_category:, executor_class:, params: {}, agent: nil,
                 requested_by: nil, source_type: nil, source_id: nil, description: nil,
                 environment: nil, requires_human_session: false, call_origin: nil)
      call_origin = ::Ai::Tools::CallOrigin.validate!(call_origin)
      resolved_environment = ::Ai::EnvironmentResolution.resolve(
        account: @account, params: params, environment: environment
      )
      # Only worth estimating when a plane (and so a ceiling) applies.
      blast_radius = resolved_environment && ::Ai::EnvironmentResolution.blast_radius(account: @account, params: params)
      policy_match = @policy_service.resolve(
        action_category: action_category, agent: agent, user: requested_by,
        environment: resolved_environment, blast_radius: blast_radius
      )

      deferred = create_deferred_operation!(
        action_category: action_category, executor_class: executor_class,
        params: params, agent: agent, requested_by: requested_by,
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
        require_approval_or_proceed(deferred, policy_match[:record], action_category,
                                    escalation: policy_match[:environment_escalation],
                                    blast_radius: policy_match[:blast_radius],
                                    requires_human_session: requires_human_session,
                                    call_origin: call_origin)
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
      Rails.logger.error("[AutonomyGate] evaluate(#{action_category}) failed: #{e.class}: #{e.message}")
      Result.new(decision: :blocked, error: "Gate evaluation failed: #{e.message}", exception: e)
    end

    private

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
    # workflow. The `else` arm is a historical fall-through from when
    # Ai::ApprovalChain lived in the business extension; the chain models are
    # CORE now, so `defined?` is always true and every deployment parks here.
    # The parked request is decidable on every deployment too — the decision
    # side of Ai::Autonomy::ApprovalWorkflowService is not capability-gated
    # (IMP-27e2f8e59ce0). Left in place rather than deleted so the branch's
    # spec history stays legible; do not read it as a live core-mode mode.
    #
    # Without this fork the require_approval path raised NameError on every
    # core-mode evaluation, the rescue caught it, and the gate returned
    # :blocked + 422 — which broke `tasks_controller create`,
    # `sdwan/networks destroy`, and every other AutonomyGate-protected
    # request spec running without business loaded.
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
        Rails.logger.info(
          "[AutonomyGate] require_approval policy in core mode (no Ai::ApprovalChain) — " \
          "auto-proceeding for #{action_category}"
        )
        result_data = deferred.execute_now!
        Result.new(decision: :proceed, deferred_operation: deferred, result: result_data)
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
          # Redacted copy, not the stored one. The operation keeps plaintext in
          # its own params because the executor replays them after approval;
          # request_data exists only to be READ, by an approval audience wider
          # than the permission that authorised the call. This is the single
          # boundary every gated call site crosses, so every producer of
          # secret-bearing params is covered here rather than one at a time.
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
