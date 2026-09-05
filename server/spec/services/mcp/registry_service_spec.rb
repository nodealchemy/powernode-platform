# frozen_string_literal: true

require "rails_helper"

# IMP-c2f5de2f11f3.
#
# The finding was "no spec, and the persistence layer is three empty stubs".
# The first half is true. The second half describes the code correctly but is
# the wrong work item, and this file deliberately does NOT specify those stubs:
#
#   persist_tool_to_database   reachable (register_tool/update_tool -> store_tool), no-op
#   remove_tool_from_database  reachable (unregister_tool -> remove_tool),          no-op
#   load_tools_from_database   UNREACHABLE — its only caller, #sync_registry, has zero callers
#   cleanup_orphaned_entries   UNREACHABLE — same
#
# Specifying an empty method pins "this does nothing", which makes dead
# scaffolding look maintained. What IS worth pinning is the reason those stubs
# are inert: this registry is a PER-INSTANCE PROJECTION of `ai_agents`, rebuilt
# by #load_existing_tools in the constructor. The agents table is the source of
# truth and `mcp_tool_manifest` is a column on it, so there is no registry
# state that needs persisting.
#
# The examples below are the contract a future "let's implement persistence"
# change would break — which is exactly the change this ticket invites.
RSpec.describe Mcp::RegistryService do
  let(:account) { create(:account) }

  def tool_id_for(agent)
    "agent_#{agent.id}_v#{agent.version.gsub('.', '_')}"
  end

  # A manifest that satisfies #validate_tool_manifest! (required fields +
  # semver). Built by hand rather than from an agent so the "not persisted"
  # example below cannot be rescued by load_existing_tools re-deriving it.
  def standalone_manifest(name)
    {
      "name" => name,
      "description" => "critic fixture",
      "type" => "function",
      "version" => "1.0.0",
      "inputSchema" => { "type" => "object", "properties" => {} },
      "outputSchema" => { "type" => "object", "properties" => {} }
    }
  end

  describe "the registry is derived from ai_agents, not persisted" do
    it "indexes the account's active agents on construction" do
      agent = create(:ai_agent, account: account)

      registry = described_class.new(account: account)

      expect(registry.get_tool(tool_id_for(agent))).to be_present
    end

    # The load-bearing example. A tool with no corresponding agent exists only
    # in the instance that registered it: #store_tool's database write is a
    # no-op and its Redis write is never read back, so a fresh instance
    # reconstructs from `ai_agents` alone and this tool is simply gone.
    #
    # If someone implements persist_tool_to_database, THIS is the example that
    # will fail, and it should — it means the registry has acquired a second
    # source of truth alongside the agents table.
    it "does NOT carry a registered tool over to a new instance" do
      manifest = standalone_manifest("critic-standalone-tool")
      first = described_class.new(account: account)
      first.register_tool("standalone_tool_v1_0_0", manifest)
      expect(first.get_tool("standalone_tool_v1_0_0")).to be_present

      second = described_class.new(account: account)

      expect(second.get_tool("standalone_tool_v1_0_0")).to be_nil
    end

    it "scopes the projection to the account — another account's agents are absent" do
      other_account = create(:account)
      other_agent = create(:ai_agent, account: other_account)

      registry = described_class.new(account: account)

      expect(registry.get_tool(tool_id_for(other_agent))).to be_nil
    end

    # Asserted through #get_tool rather than #list_tools: the latter is
    # Rails.cache-backed on unfiltered queries (1h TTL, key
    # "mcp:registry:tools:<account|global>:<sort>"), so a list assertion can be
    # answered by another example's cached value rather than by this instance.
    it "projects nothing when constructed without an account" do
      agent = create(:ai_agent, account: account)

      expect(described_class.new(account: nil).get_tool(tool_id_for(agent))).to be_nil
    end
  end

  # IMP-63a7d2f99c56. #invalidate_caches called Rails.cache.delete_matched,
  # which the production default store (solid_cache) does not implement — see
  # CacheVersioning's header. The test store (MemoryStore) DOES implement
  # delete_matched, so these examples swap in NoDeleteMatchedCacheStore
  # (spec/support/no_delete_matched_cache_store.rb) to exercise the property
  # that actually matters: production, not the store that hides the defect.
  describe "#invalidate_caches" do
    subject(:registry) { described_class.new(account: account) }

    it "does not raise on a cache store that cannot delete_matched" do
      allow(Rails).to receive(:cache).and_return(NoDeleteMatchedCacheStore.new)

      expect { registry.invalidate_caches }.not_to raise_error
    end

    it "retires a previously cached #list_tools result" do
      allow(Rails).to receive(:cache).and_return(NoDeleteMatchedCacheStore.new)
      stale = registry.list_tools # populates the cache under the pre-invalidation key
      expect(stale).to be_empty # the account has no agents yet
      create(:ai_agent, account: account)

      registry.invalidate_caches
      refreshed = described_class.new(account: account).list_tools

      expect(refreshed.size).to eq(1) # unaddressable stale [] entry, recomputed from the DB
    end
  end

  describe "#register_tool / #unregister_tool within one instance" do
    subject(:registry) { described_class.new(account: account) }

    it "round-trips a valid manifest" do
      registry.register_tool("critic_tool_v1_0_0", standalone_manifest("critic-tool"))

      expect(registry.get_tool("critic_tool_v1_0_0")["name"]).to eq("critic-tool")
    end

    it "removes it again" do
      registry.register_tool("critic_tool_v1_0_0", standalone_manifest("critic-tool"))
      registry.unregister_tool("critic_tool_v1_0_0")

      expect(registry.get_tool("critic_tool_v1_0_0")).to be_nil
    end

    it "refuses a manifest missing required fields" do
      expect {
        registry.register_tool("bad_tool", { "name" => "bad" })
      }.to raise_error(described_class::RegistryError, /Missing required fields/)
    end

    it "refuses a non-semver version" do
      manifest = standalone_manifest("critic-tool").merge("version" => "1.0")

      expect {
        registry.register_tool("bad_tool", manifest)
      }.to raise_error(described_class::RegistryError, /Invalid version format/)
    end
  end
end
