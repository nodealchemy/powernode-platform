# frozen_string_literal: true

module Ai
  module Engineering
    # The account-wide `release.build_dispatch` FLOOR row: one scope "global",
    # agent-less, user-less `auto_approve` Ai::InterventionPolicy per account.
    #
    # WHY A FLOOR AT ALL. HIER-P2B-ENG makes
    # `system_dispatch_module_build_batch` gate-routed on `release.build_dispatch`.
    # The Release Manager canonical carries its own agent-scoped auto_approve
    # row, but `Ai::InterventionPolicy#agent_matches?` admits an agent-scoped row
    # ONLY for the agent it names, and the principals that legitimately dispatch a
    # build through MCP carry no such row:
    #
    #   * an operator's Claude Code / CLI session — its MCP principal is an
    #     `mcp_client` identity minted by Ai::McpClientIdentityService, never a
    #     seeded canonical; and
    #   * a dev-cell INSTANCE principal (mTLS node cert) — no User and no Agent
    #     at all.
    #
    # With no matching row the category resolves through
    # Ai::InterventionPolicyService#default_policy = "require_approval", so every
    # build dispatch would park. This row is what keeps that verb flowing while
    # `release.promote` / `release.rollback` / `release.deploy_platform` — which
    # have NO floor, deliberately — start requiring approval (operator ruling #3).
    #
    # NOT the push-triggered build path: an automatic build from a platform-push
    # webhook runs through the extension's own trigger service and never reaches
    # the MCP verb, so it is unaffected either way.
    #
    # WHO WRITES IT. This seam only — db/seeds/ai_engineering_agents_seed.rb at
    # seed time (every account), and `rake db:seed:engineering_release_floor` on
    # an ESTABLISHED install. That second door is not optional: `db:seed` is
    # FIRST BOOT ONLY on a deployed hub (rails-start.sh seeds solely while its
    # durable `.db-initialized` marker is absent and runs `db:migrate` alone
    # afterwards), so a policy row added to a seed after first boot never reaches
    # a running install — the gap that left nine seeded governance rows unlanded
    # on this platform's own control plane, measured 2026-08-24. The system
    # extension answers the same problem for its `system.*` sets with
    # System::Governance::PolicyReconciler run from boot; core has no such
    # reconciler, and this seam is deliberately the narrow analogue rather than
    # a second one.
    #
    # ABSENCE-ONLY and non-destructive: it creates the row where the shape is
    # missing and NEVER rewrites, deactivates or deletes one an operator retuned.
    class ReleaseDispatchFloorSeeder
      CATEGORY = "release.build_dispatch"
      VERDICT  = "auto_approve"
      # Below the agent-scoped rows (priority 10) the seed writes. Specificity
      # already ranks an agent row first; the gap states the intent.
      PRIORITY = 0
      CHANNELS = %w[notification].freeze
      # The identity of the floor: what makes a row THE floor rather than an
      # operator's own global row for the category.
      SHAPE = { scope: "global", ai_agent_id: nil, user_id: nil }.freeze
      # The absence-only backfill an ESTABLISHED install runs. Defined in
      # lib/tasks/seed.rake.
      REMEDY_TASK = "rails db:seed:engineering_release_floor"

      # The floor row for an account, or nil. Never creates.
      def self.find_for(account)
        ::Ai::InterventionPolicy.where(account: account, action_category: CATEGORY, **SHAPE).first
      end

      # Create the floor for one account when it is missing. Returns true when a
      # row was written, false when one was already there.
      def self.ensure_for!(account)
        return false if find_for(account)

        ::Ai::InterventionPolicy.create!(
          account: account, action_category: CATEGORY, policy: VERDICT,
          priority: PRIORITY, is_active: true, conditions: {},
          preferred_channels: CHANNELS, **SHAPE
        )
        true
      rescue ActiveRecord::RecordNotUnique
        # Lost a concurrent race; the row exists, which is all this promises.
        false
      end

      # Every account. Returns the number of rows written.
      def self.ensure_all!
        ::Account.find_each.count { |account| ensure_for!(account) }
      end
    end
  end
end
