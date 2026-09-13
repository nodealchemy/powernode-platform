# frozen_string_literal: true

# The tool-family scope of a GLOBAL canonical agent (IMP-777f59d4cc1e).
#
# A canonical with no tool_access falls through Ai::ClaudeExport::ToolAllowlist
# to the platform read verbs — one list, the same for every agent, because that
# case never looks at the agent — and through
# Ai::AgentToolBridgeService#scope_to_tool_families to the full registry. So
# every canonical names the families its duty surface needs. A family admits a
# registry verb by exact name or by `<family>_` prefix; a list matching nothing
# fails OPEN to the full catalog, which spec/db/seeds/canonical_tool_families_spec.rb
# guards against.
#
# The seed owns a canonical's families: they are written on every run, so a
# canonical first created by an earlier seed (several of these seeds use a
# create-only find_or_create_global block) acquires them too. Other tool_access
# keys (max_iterations, …) are kept, and a row already carrying the families is
# not written again.
module CoreSeeds
  module CanonicalToolAccess
    module_function

    # @return [Hash] a copy of mcp_metadata whose tool_access carries `families`
    def with_families(mcp_metadata, families)
      metadata = mcp_metadata.is_a?(Hash) ? mcp_metadata.deep_dup : {}
      tool_access = metadata["tool_access"].is_a?(Hash) ? metadata["tool_access"] : {}
      metadata.merge("tool_access" => tool_access.merge("tool_families" => families))
    end

    def declare_families!(agent, families)
      metadata = with_families(agent.mcp_metadata, families)
      return if metadata == agent.mcp_metadata

      agent.update!(mcp_metadata: metadata)
    end
  end
end
