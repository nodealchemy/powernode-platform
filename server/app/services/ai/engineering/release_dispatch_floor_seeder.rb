# frozen_string_literal: true

module Ai
  module Engineering
    # The account-wide engineering FLOOR rows: for each category in CATEGORIES,
    # one scope "global", agent-less, user-less `auto_approve`
    # Ai::InterventionPolicy per account.
    #
    # WHY A FLOOR AT ALL. HIER-P2B-ENG makes
    # `system_dispatch_module_build_batch` gate-routed on `release.build_dispatch`,
    # `mutate_skill` on `dev.prompt_refine` and `auto_evolve_skill` on
    # `dev.skill_refine`. The owning canonicals carry their own agent-scoped
    # rows (the Release Manager an auto_approve, the Platform Developer and
    # Platform Architect a trust-conditioned PAIR), but
    # `Ai::InterventionPolicy#agent_matches?` admits an agent-scoped row ONLY
    # for the agent it names, and the principals that legitimately call those
    # verbs through MCP carry no such row:
    #
    #   * an operator's Claude Code / CLI session — its MCP principal is an
    #     `mcp_client` identity minted by Ai::McpClientIdentityService, never a
    #     seeded canonical; and
    #   * a dev-cell INSTANCE principal (mTLS node cert) — no User and no Agent
    #     at all.
    #
    # With no matching row the category resolves through
    # Ai::InterventionPolicyService#default_policy = "require_approval", so every
    # build dispatch and every refinement from those principals would park
    # where it previously ran. These rows are what keep those verbs flowing
    # while `release.promote` / `release.rollback` / `release.deploy_platform`
    # — which have NO floor, deliberately — start requiring approval (operator
    # ruling #3; the refine floors are ruling 11c, IMP-a51963f8717f).
    #
    # THE AGENT-SCOPED ROWS OUTRANK IT. Ai::InterventionPolicy#specificity_key
    # ranks a row naming an agent above any global row whatever the priority,
    # so a seeded agent keeps the verdict its own rows state: a supervised
    # Platform Developer still parks a refinement through its require_approval
    # row, a trusted one still proceeds through its conditioned row. The floor
    # only speaks for callers that own no row.
    #
    # WHICH IS MORE CALLERS THAN THE TWO ABOVE — read this before adding a
    # category. `ensure_all!` writes the floor on EVERY account, while the
    # trust-conditioned pairs are seeded only on the "Powernode Admin" account's
    # canonicals (db/seeds/ai_engineering_agents_seed.rb keys them on
    # `engineering_admin_account`), and a scope-"global" row is agent-BINDING:
    # Ai::InterventionPolicyService#resolve admits an agent caller's own rows
    # PLUS the global audience. So "owns no row" covers any agent in the account
    # without one for the category — a per-account clone of a canonical
    # included. Concretely, the two refine floors auto-approve the system
    # extension's governance-gap materialisation lane (it gates a skill binding
    # on dev.skill_refine and a prompt refinement on dev.prompt_refine) at EVERY
    # trust tier on any account but the admin one, where before them it met the
    # require_approval default and parked. That widening is deliberate; the
    # per-account agent-scoped row an operator writes to restore the park is in
    # docs/concepts/platform-engineering-agents.md. A category added here
    # widens every lane that gates on it, not only the verb you added it for.
    #
    # NOT the push-triggered build path: an automatic build from a platform-push
    # webhook runs through the extension's own trigger service and never reaches
    # the MCP verb, so it is unaffected either way. And not the Skills UI: it
    # uses the REST twins, which do not meet this gate.
    #
    # WHO WRITES IT. This seam only — db/seeds/ai_engineering_agents_seed.rb at
    # seed time (every account), `rake db:seed:engineering_floors` on an
    # ESTABLISHED install, and any boot-time governance reconcile an extension
    # wires that calls `ensure_all!` (behind `defined?`, so the two trees may
    # skew). The extra doors are not optional: `db:seed` is FIRST BOOT ONLY on a
    # deployed hub (rails-start.sh seeds solely while its durable
    # `.db-initialized` marker is absent and runs `db:migrate` alone
    # afterwards), so a policy row added to a seed after first boot never reaches
    # a running install — the gap that left nine seeded governance rows unlanded
    # on this platform's own control plane, measured 2026-08-24. The system
    # extension answers the same problem for its `system.*` sets with
    # System::Governance::PolicyReconciler run from boot; core has no such
    # reconciler, and this seam is deliberately the narrow analogue rather than
    # a second one — which is why a boot hook calls THIS rather than growing
    # a reconciler of its own. Adding a category here is therefore enough for
    # it to reach every install on its next boot or reconcile.
    #
    # ABSENCE-ONLY and non-destructive, PER CATEGORY: it creates a row where the
    # shape is missing and NEVER rewrites, deactivates or deletes one an operator
    # retuned. An install that carries the older single floor gains only the
    # rows it lacks.
    #
    # The class keeps the name it shipped under: the extension's reconcile doors
    # probe it by name behind `defined?`, and an older extension tree must keep
    # finding it.
    class ReleaseDispatchFloorSeeder
      CATEGORIES = %w[release.build_dispatch dev.prompt_refine dev.skill_refine].freeze
      VERDICT    = "auto_approve"
      # Below the agent-scoped rows (priority 10 and 20) the seed writes.
      # Specificity already ranks an agent row first; the gap states the intent.
      PRIORITY = 0
      CHANNELS = %w[notification].freeze
      # The identity of a floor: what makes a row THE floor for its category
      # rather than an operator's own global row for it.
      SHAPE = { scope: "global", ai_agent_id: nil, user_id: nil }.freeze
      # The absence-only backfill an ESTABLISHED install runs. Defined in
      # lib/tasks/seed.rake (`engineering_release_floor` is its alias).
      REMEDY_TASK = "rails db:seed:engineering_floors"

      # The floor row for one account and category, or nil. Never creates.
      def self.find_for(account, category)
        ::Ai::InterventionPolicy.where(account: account, action_category: category, **SHAPE).first
      end

      # Create the floors an account is missing. Returns the number of rows
      # written (0 when every category already has one).
      def self.ensure_for!(account)
        CATEGORIES.count { |category| ensure_category_for!(account, category) }
      end

      # Every account. Returns the number of rows written.
      def self.ensure_all!
        ::Account.find_each.sum { |account| ensure_for!(account) }
      end

      # Create the floor for one account and category when it is missing.
      # Returns true when a row was written, false when one was already there.
      def self.ensure_category_for!(account, category)
        return false if find_for(account, category)

        ::Ai::InterventionPolicy.create!(
          account: account, action_category: category, policy: VERDICT,
          priority: PRIORITY, is_active: true, conditions: {},
          preferred_channels: CHANNELS, **SHAPE
        )
        true
      rescue ActiveRecord::RecordNotUnique
        # INERT TODAY, deliberately kept. `ai_intervention_policies` carries NO
        # unique index on the floor shape (db/schema.rb lists only the
        # non-unique account/category, account/scope and account/user/agent
        # indexes), so a genuine race between two doors — a boot reconcile and
        # `rake db:seed:engineering_floors` — does NOT raise here: it writes a
        # SECOND floor row, after which #find_for returns an arbitrary one of
        # them. Both carry the same verdict, so resolution is unaffected; what
        # suffers is an operator retuning one copy and not the other. Closing it
        # properly needs a partial unique index on (account_id,
        # action_category) WHERE scope = 'global' AND ai_agent_id IS NULL AND
        # user_id IS NULL, which is a migration and out of this seam's scope.
        # This clause is what makes the guard correct the moment that index
        # lands; until then read it as "already there", not as a race guard.
        false
      end
      private_class_method :ensure_category_for!
    end
  end
end
