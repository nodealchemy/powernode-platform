# frozen_string_literal: true

module Ai
  module Tools
    module Concerns
      # The claim scope a tool door derives for its caller. Shared so the dev
      # loop (which writes it at claim time) and any tool that must recognise
      # the SAME principal later (LearningTool#reinforce_learning) cannot
      # disagree on who is calling (IMP-8a646a44efca).
      module ClaimantPrincipal
        extend ActiveSupport::Concern

        private

        # The claim scope, written at claim time and re-derived on every later call
        # (reclaim, dev_update_task, dev_complete_task) that has to recognise the
        # SAME principal. It must therefore be a pure function of the principal —
        # never of the loop — because claim and complete are separate tool
        # instances and a loop-dependent answer would strand the claim.
        #
        # An agent principal comes through Ai::AgentToolBridgeService carrying its
        # creator as `user`, so "user present" does not mean "a person is
        # calling". The interactive MCP door carries an `mcp_client` identity when
        # the account has an active AI provider and no agent otherwise, never a
        # seeded canonical, so a NON-mcp_client agent is the agent itself acting and the
        # claim belongs to it (HIER-P2B-ENG: the Platform Developer claims as
        # "agent:<id>", the identity the delegation named — not as its creator).
        def claimant_ref
          if agent.present? && !agent.mcp_client?
            "agent:#{agent.id}"
          elsif user
            "user:#{user.id}"
          elsif agent
            "agent:#{agent.id}"
          elsif node_instance
            # Instance principal (mTLS node cert; no User/Agent) — e.g. a managed
            # dev-cell driving the dev-loop over MCP. Opaque claim-scope string that
            # flows through claim → reclaim → complete like user:/agent:. (BUG-S)
            "instance:#{node_instance.id}"
          end
        end
      end
    end
  end
end
