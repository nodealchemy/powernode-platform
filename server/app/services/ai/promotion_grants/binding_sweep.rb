# frozen_string_literal: true

module Ai
  module PromotionGrants
    # Revokes every still-active promotion grant whose binding target has
    # ENDED, each with its audit row (Ledger.revoke_bound!). The gate already
    # refuses a bound grant whose target is not live (Binding.matches?), so
    # this is the record and the cleanup, not the guard.
    #
    # An MCP session has ended when its row is gone, or it is neither live nor
    # reactivatable: expired, past its TTL, idle, or revoked past the
    # reconnect grace period. A session revoked within the grace (a server
    # restart dropped its stream) may come back, so its grants are only
    # paused, never spent, until it does or the grace runs out.
    module BindingSweep
      module_function

      # @return [Hash] counts by reason
      def sweep!
        { ::Ai::PromotionGrants::Ledger::SESSION_ENDED => sweep_sessions! }
      end

      def sweep_sessions!
        kind = ::Ai::PromotionGrant::BINDING_MCP_SESSION
        ids = bound_target_ids(kind)
        return 0 if ids.empty?

        sessions = ::McpSession.where(id: ids).index_by { |session| session.id.to_s }
        ended = ids.reject do |id|
          session = sessions[id]
          session && (session.live? || session.reactivatable?)
        end
        ::Ai::PromotionGrants::Ledger.revoke_bound!(kind: kind, ids: ended, reason: ::Ai::PromotionGrants::Ledger::SESSION_ENDED)
      end

      def bound_target_ids(kind)
        ::Ai::PromotionGrant.unrevoked.unexpired.where(binding_kind: kind).distinct.pluck(:binding_id).map(&:to_s)
      end
    end
  end
end
