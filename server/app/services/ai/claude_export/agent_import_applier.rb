# frozen_string_literal: true

module Ai
  module ClaudeExport
    # The other half of AgentImportProposer. claude:import_agents files an
    # agent_create proposal whose payload is the would-be agent spec and creates
    # nothing; approving that proposal (Ai::AgentProposals::Handoff) calls this to
    # create it.
    #
    # ACCOUNT-SCOPED, never global. An account's reviewer decided this, so the row belongs
    # to that account: account_id = the proposal's account, is_system false, source_key =
    # slug, INACTIVE (an operator activates it), created by the approving user on one of the
    # account's active providers. A GLOBAL canonical is platform-maintained, seed-managed
    # content that every account clones; one account's approval must not mint one.
    #
    # Tool access is validated, not copied: every entry of tool_access.tool_families must be a
    # declared family (Ai::Tools::ToolFamilies) or a registered platform action name (what the
    # proposer emits). An unrecognised entry matches nothing, and a family list that matches
    # nothing fails OPEN to the whole registry (ToolAllowlist), so it is refused outright.
    #
    # Create-only within the account: an agent already carrying the slug IS the one the
    # proposal asked for and is returned untouched.
    class AgentImportApplier
      DESCRIPTION_MAX = 1_000

      # The payload cannot make a safe agent; the handoff fails and the approval rolls back.
      class Invalid < StandardError; end

      def initialize(proposal, creator: nil)
        @proposal = proposal
        @creator = creator
      end

      # @return [Ai::Agent] the account's agent (created now, or already present)
      def apply!
        spec = @proposal.proposed_changes
        raise Invalid, "agent_create payload is empty" unless spec.is_a?(Hash) && spec.present?

        slug = spec["slug"].to_s.strip
        raise Invalid, "agent_create payload has no slug" if slug.empty?

        account = @proposal.account
        existing = ::Ai::Agent.find_by(account_id: account.id, slug: slug)
        return existing if existing

        families, tools = split_tool_access(spec)
        agent = ::Ai::Agent.new(
          account_id: account.id, slug: slug, source_key: slug, is_system: false, status: "inactive", version: "1.0.0",
          creator: creator_for(account), provider: provider_for(account),
          name: spec["name"].presence || slug.tr("-", " ").titleize,
          agent_type: spec["agent_type"].presence || AgentImportProposer::DEFAULT_AGENT_TYPE,
          description: spec["description"].to_s.truncate(DESCRIPTION_MAX)
        )
        agent.mcp_metadata = metadata_from(spec, families, tools)
        agent.system_prompt = spec["system_prompt"].to_s
        agent.save!
        agent
      end

      # The tier, families and tools as the proposal card shows them, before anything is
      # approved. Entries are split exactly as #apply! will store them; an unrecognised
      # entry is listed under `unknown` (approval would refuse it).
      def self.preview(spec)
        return nil unless spec.is_a?(Hash)

        families, tools, unknown = classify(entries_from(spec))
        {
          "slug" => spec["slug"],
          "tier" => spec.dig("model_config", "model_requirements", "tier").presence || ::Ai::ModelTiers::DEFAULT_TIER.to_s,
          "tool_families" => families, "tools" => tools, "unknown" => unknown
        }
      end

      # [families, tools, unknown]: a declared family is a family, a registered platform action
      # name is a tool, and the two are never stored under one key. (The importer emits action
      # names today; emitting families is a separate change.)
      def self.classify(entries)
        registry = ToolAllowlist::Registry.snapshot
        families, rest = entries.partition { |e| ::Ai::Tools::ToolFamilies.known?(e) }
        tools, unknown = rest.partition { |e| registry.registered?(e) }
        [ families, tools, unknown ]
      end

      def self.entries_from(spec)
        Array(spec.dig("tool_access", "tool_families")).map { |e| e.to_s.strip }.reject(&:empty?).uniq
      end

      private

      def split_tool_access(spec)
        families, tools, unknown = self.class.classify(self.class.entries_from(spec))
        return [ families, tools ] if unknown.empty?

        raise Invalid, "unknown tool #{unknown.size == 1 ? 'family' : 'families'}: #{unknown.join(', ')}"
      end

      def metadata_from(spec, families, tools)
        tier = spec.dig("model_config", "model_requirements", "tier").presence || ::Ai::ModelTiers::DEFAULT_TIER.to_s
        {
          "model_config" => { "model_requirements" => { "tier" => tier } },
          "tool_access" => { "tool_families" => families, "tools" => tools }
        }
      end

      def creator_for(account)
        @creator || account.owner || raise(Invalid, "no user to create the agent as")
      end

      def provider_for(account)
        ::Ai::Provider.where(account_id: account.id).active.ordered_by_priority.first ||
          raise(Invalid, "the account has no active AI provider to run the agent on")
      end
    end
  end
end
