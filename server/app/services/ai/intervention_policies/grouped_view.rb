# frozen_string_literal: true

module Ai
  module InterventionPolicies
    # The account's intervention-policy rows grouped by DOMAIN, for the settings
    # panel (GET /api/v1/ai/intervention_policies/grouped).
    #
    # The panel builds its sections from this grouping rather than from a list
    # of categories written into the component: categories are defined and
    # seeded server-side, and a hardcoded copy drifted to omit 28 of 119 of them
    # (IMP-0874acd5b50c).
    #
    # Domains are the ones extensions REGISTER with Ai::ClaudeExport::PolicyDomains,
    # first match wins, in registration order. Every registered domain is shipped
    # even when empty, and a row no registered domain claims lands in "other".
    # PolicyDomains' routing heuristic is NOT used: it would invent a domain no
    # extension presents.
    #
    # This is an ACCOUNT-WIDE view and returns every row, unpaged: filtering
    # rows out of it is the defect class that made the old by_agent pivot drop
    # agents. A client showing one extension's domains filters on its own side.
    class GroupedView
      OTHER_DOMAIN = "other"
      MANUAL_BUCKET = "Manual Operations"

      def initialize(account:)
        @account = account
      end

      def as_json(*)
        { policies: { by_domain: by_domain }, chains: chains }
      end

      # The by-agent group a row belongs to. Scope decides, not agent presence:
      # nothing ties ai_agent_id to scope, so an action_type row can name an
      # agent and still be the operator's.
      def self.agent_bucket_for(policy)
        policy.scope == "agent" && policy.agent ? policy.agent.name : MANUAL_BUCKET
      end

      private

      attr_reader :account

      def by_domain
        table = ::Ai::ClaudeExport::PolicyDomains.registered
        result = table.map(&:first).uniq.index_with { [] }
        result[OTHER_DOMAIN] = []

        policies.each do |policy|
          match = table.find { |(_domain, prefixes)| prefixes.any? { |pre| policy.action_category.start_with?(pre) } }
          result[match&.first || OTHER_DOMAIN] << serialize(policy)
        end
        result
      end

      def policies
        ::Ai::InterventionPolicy.where(account: account).includes(:agent, :approval_chain).order(:action_category, :id)
      end

      def chains
        ::Ai::ApprovalChain.where(account: account, status: "active").map do |c|
          { id: c.id, name: c.name, step_count: c.step_count, is_sequential: c.is_sequential }
        end
      end

      def serialize(policy)
        {
          id: policy.id,
          action_category: policy.action_category,
          scope: policy.scope,
          policy: policy.policy,
          priority: policy.priority,
          is_active: policy.is_active,
          agent_id: policy.ai_agent_id,
          agent_name: policy.agent&.name,
          agent_bucket: self.class.agent_bucket_for(policy),
          approval_chain_id: policy.approval_chain_id,
          approval_chain_name: policy.approval_chain&.name,
          conditions: policy.conditions,
          preferred_channels: policy.preferred_channels
        }
      end
    end
  end
end
