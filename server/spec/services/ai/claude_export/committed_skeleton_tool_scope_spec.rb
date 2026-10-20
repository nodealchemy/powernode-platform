# frozen_string_literal: true

require "rails_helper"

# The oracle over the COMMITTED artifact, .claude/agents/powernode/*.md.
#
# Streamlining campaign C4 replaced the 24 per-agent skeletons (about 200 KB,
# each with a `tools:` allowlist of up to 119 MCP verbs resolved from its tool
# families — IMP-777f59d4cc1e's digest rule kept those lists apart) by four
# thin loaders, one per Ai::Agents::CanonicalRoster survivor. A thin loader is a
# pure function of the roster (Ai::ClaudeExport::ThinLoader), so this checks
# freshness byte for byte with no database, plus the shape the restart contract
# depends on: the set, the size budget, and a `tools:` line holding only the
# fixed bootstrap core.
RSpec.describe "committed Claude Code agent skeletons (thin loaders)" do
  skeleton_dir = File.expand_path("../../../../../.claude/agents/powernode", __dir__)
  ceilings_file = File.expand_path("../../../../../scripts/claude-agents-size-ceilings.txt", __dir__)
  skeletons = Dir[File.join(skeleton_dir, "*.md")].sort.to_h do |path|
    [ File.basename(path, ".md"), File.read(path) ]
  end

  tools_line = ->(content) { content[/\A---\n.*?^tools: (.*?)$.*?^---$/m, 1].to_s.split(",").map(&:strip) }
  loader = Ai::ClaudeExport::ThinLoader

  it "is exactly the four survivors' skeletons" do
    expect(skeletons.keys).to match_array(Ai::Agents::CanonicalRoster.slugs)
  end

  it "matches what `rails claude:sync_agents` renders today (regenerate and commit if not)" do
    stale = skeletons.reject { |slug, content| content == loader.render(slug) }.keys

    expect(stale).to be_empty, "regenerate with `cd server && bundle exec rails claude:sync_agents`: #{stale.join(', ')}"
  end

  it "keeps every skeleton inside the thin-loader budget" do
    oversized = skeletons.select { |_, content| content.lines.size > loader::MAX_LINES || content.bytesize > loader::MAX_BYTES }

    expect(oversized.keys).to be_empty
  end

  it "lists only the bootstrap core in every `tools:` line" do
    core = %w[Read Grep Glob ToolSearch Edit Write Bash] +
           loader::BOOTSTRAP_ACTIONS.map { |action| "#{loader::MCP_PREFIX}#{action}" } + [ loader::SERVER_GRANT ]

    extra = skeletons.transform_values { |content| tools_line.call(content) - core }.reject { |_, names| names.empty? }
    expect(extra).to be_empty, "outside the bootstrap core: #{extra.inspect}"
  end

  it "holds the size ceilings at the thin-loader reality (they only ever go down)" do
    ceilings = File.readlines(ceilings_file).grep(/\A\w+=\d+/).to_h { |line| line.strip.split("=") }.transform_values(&:to_i)

    expect(ceilings["max_tools_per_agent"]).to eq(skeletons.values.map { |content| tools_line.call(content).size }.max)
    expect(ceilings["max_roster_bytes"]).to be <= Ai::Agents::CanonicalRoster.slugs.size * loader::MAX_BYTES
    expect(skeletons.values.sum(&:bytesize)).to be <= ceilings["max_roster_bytes"]
  end
end
