# frozen_string_literal: true

module Ai
  module Agents
    # A runtime writer was handed a GLOBAL canonical agent row.
    class GlobalRowRefused < StandardError
      attr_reader :reason, :details

      def initialize(message, reason:, details: {})
        super(message)
        @reason = reason
        @details = details
      end
    end

    # THE refusal every runtime writer that attributes to an agent shares.
    #
    # A global canonical agent (account_id NULL) is a read-only TEMPLATE, updated
    # only by approved, deployed seeds. Runtime state (runs, memory, skill usage,
    # learnings that name an agent) attaches to the ACCOUNT'S SHADOW of it, which
    # Ai::Agents::AccountPrincipalResolver.for mints. A writer that is handed the
    # global row refuses with a stated reason and writes nothing; it never falls
    # back to the global row, and it never takes the resolver's `acting` fallback
    # (which answers with the canonical itself when no clone can be minted).
    module ShadowWriteGuard
      REASON = "global_canonical_row"

      module_function

      # @param agent_or_id [Ai::Agent, String, nil] the agent a write would attribute to
      # @param writer [String] the writer's name, carried in the refusal
      # @return [Ai::Agent, String, nil] the argument, when it is not a global row
      # @raise [GlobalRowRefused] when it is a global canonical
      def refuse_global!(agent_or_id, writer:)
        slug = global_slug(agent_or_id)
        return agent_or_id unless slug

        raise GlobalRowRefused.new(
          "Refused: #{writer} was handed the global canonical agent #{slug.presence || agent_label(agent_or_id)} — a " \
          "read-only template that runtime state never attaches to. Resolve the account's shadow " \
          "(Ai::Agents::AccountPrincipalResolver.for) and write to that. Nothing was written.",
          reason: REASON,
          details: { writer: writer, agent_slug: slug, agent_id: agent_label(agent_or_id) }
        )
      end

      # True for a global agent record or the id of one.
      def global?(agent_or_id) = !global_slug(agent_or_id).nil?

      # The slug ("" when it has none) of a global agent, nil for anything else.
      def global_slug(agent_or_id)
        case agent_or_id
        when nil then nil
        when ::Ai::Agent then agent_or_id.global? ? agent_or_id.slug.to_s : nil
        else
          id = agent_or_id.to_s
          return nil if id.blank?

          rows = ::Ai::Agent.global.where(id: id).pluck(:slug)
          rows.empty? ? nil : rows.first.to_s
        end
      end

      def agent_label(agent_or_id)
        agent_or_id.respond_to?(:id) ? agent_or_id.id.to_s : agent_or_id.to_s
      end
    end
  end
end
