# frozen_string_literal: true

module Ai
  module AgentProposals
    # One AuditLog row per proposal transition: ai.proposal.{approved,rejected,
    # withdrawn,expired,implemented,handed_off,handoff_abandoned}. The actor is the reviewer (nil
    # for the expiry sweep, a gateway lapse and a completion that no person
    # reported), the resource is the proposal, and the details carry what the
    # transition produced (the handoff, the implemented ref).
    #
    # REQUIRED, not best-effort, and always called inside the transition's own
    # transaction: a transition that cannot be audited does not happen.
    module Audit
      TRANSITIONS = %w[approved rejected withdrawn expired implemented handed_off handoff_abandoned].freeze

      module_function

      def action_for(transition)
        "ai.proposal.#{transition}"
      end

      def record!(proposal, transition, actor:, source:, details: {})
        raise ArgumentError, "unknown proposal transition #{transition.inspect}" unless TRANSITIONS.include?(transition)

        payload = base_details(proposal).merge(details.to_h.stringify_keys).compact
        ::AuditLog.create!(
          account_id: proposal.account_id, user: actor, action: action_for(transition), source: source,
          resource_type: proposal.class.name, resource_id: proposal.id,
          severity: "low", risk_level: "low",
          new_values: payload, metadata: payload
        )
      end

      def base_details(proposal)
        {
          "proposal_id" => proposal.id,
          "proposal_type" => proposal.proposal_type,
          "status" => proposal.status,
          "handoff_kind" => proposal.handoff_kind,
          "handoff_id" => proposal.handoff_id,
          "implemented_ref" => proposal.implemented_ref
        }
      end
    end
  end
end
