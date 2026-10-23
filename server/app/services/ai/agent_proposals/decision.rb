# frozen_string_literal: true

module Ai
  module AgentProposals
    # THE funnel for deciding an Ai::AgentProposal. Every door (the REST controller,
    # batch_review, the gateway cascade, and later a chat door) decides through
    # `Decision.call`: this is where the approval hands off (Ai::AgentProposal#approve!)
    # and where a TOOL-DOOR decision (chat) is admitted or refused. A new door adds a
    # caller; it does not add a rule.
    #
    #   Decision.call(proposal, "approved", user, origin: origin, via_agent: agent,
    #                 mcp_session_id: session_id, instruction: "ship it")
    #
    # `origin` is REQUIRED and nil raises: a decision never defaults to an admitted door.
    # Exactly two origins are not tool doors:
    #   REST_SESSION  a person's own session, with a user (the controller, batch_review)
    #   "internal"    a DECLARED in-process caller named by `principal:` (INTERNAL_CALLERS),
    #                 audited as source system (the gitops reconciler's auto-apply)
    # Every other origin is a tool door and goes through the chat rule below. A decision with
    # no person behind it (a gateway chain's timeout_action approve) never reaches here.
    #
    # `decided_by` is the person the decision is attributed to. `via_agent` is the agent
    # that carried the call (REQUIRED on a tool door: no agent, no decision).
    # `mcp_session_id` is the MCP session the call arrived on, resolved by the MCP controller
    # from the caller's OWNED session, never from params. `instruction` is what the user said
    # (verbatim, max 500 chars) and is audited with the decision.
    #
    # THE RULE (one place; a ruling change is an edit to #tool_door_admission only).
    # A tool-door decision (any origin other than the two above) is accepted only when
    # ALL hold:
    #   * it names the agent that carried it;
    #   * the site setting proposals.chat_decisions_enabled is on (default on);
    #   * the proposal_type is in Ai::AgentProposal::CHAT_DECIDABLE_TYPES;
    #   * the decider is a user of the proposal's account;
    #   * AND one of
    #       same_session  the proposal was filed through the calling session, that session
    #                     is live, owned by the deciding user, and the proposal is still
    #                     within its review deadline; or
    #       other_agent   the calling agent is not the proposal's own agent AND the calling
    #                     session is not the one it was filed through.
    # Everything else is refused with a pointer to the app card.
    module Decision
      DECISIONS = %w[approved rejected].freeze
      INSTRUCTION_MAX = 500
      SETTING = "proposals.chat_decisions_enabled"
      SAME_SESSION = "same_session"
      OTHER_AGENT = "other_agent"
      INTERNAL = "internal"
      # The only in-process callers that may decide without a person. Declare here to add one.
      INTERNAL_CALLERS = %w[gitops_reconciler].freeze
      # kind: :rest | :internal | :chat; branch: same_session | other_agent (chat only);
      # source: the AuditLog source for the decision's rows.
      Admission = Struct.new(:kind, :branch, :principal, keyword_init: true) do
        def source = kind == :internal ? "system" : "api"
      end
      APP_CARD = "Decide it in the app instead: Control > Approvals > Proposals."

      # A tool-door decision the rule does not admit.
      class Refused < Ai::AgentProposal::InvalidTransition; end

      module_function

      def call(proposal, decision, decided_by, origin:, principal: nil, via_agent: nil, mcp_session_id: nil,
               instruction: nil)
        unless DECISIONS.include?(decision.to_s)
          raise ArgumentError, "decision must be one of #{DECISIONS.join('|')}, got #{decision.inspect}"
        end

        context = { origin: origin, principal: principal, via_agent: via_agent, mcp_session_id: mcp_session_id,
                    instruction: instruction }
        if decision.to_s == "approved"
          proposal.approve!(decided_by, **context)
        else
          proposal.reject!(decided_by, **context)
        end
        resolve_gateway_requests!(proposal, decision) if tool_door?(origin)
        proposal
      end

      # A tool door is every origin that is not a person's own REST session or a declared
      # internal caller. Fail closed: an unrecognised value is not an admitted door.
      def tool_door?(origin)
        ![ ::Ai::ApprovalDecision::REST_SESSION, INTERNAL ].include?(origin.to_s)
      end

      # Returns an Admission, or raises (ArgumentError for a missing/unknown origin, Refused
      # for a decision the rule does not admit).
      def admit!(proposal, decided_by, origin:, principal: nil, via_agent: nil, mcp_session_id: nil)
        raise ArgumentError, "origin is required to decide a proposal" if origin.blank?

        origin = origin.to_s
        case origin
        when ::Ai::ApprovalDecision::REST_SESSION
          raise Refused, "A person's own session is required: no user is attached to this decision." unless decided_by

          Admission.new(kind: :rest)
        when INTERNAL
          raise Refused, "#{principal.inspect} is not a declared internal decider." unless INTERNAL_CALLERS.include?(principal.to_s)

          Admission.new(kind: :internal, principal: principal.to_s)
        when ::Ai::ApprovalDecision::REST_OTHER
          raise Refused, "Decide this proposal from your own session; impersonation and account-switch sessions cannot."
        else
          unless ::Ai::Tools::CallOrigin::ALL.include?(origin)
            raise ArgumentError, "unknown decision origin #{origin.inspect}"
          end

          branch = tool_door_admission(proposal, decided_by, via_agent, mcp_session_id) ||
                   raise(Refused, "This proposal cannot be decided from chat. #{APP_CARD}")
          Admission.new(kind: :chat, branch: branch)
        end
      end

      def tool_door_admission(proposal, decided_by, via_agent, mcp_session_id)
        return nil unless via_agent # fail closed: a tool door with no agent is not a decider
        return nil unless chat_decisions_enabled?
        return nil unless ::Ai::AgentProposal::CHAT_DECIDABLE_TYPES.include?(proposal.proposal_type)
        return nil unless decided_by && decided_by.account_id == proposal.account_id
        return SAME_SESSION if same_session?(proposal, decided_by, mcp_session_id)
        return OTHER_AGENT if other_agent?(proposal, via_agent, mcp_session_id)

        nil
      end

      def chat_decisions_enabled?
        value = ::SiteSetting.get(SETTING)
        value.nil? ? true : ActiveModel::Type::Boolean.new.cast(value)
      end

      def filed_through?(proposal, mcp_session_id)
        proposal.origin_mcp_session_id.present? && proposal.origin_mcp_session_id.to_s == mcp_session_id.to_s
      end

      def same_session?(proposal, decided_by, mcp_session_id)
        return false unless filed_through?(proposal, mcp_session_id)
        return false if proposal.review_deadline.present? && proposal.review_deadline < Time.current

        session = ::McpSession.live.find_by(id: mcp_session_id)
        session.present? && session.user_id == decided_by.id && session.account_id == proposal.account_id
      end

      def other_agent?(proposal, via_agent, mcp_session_id)
        proposal.ai_agent_id.to_s != via_agent.id.to_s && !filed_through?(proposal, mcp_session_id)
      end

      # An accepted chat decision settles the proposal's gateway ApprovalRequest outright, so
      # the app card does not stay pending beside a proposal that is already decided.
      def resolve_gateway_requests!(proposal, decision)
        ::Ai::ApprovalRequest.for_source(proposal.class.name, proposal.id).pending.find_each do |request|
          decision.to_s == "approved" ? request.approve! : request.reject!
        end
      end
    end
  end
end
