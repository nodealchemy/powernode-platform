# frozen_string_literal: true

require_relative "../content/canonical_agent_content"

# A GLOBAL canonical's seeded text (description, system prompt), written on every
# seed run like CoreSeeds::CanonicalToolAccess, but through
# Ai::Agents::CanonicalContentRefresh: a field an operator edited is kept and
# reported instead of overwritten. A seed that builds a row assigns its text only
# while the row is new and calls refresh! after saving it.
module CoreSeeds
  module CanonicalContent
    module_function

    def refresh!(agent, fields, previous: {})
      outcome = Ai::Agents::CanonicalContentRefresh.apply!(agent, fields, previous: previous)
      warn_skipped(outcome)
      outcome
    end

    # refresh! with the fields and previous values CanonicalAgentContent holds
    # for the agent's slug, merged over `inline` (fields the seed still owns).
    def refresh_from_catalog!(agent, inline: {})
      slug = agent.slug
      refresh!(agent, inline.merge(CanonicalAgentContent.fields(slug)), previous: CanonicalAgentContent.previous(slug))
    end

    # Applies every CanonicalAgentContent entry to its global row in `model`
    # (Ai::Agent, or a migration's own table class); a slug with no global row
    # is skipped. Data migrations call this, since seeds never re-run.
    # @return [Array<Ai::Agents::CanonicalContentRefresh::Outcome>]
    def refresh_catalog!(model)
      CanonicalAgentContent::AGENTS.keys.filter_map do |slug|
        agent = model.find_by(account_id: nil, slug: slug)
        next unless agent

        refresh!(agent, CanonicalAgentContent.fields(slug), previous: CanonicalAgentContent.previous(slug))
      end
    end

    # @param only [Hash{String => Array<Symbol>}, nil] slug => fields, for a
    #   wave's down that must not revert what an earlier wave wrote
    def revert_catalog!(model, only: nil)
      (only || CanonicalAgentContent::AGENTS.keys.index_with { nil }).each do |slug, fields|
        agent = model.find_by(account_id: nil, slug: slug)
        next unless agent

        values = CanonicalAgentContent.fields(slug)
        Ai::Agents::CanonicalContentRefresh.revert!(agent, fields ? values.slice(*fields) : values)
      end
    end

    # Sets each catalog entry's mcp_flags on its global row in `model` where the
    # row lacks the key; a key the row already has (an operator's choice) is
    # kept. Returns the slugs it changed.
    def apply_flags_catalog!(model)
      CanonicalAgentContent::AGENTS.keys.filter_map do |slug|
        flags = CanonicalAgentContent.mcp_flags(slug)
        next if flags.empty?

        agent = model.find_by(account_id: nil, slug: slug)
        next unless agent

        metadata = agent.mcp_metadata.is_a?(Hash) ? agent.mcp_metadata : {}
        missing = flags.reject { |key, _| metadata.key?(key) }
        next if missing.empty?

        agent.update_columns(mcp_metadata: metadata.merge(missing))
        slug
      end
    end

    # Removes a catalog flag from its global row only where the row still holds
    # the seeded value.
    def revert_flags_catalog!(model)
      CanonicalAgentContent::AGENTS.keys.each do |slug|
        flags = CanonicalAgentContent.mcp_flags(slug)
        next if flags.empty?

        agent = model.find_by(account_id: nil, slug: slug)
        next unless agent && agent.mcp_metadata.is_a?(Hash)

        seeded = flags.select { |key, value| agent.mcp_metadata.key?(key) && agent.mcp_metadata[key] == value }
        agent.update_columns(mcp_metadata: agent.mcp_metadata.except(*seeded.keys)) if seeded.any?
      end
    end

    def warn_skipped(outcome)
      return unless outcome.skipped?

      message = "[CanonicalContent] #{outcome.slug}: kept operator-edited #{outcome.skipped.join(', ')}"
      Rails.logger.warn(message)
      puts "  ⚠️  #{message}"
    end
  end
end
