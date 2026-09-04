# frozen_string_literal: true

module Ai
  module Agents
    # The ONE writer of the agent hierarchy: `Ai::AgentLineage` edges (plus the
    # child's denormalised `parent_agent_id`) and `Ai::DelegationPolicy` rows.
    #
    # WHY A SEAM (HIER-P1). Until this class, the only lineage writer was
    # `FactoryService#create_lineage`, which had no production caller, and the
    # only delegation-policy writer was the REST controller — so every seeded
    # agent and every agent created by a tool, a team composer or the autonomy
    # service was a root on the Autonomy page, and
    # `DelegationAuthorityService#validate_delegation` allowed everything for
    # want of a row. The seeds and the four creation paths HIER-P1 covers
    # (AgentManagementTool#create_agent, AgentAutonomyService#create_agent_for_team,
    # ConciergeService#create_agent_from_spec and FactoryService#spawn) now call
    # the same two methods, so the lineage forest, the delegation panel and the
    # actual authority checks describe one structure. Api::V1::Ai::AgentsController#create
    # is the remaining door that still creates a root (a later increment).
    #
    # WHAT IT DOES NOT DECIDE. Self/cycle refusal stays in
    # `Ai::AgentLineage`'s validations (this class lets `RecordInvalid`
    # propagate); resolution of WHICH policy governs an agent stays in
    # `Ai::DelegationPolicy.resolve_for`. This class only guarantees that a
    # write is idempotent, keyed correctly, and audited.
    #
    # ACCOUNT KEYING. `account` is the account whose hierarchy is being
    # written, and BOTH rows carry it: a lineage row must (the column is NOT
    # NULL, and a GLOBAL agent owns no account, so seeds pass the platform
    # admin account), and a delegation policy is keyed (agent_id, account_id)
    # on that same account. This seam never writes the CANONICAL
    # `account_id NULL` policy row that HIER-P0's migration makes possible:
    # keying every write on a real account is correct under both the old
    # `account_id NOT NULL` schema and the new partial indexes, so seeding the
    # hierarchy never depends on which of the two a database is at.
    # `Ai::DelegationPolicy.resolve_for` finds the row for that account and
    # another account may still hold its own.
    class HierarchyWriter
      SEAM = name.freeze

      # Audit action names must already be registered (AuditLog validates
      # against AuditActions.all_actions); both writes are configuration
      # changes to an agent, and the metadata names the seam and the event.
      AUDIT_ACTION = "ai.agents.update"

      # The only Ai::DelegationPolicy columns this seam writes. `allowed_actions`
      # is accepted as the operator-facing alias of `delegatable_actions`
      # (the ruling and the Autonomy modal both say "allowed actions").
      DELEGATION_ATTRIBUTES = %i[inheritance_policy max_depth allowed_delegate_types
                                 delegatable_actions budget_delegation_pct].freeze
      DELEGATION_ALIASES = { allowed_actions: :delegatable_actions }.freeze

      attr_reader :account

      def initialize(account:)
        raise ArgumentError, "#{SEAM} needs the account whose hierarchy is being written" unless account

        @account = account
      end

      # Make `child` a child of `parent`. Idempotent on (parent, child): an
      # existing edge is reused, a terminated one is reactivated, and any OTHER
      # active edge the child had is terminated so a child has exactly one
      # active parent. Raises ActiveRecord::RecordInvalid on a self edge or a
      # cycle (the model's validations). Returns the Ai::AgentLineage.
      def attach!(child:, parent:, spawn_reason:, metadata: {})
        raise ArgumentError, "attach! needs a child agent" unless child
        raise ArgumentError, "attach! needs a parent agent" unless parent

        ActiveRecord::Base.transaction do
          lineage = ::Ai::AgentLineage.find_or_initialize_by(parent_agent_id: parent.id, child_agent_id: child.id)
          lineage.assign_attributes(
            account: account,
            spawn_reason: spawn_reason.to_s,
            spawned_at: lineage.spawned_at || Time.current,
            terminated_at: nil,
            termination_reason: nil,
            # Snapshot keys are the seam's own and are REFRESHED on every
            # attach (a stale parent_trust_level would outlive a trust change);
            # the caller's metadata still wins over both.
            metadata: (lineage.metadata || {}).merge(parent_snapshot(parent)).merge(metadata.to_h.stringify_keys)
          )
          edge_changed = lineage.new_record? || lineage.changed?
          lineage.save! if edge_changed

          reparented = terminate_other_edges!(child, parent)
          child.update!(parent_agent_id: parent.id) if child.parent_agent_id != parent.id

          if edge_changed || reparented.any?
            audit!(
              resource: lineage,
              event: "lineage.attach",
              details: {
                "parent_agent_id" => parent.id, "child_agent_id" => child.id,
                "spawn_reason" => spawn_reason.to_s, "reparented_from" => reparented
              }
            )
          end

          lineage
        end
      end

      # Upsert the delegation policy for `agent`, keyed (agent_id, this
      # writer's account) — see ACCOUNT KEYING above. Only the columns in
      # DELEGATION_ATTRIBUTES (or the `allowed_actions` alias) are accepted;
      # anything else is a caller bug and raises. Returns the Ai::DelegationPolicy.
      def ensure_delegation_policy!(agent:, **attrs)
        raise ArgumentError, "ensure_delegation_policy! needs an agent" unless agent

        attributes = normalize_delegation_attrs(attrs)

        ActiveRecord::Base.transaction do
          policy = ::Ai::DelegationPolicy.find_or_initialize_by(agent_id: agent.id, account_id: account.id)
          policy.assign_attributes(attributes)
          next policy unless policy.new_record? || policy.changed?

          changed = policy.changes.transform_values(&:last)
          policy.save!
          audit!(
            resource: policy,
            event: "delegation_policy.upsert",
            details: { "agent_id" => agent.id, "policy_account_id" => policy.account_id },
            new_values: changed
          )
          policy
        end
      end

      private

      def parent_snapshot(parent)
        {
          "parent_trust_level" => parent.try(:trust_level),
          "parent_type" => parent.agent_type
        }.compact
      end

      # Every other ACTIVE edge into `child` is closed: the seam's contract is
      # one active parent per child. Returns the parent ids it closed.
      def terminate_other_edges!(child, parent)
        ::Ai::AgentLineage.for_child(child.id).active.where.not(parent_agent_id: parent.id).map do |edge|
          edge.terminate!(reason: "reparented to #{parent.id} by #{SEAM}")
          edge.parent_agent_id
        end
      end

      def normalize_delegation_attrs(attrs)
        attrs.to_h.symbolize_keys.each_with_object({}) do |(key, value), out|
          column = DELEGATION_ALIASES.fetch(key, key)
          unless DELEGATION_ATTRIBUTES.include?(column)
            raise ArgumentError, "#{SEAM}#ensure_delegation_policy! does not write #{key.inspect} " \
                                 "(accepts #{DELEGATION_ATTRIBUTES.join(', ')}, allowed_actions)"
          end

          out[column] = value
        end
      end

      # Both writes are recorded against the account whose hierarchy changed,
      # with the seam named so the entry is attributable to this path and not
      # to the REST controllers that write the same tables for operators.
      def audit!(resource:, event:, details:, new_values: nil)
        ::AuditLog.create!(
          account: account, user: nil,
          action: AUDIT_ACTION, source: "system",
          resource_type: resource.class.name, resource_id: resource.id,
          severity: "low", risk_level: "low",
          new_values: new_values || details,
          metadata: { "seam" => SEAM, "event" => event }.merge(details)
        )
      rescue StandardError => e
        # Best-effort, like Ai::Agent's global audit hook: an audit hiccup must
        # not roll back the hierarchy write it describes.
        Rails.logger.warn("[#{SEAM}] #{event} audit failed for #{resource.class.name} #{resource.id}: #{e.class}: #{e.message}")
      end
    end
  end
end
