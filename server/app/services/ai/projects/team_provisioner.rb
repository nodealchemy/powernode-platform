# frozen_string_literal: true

module Ai
  module Projects
    # APO increment `app-5` (core half) — gives a project its OWNING TEAM.
    #
    # REUSE, NOT A SECOND PATH. Materialising a canonical Ai::TeamTemplate into
    # an Ai::AgentTeam already has exactly one implementation —
    # Ai::Teams::CanonicalTeamReconciler — and it already does the hard parts:
    # it seats the account's EXECUTING PRINCIPALS (ruling 8, a global canonical
    # never executes, so the seats are clones minted by
    # Ai::Agents::AccountPrincipalResolver with a canonical_clone lineage edge),
    # it writes the backing Ai::TeamRole rows, and it is idempotent. This class
    # does not reimplement any of that. It supplies the PROJECT SCOPE the
    # reconciler now takes, then adds the two things a project team needs that
    # an account team does not: a bounded delegation policy and a supervised
    # start for anything it minted.
    #
    # THE DELEGATION POLICY IS THE POINT, and it is written through the ONE
    # writer of delegation rows, Ai::Agents::HierarchyWriter#ensure_delegation_policy!
    # — not with a direct create, which would make this the third writer of a
    # row that has a single-writer ruling.
    #
    # PERMISSION LAUNDERING. A project team must not be able to delegate
    # authority it was not granted. Both lists are derived through
    # Ai::DelegationPolicy.narrow, which reads a parent's list literally (an
    # empty list permits nothing) and so can never return more than the parent
    # held. This used to end every derivation at a sentinel and to widen an
    # empty parent to the seated types, from when an empty list meant
    # UNRESTRICTED; under HIER-P0 that widening handed a leaf's clone
    # delegation its parent did not hold (IMP-d2873a16567e).
    #
    # BEST-EFFORT, like the mission attach in app-4. A project whose team cannot
    # be created is still a valid, usable project: the team is additive, nothing
    # downstream requires one, and failing project creation because a canonical
    # template has not been seeded yet would be a worse outcome than a project
    # with no team.
    class TeamProvisioner
      SEAM = name.freeze

      # The canonical template this provisions from — seeded by
      # db/seeds/ai_project_operations_team_seed.rb as a global, is_system,
      # source_key-managed Ai::TeamTemplate.
      TEMPLATE_SLUG = "project-operations"

      # Ceiling on a project team's delegation depth, before the parent's own
      # depth and the project's declaration narrow it further. A project team
      # coordinates its own three seats; it is not a place to grow a tree.
      DEFAULT_MAX_DEPTH = 2

      # Where a project declares its own delegation bounds, inside the
      # `configuration` hash the bounds ladder already reads from.
      DELEGATION_CONFIG_KEY = "delegation"
      MAX_DEPTH_KEY         = "max_depth"
      BUDGET_PCT_KEY        = "budget_delegation_pct"

      # Every newly minted principal starts here. Ai::AgentTrustScore::TIERS
      # orders supervised < monitored < trusted < autonomous.
      INITIAL_TRUST_TIER = "supervised"

      Result = Struct.new(:project, :team, :created, :members_seated, :minted_principal_ids,
                          :policy, :skipped, keyword_init: true) do
        def provisioned? = !team.nil?
      end

      class << self
        def provision!(project:, user: nil, template_slug: TEMPLATE_SLUG)
          new(project: project, user: user, template_slug: template_slug).provision!
        end
      end

      attr_reader :project, :user, :template_slug

      def initialize(project:, user: nil, template_slug: TEMPLATE_SLUG)
        raise ArgumentError, "#{SEAM} needs a project" unless project

        @project = project
        @user = user
        @template_slug = template_slug.to_s
      end

      # Never raises. See the BEST-EFFORT note in the header: the caller is a
      # project creation path, and the project is the thing the operator asked
      # for.
      def provision!
        template = canonical_template
        unless template
          return empty_result(
            "template #{template_slug.inspect} is not seeded",
            state: ::Ai::Project::STATE_NO_TEMPLATE
          )
        end

        # Which principals exist BEFORE seating — anything that appears after is
        # newly minted and starts supervised. Read before the write, because
        # after it every seat exists and the distinction is gone.
        pre_existing = existing_principal_ids(template)

        result = ::Ai::Teams::CanonicalTeamReconciler
                 .new(account: project.account, template: template, project: project)
                 .reconcile!
        unless result.team
          return empty_result(
            result.skipped.join(", ").presence || "team was not materialised",
            state: ::Ai::Project::STATE_FAILED
          )
        end

        team = result.team
        minted = team.members.pluck(:ai_agent_id) - pre_existing
        supervise!(minted)
        policy = bound_delegation!(team)

        Result.new(project: project, team: team, created: result.created,
                   members_seated: team.members.count, minted_principal_ids: minted,
                   policy: policy, skipped: result.skipped)
      rescue StandardError => e
        Rails.logger.warn(
          "[#{SEAM}] could not provision a team for project #{project.id} (#{e.class}: #{e.message}); " \
          "the project stands without one"
        )
        empty_result("#{e.class}: #{e.message}", state: ::Ai::Project::STATE_FAILED)
      end

      private

      # Every teamless exit records WHY (APO app-6). Before this the three
      # teamless outcomes — never attempted, no template on this install, the
      # attempt failed — were one indistinguishable appearance, which is the
      # same defect shape as a health probe returning a constant.
      #
      # SUCCESS records nothing: `provisioned` is derived from the team
      # association, so writing it would be a second claim about a fact the row
      # already states, free to go stale. NOT-ATTEMPTED records nothing either
      # — it IS the absence, and writing it would make "we gave up" and "nobody
      # ever tried" indistinguishable again.
      #
      # The record is itself BEST-EFFORT. This whole service exists so that a
      # team failure cannot fail a project, and a failure to write the
      # explanation of a failure must not be the thing that finally does.
      def empty_result(reason, state:)
        record_outcome(state, reason)
        Result.new(project: project, team: nil, created: false, members_seated: 0,
                   minted_principal_ids: [], policy: nil, skipped: [ reason ])
      end

      def record_outcome(state, reason)
        project.record_team_provisioning!(state: state, reason: reason, template_slug: template_slug)
      rescue StandardError => e
        Rails.logger.warn(
          "[#{SEAM}] could not record the team-provisioning outcome for project #{project.id} " \
          "(#{e.class}: #{e.message}); the state reads as #{::Ai::Project::STATE_NOT_ATTEMPTED}"
        )
        nil
      end

      def canonical_template
        ::Ai::TeamTemplate.canonical.find_by(slug: template_slug) ||
          ::Ai::TeamTemplate.canonical.find_by(source_key: template_slug)
      end

      # Read-only: never mints, so the "was it minted by this call" question is
      # answered without changing its own answer.
      def existing_principal_ids(template)
        template.member_definitions.filter_map do |definition|
          canonical = resolve_canonical(definition["agent_slug"])
          next nil unless canonical

          ::Ai::Agents::AccountPrincipalResolver.existing(canonical, account: project.account)&.id
        end
      end

      def resolve_canonical(slug)
        ::Ai::Agent.global.find_by(slug: slug) || ::Ai::Agent.global.find_by(source_key: slug)
      end

      # A principal this call brought into existence starts SUPERVISED.
      #
      # Only the ones it minted. Ai::Agents::AccountPrincipalResolver copies the
      # canonical's trust score on mint, and an account may deliberately have
      # promoted an existing clone since — demoting that row because a project
      # happened to seat it would revert an operator decision this class knows
      # nothing about.
      def supervise!(agent_ids)
        Array(agent_ids).each do |agent_id|
          score = ::Ai::AgentTrustScore.find_or_initialize_by(agent_id: agent_id)
          score.account ||= project.account
          score.tier = INITIAL_TRUST_TIER
          score.overall_score = ::Ai::AgentTrustScore::TIER_THRESHOLDS.fetch(INITIAL_TRUST_TIER, 0.0)
          score.save! if score.new_record? || score.changed?
        end
      end

      # The team lead's delegation policy, DERIVED by narrowing — never copied,
      # never widened. Returns the policy, or nil when there is no lead to bound
      # (a template with no manager cannot delegate at all).
      def bound_delegation!(team)
        lead = team.team_lead
        return nil unless lead

        principal = lead.agent
        # The authority being narrowed is the CLONING agent's — the canonical
        # this principal was cloned from, resolved through the same override
        # rule every other reader uses. A principal cloned from nothing is
        # bounded by the platform ceiling alone.
        parent = parent_policy_for(principal)
        seated_types = team.members.includes(:agent).map { |m| m.agent.agent_type.to_s }.uniq.compact_blank

        ::Ai::Agents::HierarchyWriter.new(account: project.account).ensure_delegation_policy!(
          agent: principal,
          inheritance_policy: parent&.inheritance_policy.presence || "conservative",
          max_depth: narrow_depth(parent),
          allowed_delegate_types: narrow_types(parent, seated_types),
          allowed_actions: narrow_actions(parent),
          budget_delegation_pct: narrow_budget(parent)
        )
      end

      def parent_policy_for(principal)
        canonical_id = principal.try(:cloned_from_id)
        return nil unless canonical_id

        ::Ai::DelegationPolicy.resolve_for(agent_id: canonical_id, account_id: project.account_id)
      end

      # The narrowest of: the platform ceiling, the parent's depth, the
      # project's declaration. `min` over the declared ones, never their max.
      def narrow_depth(parent)
        candidates = [ DEFAULT_MAX_DEPTH ]
        candidates << parent.max_depth.to_i if parent&.max_depth.to_i.positive?
        declared = positive_integer(project_delegation_config[MAX_DEPTH_KEY])
        candidates << declared if declared
        [ candidates.min, 1 ].max
      end

      # The team needs its seated types and the action delegation is checked
      # as; it gets the part of each its cloning agent held. A principal cloned
      # from nothing (no parent row) is bounded by those needs alone.
      def narrow_types(parent, seated_types)
        ::Ai::DelegationPolicy.narrow(held: parent&.allowed_delegate_types, needed: seated_types)
      end

      def narrow_actions(parent)
        ::Ai::DelegationPolicy.narrow(held: parent&.delegatable_actions, needed: ::Ai::DelegationPolicy::DELEGATABLE_ACTIONS)
      end

      # A fraction in [0, 1]. The project may lower it; nothing may raise it
      # above what the parent held.
      def narrow_budget(parent)
        candidates = []
        held = parent&.budget_delegation_pct
        candidates << held.to_f if held
        declared = project_delegation_config[BUDGET_PCT_KEY]
        fraction = Float(declared.to_s, exception: false)
        candidates << fraction if fraction && fraction >= 0.0 && fraction <= 1.0
        return 0.0 if candidates.empty?

        candidates.min.clamp(0.0, 1.0)
      end

      def project_delegation_config
        cfg = project.configuration
        return {} unless cfg.is_a?(Hash)

        section = cfg[DELEGATION_CONFIG_KEY] || cfg[DELEGATION_CONFIG_KEY.to_sym]
        section.is_a?(Hash) ? section.deep_stringify_keys : {}
      end

      def positive_integer(raw)
        value = raw.is_a?(Numeric) ? raw.to_i : Integer(raw.to_s.strip, exception: false)
        value&.positive? ? value : nil
      end
    end
  end
end
