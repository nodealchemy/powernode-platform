# frozen_string_literal: true

module Ai
  module Teams
    # ONE STRUCTURE, THREE VIEWS (HIER-P4). A canonical team is:
    #
    #   * an Ai::TeamTemplate (global, source_key-managed — the NODES and the
    #     ROLES, written by Ai::Teams::CanonicalTeamSeeder),
    #   * the lineage forest (one active Ai::AgentLineage edge manager → member
    #     per member, written by the hierarchy seeds through
    #     Ai::Agents::HierarchyWriter),
    #   * the delegation graph (the manager's Ai::DelegationPolicy admits every
    #     member's agent_type, and every type it admits is carried by some
    #     member — same writer),
    #
    # and it is MATERIALISED per account as an Ai::AgentTeam (hierarchical /
    # manager_led / hub_spoke) whose members are the account's EXECUTING
    # PRINCIPALS for the canonical agents — the clones
    # Ai::Agents::AccountPrincipalResolver mints — never the canonicals
    # themselves (proposal §5 ruling 8: a global canonical never executes, so
    # a team it sat in could never run).
    #
    # `drift` is read-only: it reports where the three views disagree —
    # missing lineage edges, members the manager may not delegate to, delegate
    # types the team lacks, absent canonicals — and where the materialised
    # team disagrees with the template (absent, missing / extra members, wrong
    # role, wrong lead). It resolves principals through the non-minting
    # `AccountPrincipalResolver.existing`, so a health check materialises
    # nothing (the same read-only discipline the fleet's per-agent policy
    # resolver keeps with its `mint: false`).
    #
    # `reconcile!` repairs MEMBERSHIP ONLY — the team row, its members, their
    # roles and lead — and mints the principals it needs. It never writes a
    # lineage edge or a delegation row: those have their own single writers,
    # and a missing edge stays reported as drift until that writer runs.
    # Idempotent: a second pass on an unchanged database changes nothing.
    #
    # Wired on `system:governance:reconcile` / `system:governance:drift`
    # (extensions/system/server/lib/tasks/governance_reconcile.rake) and called
    # by the two canonical team seeds at first boot.
    class CanonicalTeamReconciler
      SEAM = name.freeze

      # The delegate-type list "nobody" is spelled with (Ai::DelegationPolicy
      # reads an EMPTY list as unrestricted): db/seeds/ai_agent_hierarchy_seed.rb
      # RELEASE_MANAGER_NO_DELEGATES. Never a type a member could carry, so
      # never "unrepresented".
      NO_SUCH_TYPE_SENTINEL = "none"

      # The account the canonical team seeds materialise in, by name. The seeds
      # resolve it the same way (`Account.find_by(name: ...) || Account.first`);
      # the setting lets an install that named its first account differently
      # point the boot reconcile at it without a code change.
      PRIMARY_ACCOUNT_SETTING = "canonical_team_primary_account_name"
      DEFAULT_PRIMARY_ACCOUNT_NAME = "Powernode Admin"

      Result = Struct.new(:template, :team, :created, :team_updated, :members_added, :members_removed,
                          :members_updated, :skipped, keyword_init: true) do
        def changed?
          created || team_updated || members_added.positive? || members_removed.positive? || members_updated.positive?
        end
      end

      DriftReport = Struct.new(:template_slug, :absent_agents, :missing_edges, :present_edges,
                               :undelegatable_members, :unrepresented_delegate_types, :team_absent,
                               :missing_members, :extra_members, :role_mismatches, :lead_mismatch,
                               keyword_init: true) do
        def drifted?
          absent_agents.any? || missing_edges.any? || undelegatable_members.any? ||
            unrepresented_delegate_types.any? || team_absent || missing_members.any? ||
            extra_members.any? || role_mismatches.any? || lead_mismatch
        end
      end

      # One desired seat: the template definition, the canonical it names (nil
      # when absent) and the account's principal for it (nil when absent or,
      # read-only, not yet minted).
      Seat = Struct.new(:definition, :canonical, :principal, keyword_init: true) do
        def slug = definition["agent_slug"]
        def role = definition["member_role"]
        def lead? = definition["is_lead"] == true
      end

      class << self
        def reconcile_all!(account:, logger: Rails.logger)
          ::Ai::TeamTemplate.canonical.order(:slug).map do |template|
            new(account: account, template: template, logger: logger).reconcile!
          end
        end

        def drift_all(account:)
          ::Ai::TeamTemplate.canonical.order(:slug).map do |template|
            new(account: account, template: template).drift
          end
        end

        # The accounts a BOOT reconcile may write to. Materialising a canonical
        # team mints an account principal per seat, so walking Account.all would
        # create two teams and up to twenty agent rows in every tenant on every
        # boot — nothing in the campaign asks for per-tenant materialisation.
        # The write set is therefore: the accounts that already hold a canonical
        # team (so drift there is repaired wherever an operator materialised
        # one) plus the primary account the seeds materialise in (so an install
        # whose first boot predates the team seeds still gets one).
        # `drift` stays free to read every account.
        def reconcilable_accounts
          ids = ::Ai::AgentTeam.canonical.distinct.pluck(:account_id).compact
          primary = primary_account
          ids << primary.id if primary
          ::Account.where(id: ids.uniq)
        end

        def primary_account
          name = ::SiteSetting.get(PRIMARY_ACCOUNT_SETTING).presence || DEFAULT_PRIMARY_ACCOUNT_NAME
          ::Account.find_by(name: name) || ::Account.first
        end
      end

      attr_reader :account, :template

      def initialize(account:, template:, logger: Rails.logger)
        raise ArgumentError, "#{SEAM} needs the account the team is materialised in" unless account
        raise ArgumentError, "#{SEAM} needs a template" unless template
        raise ArgumentError, "#{SEAM}: #{template.slug.inspect} is not a canonical template" unless template.canonical?

        @account = account
        @template = template
        @logger = logger
      end

      def reconcile!
        skipped = []
        team, created, team_updated, conflict = find_or_materialise_team!
        if conflict
          return Result.new(template: template, team: nil, created: false, team_updated: false,
                            members_added: 0, members_removed: 0, members_updated: 0, skipped: [ conflict ])
        end

        seats = desired_seats(mint: true, skipped: skipped)
        desired_ids = seats.map { |s| s.principal.id }

        added = 0
        removed = 0
        updated = 0

        ::ActiveRecord::Base.transaction do
          # Pass 1: strangers out, wrong leads down — before the desired lead
          # is (re)asserted, so the single-lead validation never trips.
          team.members.includes(:agent).where.not(ai_agent_id: desired_ids).find_each do |member|
            team.ai_team_roles.where(ai_agent_id: member.ai_agent_id).destroy_all
            member.destroy!
            removed += 1
          end
          team.ai_team_roles.where.not(ai_agent_id: desired_ids).destroy_all

          lead_id = seats.find(&:lead?)&.principal&.id
          team.members.leads.where.not(ai_agent_id: lead_id).find_each do |member|
            member.update!(is_lead: false)
            updated += 1
          end

          # Pass 2: every desired seat present, at its role, priority and lead flag.
          existing = team.members.index_by(&:ai_agent_id)
          seats.each_with_index do |seat, index|
            attrs = { role: seat.role, is_lead: seat.lead?, priority_order: index }
            member = existing[seat.principal.id]
            seated_now = member.nil?
            if seated_now
              team.members.create!(agent: seat.principal, **attrs)
              added += 1
            elsif attrs.any? { |key, value| member.public_send(key) != value }
              member.update!(attrs)
              updated += 1
            end
            # A backing role written for a seat added just now is part of the
            # add, not a repair; only a role re-written for an existing seat counts.
            role_written = ensure_role!(team, seat, index)
            updated += 1 if role_written && !seated_now
          end
        end

        if created || team_updated || added.positive? || removed.positive? || updated.positive?
          @logger.info("[#{SEAM}] #{template.slug} in account #{account.id}: " \
                       "#{created ? 'created' : 'present'}, +#{added} -#{removed} ~#{updated} member(s), " \
                       "skipped #{skipped.size}")
        end

        Result.new(template: template, team: team, created: created, team_updated: team_updated,
                   members_added: added, members_removed: removed, members_updated: updated, skipped: skipped)
      end

      # Read-only: where the three views and the materialised team disagree.
      def drift
        skipped = []
        seats = desired_seats(mint: false, skipped: skipped, keep_unminted: true)
        absent = skipped.select { |s| s.end_with?("(agent absent)") }

        manager_def = template.manager_definition
        manager = manager_def && resolve_canonical(manager_def["agent_slug"])
        member_seats = seats.reject(&:lead?).select(&:canonical)

        missing_edges = []
        present_edges = []
        undelegatable = []
        unrepresented = []

        if manager
          policy = ::Ai::DelegationPolicy.resolve_for(agent_id: manager.id, account_id: account.id)
          member_seats.each do |seat|
            key = "#{manager_def['agent_slug']}/#{seat.slug}"
            attached?(seat.canonical, manager) ? present_edges << key : missing_edges << key
            if policy && !policy.allows_delegate_type?(seat.canonical.agent_type)
              undelegatable << "#{seat.slug}(#{seat.canonical.agent_type})"
            end
          end
          if policy
            carried = member_seats.map { |s| s.canonical.agent_type }.uniq
            unrepresented = Array(policy.allowed_delegate_types).map(&:to_s).uniq - carried - [ NO_SUCH_TYPE_SENTINEL ]
          end
        end

        team = canonical_team
        missing_members = []
        extra_members = []
        role_mismatches = []
        lead_mismatch = false

        if team
          members = team.members.includes(:agent).index_by(&:ai_agent_id)
          seats.each do |seat|
            member = seat.principal && members[seat.principal.id]
            if member.nil?
              missing_members << seat.slug
              next
            end
            role_mismatches << "#{seat.slug}(#{member.role}≠#{seat.role})" if member.role != seat.role
          end
          desired_ids = seats.filter_map { |s| s.principal&.id }
          extra_members = members.values.reject { |m| desired_ids.include?(m.ai_agent_id) }
                                 .map { |m| m.agent.slug }.sort
          lead_seat = seats.find(&:lead?)
          lead_mismatch = lead_seat.nil? || team.team_lead.nil? ||
                          team.team_lead.ai_agent_id != lead_seat.principal&.id
        else
          missing_members = seats.map(&:slug)
        end

        DriftReport.new(
          template_slug: template.slug,
          absent_agents: absent,
          missing_edges: missing_edges.sort,
          present_edges: present_edges.sort,
          undelegatable_members: undelegatable.sort,
          unrepresented_delegate_types: unrepresented.sort,
          team_absent: team.nil?,
          missing_members: missing_members,
          extra_members: extra_members,
          role_mismatches: role_mismatches,
          lead_mismatch: lead_mismatch
        )
      end

      private

      # The account's materialisation: template_id AND the canonical flag. A
      # team merely cloned from the template (TeamTemplate#create_team!) has
      # the id but not the flag, and is the account's own.
      def canonical_team
        account.ai_agent_teams.canonical.find_by(template_id: template.id)
      end

      def find_or_materialise_team!
        team = canonical_team
        created = false

        if team.nil?
          stray = account.ai_agent_teams.find_by(name: template.name)
          if stray
            return [ nil, false, false,
                     "#{template.slug}(name conflict: team #{stray.id} #{template.name.inspect} is not the " \
                     "canonical materialisation — rename it, then reconcile)" ]
          end

          team = account.ai_agent_teams.new(name: template.name)
          created = true
        end

        config = template.default_config || {}
        team.assign_attributes(
          name: template.name,
          description: template.description,
          goal_description: template.description,
          team_type: config["team_type"] || "hierarchical",
          team_topology: template.team_topology,
          coordination_strategy: config["coordination_strategy"] || "manager_led",
          communication_pattern: config["communication_pattern"] || "hub_spoke",
          template_id: template.id,
          team_config: (team.team_config || {}).merge(
            "canonical"     => true,
            "source_key"    => template.source_key,
            "template_slug" => template.slug
          )
        )
        team_updated = !created && team.changed?
        team.save! if team.new_record? || team.changed?

        [ team, created, team_updated, nil ]
      end

      # `keep_unminted`: in a read-only pass a seat whose principal does not
      # exist yet stays in the list (principal nil) so it reports as a missing
      # member; the writing pass drops it into `skipped` instead.
      def desired_seats(mint:, skipped:, keep_unminted: false)
        template.member_definitions.filter_map do |definition|
          slug = definition["agent_slug"]
          canonical = resolve_canonical(slug)
          if canonical.nil?
            skipped << "#{slug}(agent absent)"
            next keep_unminted ? Seat.new(definition: definition, canonical: nil, principal: nil) : nil
          end

          principal = principal_for(canonical, mint: mint)
          if principal.nil?
            skipped << "#{slug}(no account principal)" unless keep_unminted
            next keep_unminted ? Seat.new(definition: definition, canonical: canonical, principal: nil) : nil
          end

          Seat.new(definition: definition, canonical: canonical, principal: principal)
        end
      end

      def principal_for(canonical, mint:)
        if mint
          ::Ai::Agents::AccountPrincipalResolver.acting(canonical, account: account)
        else
          ::Ai::Agents::AccountPrincipalResolver.existing(canonical, account: account)
        end
      end

      # Global canonicals only — slug first, then the seed-managed source_key
      # (the System Topology Designer's slug and source_key differ).
      def resolve_canonical(slug)
        ::Ai::Agent.global.find_by(slug: slug) || ::Ai::Agent.global.find_by(source_key: slug)
      end

      def attached?(child, parent)
        ::Ai::AgentLineage.for_child(child.id).active.exists?(parent_agent_id: parent.id)
      end

      # The backing Ai::TeamRole the orchestration/UI layer reads, bound to the
      # principal. True when it was created or changed.
      def ensure_role!(team, seat, index)
        definition = seat.definition
        role = team.ai_team_roles.find_or_initialize_by(ai_agent_id: seat.principal.id)
        role.assign_attributes(
          account: account,
          role_name: unique_role_name(team, role, definition["name"]),
          role_type: ::Ai::AgentTeamMember.role_type_for(seat.role),
          role_description: definition["description"].presence || seat.canonical.description,
          capabilities: Array(definition["capabilities"]),
          priority_order: index,
          can_delegate: seat.lead?,
          can_escalate: definition.fetch("can_escalate", true)
        )
        return false unless role.new_record? || role.changed?

        role.save!
        true
      end

      def unique_role_name(team, role, name)
        taken = team.ai_team_roles.where(role_name: name).where.not(id: role.id).exists?
        taken ? "#{name} (#{role.ai_agent_id})" : name
      end
    end
  end
end
