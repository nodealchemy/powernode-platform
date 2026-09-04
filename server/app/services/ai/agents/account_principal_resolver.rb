# frozen_string_literal: true

module Ai
  module Agents
    # THE ONE resolver of "which Ai::Agent row ACTS for canonical X in account Y"
    # (HIER-P2I, proposal §5 ruling 8).
    #
    # A GLOBAL canonical agent (account_id NULL — GloballyScopable#global?) is a
    # TEMPLATE, never an executing principal: Ai::Tools::BaseTool refuses it at
    # the tool seam, because a principal with no account has no account role to
    # bound it. What executes is the account's CLONE of the canonical, minted
    # here on first use through the HIER-P1 canonical rule — the same path
    # Ai::Tools::AgentManagementTool#clone_canonical_agent takes: `clone_to_account`
    # (cloned_from_id / source_version / source_snapshot), a creator and provider
    # from THIS account, and an Ai::Agents::HierarchyWriter `canonical_clone`
    # lineage edge to the canonical.
    #
    # ONE copy of the rule. HIER-P2B-ENG wrote it for one consumer
    # (Ai::DevLoop::CampaignDriver#default_platform_agent); this class is that
    # helper extracted, and every seeded canonical that acts on its own —
    # the fleet tick and its per-owner gates (System::Governance::AgentResolver),
    # the CVE responder, the adaptation gate, the concierge doors — resolves
    # through it. Do not write a second copy.
    #
    # WHAT FOLLOWS THE CLONE. The account had rows keyed on the CANONICAL's id
    # before any clone existed, and the gate reads them by the ACTING agent's id
    # (System::Fleet::FleetAutonomyService#permitted_actions is literally
    # `ai_agent_id: agent.id`), so a clone without them would leave every lane
    # GATE_POLICY_MISSING until the next boot-time reconcile. The account's
    # agent-scoped Ai::InterventionPolicy rows are therefore RE-HOMED onto the
    # clone (the operator's tuned verbs travel with them), and the canonical's
    # skill bindings, trust score and the delegation policy that governed it
    # for this account are COPIED — a clone without them would be a weaker
    # agent than the template it stands in for.
    #
    # The re-home runs on EVERY resolution, not only at mint. This seam is not
    # the only way an account acquires a clone: Ai::Tools::AgentManagementTool
    # #clone_canonical_agent and the REST clone door
    # (Api::V1::Ai::AgentsController#clone, GloballyScopedContent) both mint one
    # with provenance and NOTHING else, and an account that cloned through
    # either would otherwise resolve to a principal whose policy rows are still
    # on the canonical — precisely the GATE_POLICY_MISSING state above, and one
    # System::Governance::PolicyReconciler cannot repair (it maps the CLONE's
    # id, so a row still on the canonical is not a re-homable former owner; it
    # would create fresh declared defaults on the clone and orphan the
    # operator's tuned row). #follow_on_moves! is therefore idempotent and
    # costs one indexed EXISTS when there is nothing to move. The COPIES stay
    # mint-only on purpose: `find_or_create_by!` on every resolution would
    # resurrect a skill binding an operator deliberately removed from their
    # own clone.
    #
    # IDENTITY. Ai::Agent partitions name/slug uniqueness by account, so the
    # clone keeps the canonical's name and slug whenever the account has not
    # already used them: every `Ai::Agent.resolve_for(name:)` site then finds
    # the clone override-first (`account_override_first`) with no second lookup
    # rule, and the "(Copy)" suffix `clone_to_account` mints for tenant
    # customisation does not leak into the fleet's own principals.
    #
    # NOT a per-request cache and NOT a bypass: `acting` answers with the
    # canonical itself when no clone can be minted (an account with no user to
    # own one, or no active provider to run one on — a canonical seeded before
    # any provider existed carries none to fall back to, IMP-6cda93db7f31), and
    # the tool seam then refuses that canonical BY NAME — the failure is
    # visible, never silently widened.
    class AccountPrincipalResolver
      SEAM = name.freeze
      SPAWN_REASON = "canonical_clone"

      # Registered audit action (AuditActions::AI_AGENT_ACTIONS); the metadata
      # names this seam and the event, as HierarchyWriter does.
      AUDIT_ACTION = "ai.agents.update"

      # Trust-score columns that are a per-agent HISTORY rather than a
      # standing, and so start fresh on the clone.
      TRUST_SCORE_HISTORY = %w[id agent_id account_id created_at updated_at
                               evaluation_history evaluation_count last_evaluated_at].freeze

      class << self
        # The account's executing principal for a canonical named by slug (or
        # source_key): its own row for that key, else a clone minted now. Nil
        # when no canonical carries the key, or when the account has no user
        # to own a clone.
        def for(canonical_slug:, account:, user: nil)
          new(account: account, user: user).for(canonical_slug: canonical_slug)
        end

        # An already-resolved row (Ai::Agent.resolve_for and friends may hand
        # back the GLOBAL canonical) mapped to the account's executing
        # principal. Account rows pass through untouched; a canonical is
        # swapped for the account's clone of it, minted on first use.
        def acting(agent, account:, user: nil)
          new(account: account, user: user).acting(agent)
        end

        # The account's executing concierge: the read-only
        # Ai::Agent.resolve_concierge_for answer, mapped through #acting.
        def concierge_for(account, user: nil)
          return nil if account.nil?

          acting(::Ai::Agent.resolve_concierge_for(account.id), account: account, user: user)
        end

        # READ-ONLY twin of `acting`: the account's existing clone of a global
        # canonical, or nil — never minting. A drift report (a health check, a
        # CI assertion, the governance rake's read-only verb) resolves through
        # this so that asking "which row WOULD act" materialises nothing;
        # an account-scoped agent is returned as itself.
        def existing(agent, account:)
          new(account: account).existing(agent)
        end
      end

      attr_reader :account, :user

      # THE provider rule for anything that has to run a canonical's pinned
      # model somewhere else (the account clone here, the seeds' owner
      # back-fill in db/seeds/concerns/canonical_agent_owner.rb): an ACTIVE
      # provider of the pin's family from `providers`; else `preferred` when it
      # agrees with the pin (that is what the canonical itself runs on, active
      # or not); else any provider of the family; else — no provider of that
      # family at all — `preferred`, then the first active provider, flagged
      # incompatible so the caller can drop the pin or leave the row
      # provider-less. Returns [provider or nil, compatible?]. A pin no family
      # claims is compatible with any provider.
      def self.provider_for_pin(pinned_model:, providers:, preferred: nil)
        family = ::Ai::Agent.provider_family_for(pinned_model) if pinned_model.present?
        list = providers.respond_to?(:to_a) ? providers.to_a : Array(providers)
        return [ list.find(&:is_active) || preferred || list.first, true ] if family.nil?

        same = list.select { |p| p.provider_type == family }
        return [ same.find(&:is_active), true ] if same.any?(&:is_active)
        return [ preferred, true ] if preferred && preferred.provider_type == family
        return [ same.first, true ] if same.any?

        [ list.find(&:is_active) || preferred || list.first, false ]
      end

      def initialize(account:, user: nil)
        raise ArgumentError, "#{SEAM} needs the account the principal acts in" unless account

        @account = account
        @user = user
      end

      def for(canonical_slug:)
        slug = canonical_slug.to_s
        return nil if slug.blank?

        canonical = ::Ai::Agent.global.find_by(slug: slug) || ::Ai::Agent.global.find_by(source_key: slug)

        owned = owned_agents.find_by(slug: slug) || owned_agents.find_by(source_key: slug)
        return follow_on_moves!(owned, canonical) if owned
        return nil unless canonical

        mint!(canonical)
      end

      def existing(agent)
        return agent if agent.nil? || !global?(agent)

        existing_clone_of(agent)
      end

      def acting(agent)
        return agent if agent.nil?
        return agent unless global?(agent)

        if (clone = existing_clone_of(agent))
          return follow_on_moves!(clone, agent)
        end

        mint!(agent) || agent
      end

      private

      def global?(agent)
        agent.respond_to?(:global?) && agent.global? == true
      end

      def owned_agents
        ::Ai::Agent.owned_by_account(account.id)
      end

      # The account's clone of THIS canonical: provenance first (a clone whose
      # name and slug an operator changed is still the clone), then the
      # identity keys the canonical carries.
      def existing_clone_of(canonical)
        owned = owned_agents.order(:created_at, :id)
        found = owned.find_by(cloned_from_id: canonical.id)
        found ||= owned.find_by(source_key: canonical.source_key) if canonical.source_key.present?
        found ||= owned.find_by(slug: canonical.slug) if canonical.slug.present?
        found
      end

      def creator
        return user if user && user.respond_to?(:account_id) && user.account_id == account.id

        account.users.order(:created_at).first
      end

      def mint!(canonical)
        owner = creator
        unless owner
          Rails.logger.warn(
            "[#{SEAM}] cannot clone canonical #{canonical.slug.inspect} into account #{account.id}: " \
            "the account has no user to own the clone"
          )
          return nil
        end

        provider, metadata_override = runnable_provider_for(canonical)
        unless provider
          Rails.logger.warn(
            "[#{SEAM}] cannot clone canonical #{canonical.slug.inspect} into account #{account.id}: " \
            "the account has no active provider and the canonical carries none"
          )
          return nil
        end

        ::Ai::Agent.transaction do
          # Two ticks (or a tick and a request door) can race to mint the same
          # clone; the per-(account, canonical) transaction lock makes the
          # second one find the first's row instead of minting a twin.
          lock_mint!(canonical)
          if (raced = existing_clone_of(canonical))
            next follow_on_moves!(raced, canonical)
          end

          clone = canonical.clone_to_account(
            account, { creator: owner, provider: provider, mcp_metadata: metadata_override }.compact
          )
          restore_identity!(clone, canonical)
          hierarchy.attach!(
            child: clone, parent: canonical, spawn_reason: SPAWN_REASON,
            metadata: { "canonical_slug" => canonical.slug, "source_version" => clone.source_version }
          )
          copy_skills!(clone, canonical)
          copy_delegation_policy!(clone, canonical)
          copy_trust_score!(clone, canonical)
          follow_on_moves!(clone, canonical)

          Rails.logger.info(
            "[#{SEAM}] minted account principal #{clone.id} for canonical #{canonical.slug.inspect} " \
            "in account #{account.id}"
          )
          clone
        end
      end

      # The clone must be RUNNABLE where the canonical was (deploy-4 incident,
      # 2026-09-04: ops-hub's only active provider was OpenAI, every fleet
      # canonical is pinned to a Claude model on the account's inactive
      # Anthropic provider, and "first active provider + keep the pin" failed
      # Ai::Agent's model/provider validation — so the boot reconcile failed
      # and every declared verb fell to the require_approval default).
      # Order: an ACTIVE provider of the pin's family in this account; else the
      # canonical's own provider when it belongs to this account and agrees
      # with the pin (that is exactly what the canonical ran on); else the
      # account's active provider with the pin DROPPED — an unpinned clone
      # resolves through the provider's default model instead of refusing to
      # exist. Returns [provider, mcp_metadata override or nil].
      def runnable_provider_for(canonical)
        pin = canonical.mcp_metadata&.dig("model_config", "model").presence
        # The canonical's own provider counts when this account owns it (that is
        # what the canonical itself runs on) — or, as the fallback of last
        # resort, when the account has no provider of its own at all. A clone
        # never borrows another tenant's provider while its own account has one.
        own = canonical.provider
        own = nil if own && own.account_id != account.id && account.ai_providers.exists?
        provider, compatible = self.class.provider_for_pin(
          pinned_model: pin, providers: account.ai_providers.ordered_by_priority, preferred: own
        )
        return [ nil, nil ] unless provider
        return [ provider, nil ] if compatible

        family = ::Ai::Agent.provider_family_for(pin)
        metadata = (canonical.mcp_metadata || {}).deep_dup
        metadata["model_config"] = (metadata["model_config"] || {}).except("model")
        Rails.logger.warn(
          "[#{SEAM}] canonical #{canonical.slug.inspect} is pinned to #{pin.inspect} (#{family}) but account " \
          "#{account.id} has no #{family} provider; minting the clone UNPINNED on #{provider.provider_type}"
        )
        [ provider, metadata ]
      end

      def lock_mint!(canonical)
        key = "#{SEAM}:#{account.id}:#{canonical.id}"
        ::ActiveRecord::Base.connection.execute(
          "SELECT pg_advisory_xact_lock(hashtext(#{::ActiveRecord::Base.connection.quote(key)}))"
        )
      end

      # `clone_to_account` suffixes "(Copy)" to stay clear of the canonical the
      # account can also see; the fleet's own principal keeps the canonical's
      # name and slug when the account has not used them (see IDENTITY above).
      # Name first — Ai::Agent regenerates the slug from a changed name — then
      # the slug, in case the canonical's slug is not name-derived.
      def restore_identity!(clone, canonical)
        others = owned_agents.where.not(id: clone.id)
        if canonical.name.present? && clone.name != canonical.name && !others.exists?(name: canonical.name)
          clone.update!(name: canonical.name)
        end
        if canonical.slug.present? && clone.slug != canonical.slug && !others.exists?(slug: canonical.slug)
          clone.update!(slug: canonical.slug)
        end
      end

      def copy_skills!(clone, canonical)
        canonical.agent_skills.find_each do |binding|
          ::Ai::AgentSkill.find_or_create_by!(ai_agent_id: clone.id, ai_skill_id: binding.ai_skill_id) do |copy|
            copy.is_active = binding.is_active
            copy.priority = binding.priority
          end
        end
      end

      # The policy that governed the canonical FOR THIS ACCOUNT (the account's
      # row, else the canonical account_id-NULL row), written for the clone
      # through the hierarchy seam so it is keyed and audited like every other
      # delegation policy.
      def copy_delegation_policy!(clone, canonical)
        policy = ::Ai::DelegationPolicy.resolve_for(agent_id: canonical.id, account_id: account.id)
        return unless policy

        attrs = policy.attributes
                      .slice(*::Ai::Agents::HierarchyWriter::DELEGATION_ATTRIBUTES.map(&:to_s))
                      .compact.symbolize_keys
        return if attrs.empty?

        hierarchy.ensure_delegation_policy!(agent: clone, **attrs)
      end

      def copy_trust_score!(clone, canonical)
        score = ::Ai::AgentTrustScore.find_by(agent_id: canonical.id)
        return unless score
        return if ::Ai::AgentTrustScore.exists?(agent_id: clone.id)

        ::Ai::AgentTrustScore.create!(
          score.attributes.except(*TRUST_SCORE_HISTORY).merge("agent_id" => clone.id, "account_id" => account.id)
        )
      end

      # Everything that must be true of the account's principal whichever path
      # minted it. Idempotent, and cheap when there is nothing to do — the
      # re-home's own scope is an indexed lookup that returns no rows on every
      # resolution after the first.
      def follow_on_moves!(clone, canonical)
        return clone if clone.nil? || canonical.nil? || clone.id == canonical.id

        rehome_intervention_policies!(clone, canonical)
        clone
      end

      # The account's agent-scoped rows written against the canonical move to
      # the clone, verbs and all — the move System::Governance::
      # PolicyReconciler#rehome! makes when a category's declared owner
      # changes, audited the same way (old and new ai_agent_id).
      #
      # WIDER than that precedent by one clause, deliberately: the reconciler
      # takes only `user_id: nil` rows because an operator-shape row is a
      # different AUDIENCE, not a former home. Here the criterion is not
      # audience but what the gate READS — FleetAutonomyService#permitted_actions
      # is `where(account:, ai_agent_id: agent.id, scope: "agent", is_active: true)`
      # with no user_id filter — so a `scope: "agent"` row with a user_id set is
      # a verb the gate would grant, and leaving it on a principal that can
      # never execute strands it. Every row the gate would read travels.
      def rehome_intervention_policies!(clone, canonical)
        rows = ::Ai::InterventionPolicy.where(account_id: account.id, ai_agent_id: canonical.id, scope: "agent")
        ids = rows.pluck(:id)
        return if ids.empty?

        rows.update_all(ai_agent_id: clone.id, updated_at: Time.current)
        audit!(
          resource: clone, event: "intervention_policies.rehomed",
          old_values: { "ai_agent_id" => canonical.id },
          new_values: { "ai_agent_id" => clone.id },
          details: { "canonical_id" => canonical.id, "canonical_slug" => canonical.slug,
                     "policy_ids" => ids, "count" => ids.size }
        )
      end

      def hierarchy
        @hierarchy ||= ::Ai::Agents::HierarchyWriter.new(account: account)
      end

      # Best-effort, like HierarchyWriter#audit!: an audit hiccup must not roll
      # back the principal it describes.
      def audit!(resource:, event:, details:, old_values: nil, new_values: nil)
        ::AuditLog.create!(
          account: account, user: nil,
          action: AUDIT_ACTION, source: "system",
          resource_type: resource.class.name, resource_id: resource.id,
          severity: "low", risk_level: "low",
          old_values: old_values, new_values: new_values,
          metadata: { "seam" => SEAM, "event" => event }.merge(details)
        )
      rescue StandardError => e
        Rails.logger.warn("[#{SEAM}] #{event} audit failed for #{resource.class.name} #{resource.id}: #{e.class}: #{e.message}")
      end
    end
  end
end
