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
    def evaluate(action_category:, executor_class:, params: {}, agent: nil,
                 requested_by: nil, source_type: nil, source_id: nil, description: nil)
      policy_match = @policy_service.resolve(
        action_category: action_category, agent: agent, user: requested_by
      )

      deferred = create_deferred_operation!(
        action_category: action_category, executor_class: executor_class,
        params: params, agent: agent, requested_by: requested_by,
        source_type: source_type, source_id: source_id, description: description
      )

      case policy_match[:policy]
      when "auto_approve", "notify_and_proceed"
        result_data = deferred.execute_now!
        Result.new(decision: :proceed, deferred_operation: deferred, result: result_data)
      when "require_approval"
        require_approval_or_proceed(deferred, policy_match[:record], action_category)
      when "block", "silent"
        deferred.update!(status: "rejected", error_message: "Blocked by policy")
        Result.new(decision: :blocked, deferred_operation: deferred,
                   error: "Action #{action_category} is blocked by policy")
      else
        # Unknown policy — fail safe to require_approval
        Rails.logger.warn("[AutonomyGate] Unknown policy '#{policy_match[:policy]}' for #{action_category}, defaulting to require_approval")
        require_approval_or_proceed(deferred, policy_match[:record], action_category)
      end
    rescue StandardError => e
      Rails.logger.error("[AutonomyGate] evaluate(#{action_category}) failed: #{e.class}: #{e.message}")
      Result.new(decision: :blocked, error: "Gate evaluation failed: #{e.message}", exception: e)
    end

    private

    def create_deferred_operation!(action_category:, executor_class:, params:, agent:,
                                   requested_by:, source_type:, source_id:, description:)
      ::Ai::DeferredOperation.create!(
        account: @account,
        action_category: action_category,
        executor_class: executor_class,
        params: params || {},
        ai_agent: agent,
        requested_by: requested_by,
        source_type: source_type,
        source_id: source_id,
        description: description
      )
    end

    # Bridges the require_approval policy decision to either the approval-chain
    # workflow (when Ai::ApprovalChain is loaded — the business extension owns
    # the chain model) or a fall-through auto-proceed in core mode (single-
    # operator self-hosted: the requester IS the approver, no separate
    # approval infrastructure to defer to).
    #
    # Without this fork the require_approval path raised NameError on every
    # core-mode evaluation, the rescue caught it, and the gate returned
    # :blocked + 422 — which broke `tasks_controller create`,
    # `sdwan/networks destroy`, and every other AutonomyGate-protected
    # request spec running without business loaded.
    def require_approval_or_proceed(deferred, policy_record, action_category)
      if defined?(::Ai::ApprovalChain)
        request = create_approval_request!(deferred, policy_record)
        deferred.update!(approval_request: request)
        Result.new(decision: :pending, deferred_operation: deferred)
      else
        Rails.logger.info(
          "[AutonomyGate] require_approval policy in core mode (no Ai::ApprovalChain) — " \
          "auto-proceeding for #{action_category}"
        )
        result_data = deferred.execute_now!
        Result.new(decision: :proceed, deferred_operation: deferred, result: result_data)
      end
    end

    def create_approval_request!(deferred, policy_record)
      chain = resolve_chain(deferred, policy_record)
      chain.create_request!(
        source_type: "Ai::DeferredOperation",
        source_id: deferred.id,
        description: deferred.description.presence || deferred.action_category,
        request_data: {
          action_category: deferred.action_category,
          executor_class: deferred.executor_class,
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
        },
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
