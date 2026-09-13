# frozen_string_literal: true

require "rails_helper"
require "digest"

# IMP-777f59d4cc1e — every core canonical agent seeds a tool-access
# configuration expressed as tool FAMILIES.
#
# With none, Ai::ClaudeExport::ToolAllowlist falls through to the platform read
# verbs — the same list for every agent — and the runtime bridge
# (AgentToolBridgeService#scope_to_tool_families) serves the full registry. So
# the specialists were identical in what they could reach. This pins the seed
# half: each canonical declares families, they resolve to something (a list
# matching nothing fails OPEN to the full catalog), and no two canonicals
# resolve to the same allowlist.
RSpec.describe "core canonical agent seeds declare tool families" do
  seed_files = %w[
    claude_agents_seed.rb monitoring_analytics_agents_seed.rb ai_utility_agents_seed.rb
    ai_concierge_seed.rb autonomy_data_seed.rb ai_engineering_agents_seed.rb
  ].freeze

  def load_seed!(file)
    silence_warnings { load Rails.root.join("db", "seeds", file) }
  end

  define_method(:seed_all!) { seed_files.each { |file| load_seed!(file) } }

  let!(:concierge_skill) do
    create(:ai_skill, :global, slug: "powernode-concierge", name: "Powernode Concierge", is_system: true)
  end
  let(:registry) { Ai::ClaudeExport::ToolAllowlist::Registry.snapshot }
  let(:canonicals) { Ai::Agent.global.where(status: "active").order(:slug).to_a }

  def families_of(agent)
    agent.reload.mcp_metadata.dig("tool_access", "tool_families")
  end

  it "seeds tool families on every core canonical" do
    seed_all!

    expect(canonicals.size).to be >= 10
    unscoped = canonicals.reject { |agent| families_of(agent).present? }.map(&:slug)
    expect(unscoped).to be_empty, "these canonicals seed no tool families: #{unscoped.join(', ')}"
  end

  it "resolves every canonical to its own scoped allowlist — not the read-verb fallback, not the full catalog" do
    seed_all!

    resolved = canonicals.to_h { |agent| [ agent.slug, Ai::ClaudeExport::ToolAllowlist.platform_actions_for(agent, registry: registry) ] }

    unscoped = resolved.select { |_, actions| actions == Ai::ClaudeExport::ToolAllowlist::UNSCOPED }.keys
    expect(unscoped).to be_empty, "these canonicals export the full catalog (families matched nothing?): #{unscoped.join(', ')}"

    fallback = resolved.select { |_, actions| actions.is_a?(Array) && actions.sort == registry.read_action_names.sort }.keys
    expect(fallback).to be_empty, "these canonicals still export the read-verb fallback: #{fallback.join(', ')}"

    shared = resolved.group_by { |_, actions| Digest::SHA256.hexdigest(Array(actions).sort.join(",")) }
                     .values.select { |group| group.size > 1 }
    expect(shared).to be_empty, "canonicals resolving to one allowlist: #{shared.map { |g| g.map(&:first).join(' = ') }.join('; ')}"
  end

  # Several of these seeds write the canonical in a create-only block, and
  # seeds re-run on every dev install and CI database: a canonical that already
  # exists must acquire its families on the next seed, not only a new row.
  it "declares the families on a canonical that already exists without them" do
    seed_all!
    canonicals.each do |agent|
      agent.update_columns(mcp_metadata: agent.mcp_metadata.except("tool_access"))
    end

    seed_all!

    unscoped = canonicals.reject { |agent| families_of(agent).present? }.map(&:slug)
    expect(unscoped).to be_empty, "a re-seed left these canonicals unscoped: #{unscoped.join(', ')}"
  end

  it "is idempotent — a second seed does not rewrite a canonical's tool access" do
    seed_all!
    snapshot = -> { canonicals.map { |agent| [ agent.slug, agent.reload.mcp_metadata["tool_access"], agent.updated_at ] } }

    expect { seed_all! }.not_to change(&snapshot)
  end
end
