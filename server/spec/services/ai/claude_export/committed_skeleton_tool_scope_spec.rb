# frozen_string_literal: true

require "spec_helper"
require "digest"

# IMP-777f59d4cc1e — the oracle over the GENERATED artifact.
#
# Ai::ClaudeExport::ToolAllowlist's last case (nothing configured) returns the
# platform read verbs, a pure function of the tool registry that never looks
# at the agent. Every canonical whose seed omitted a tool-access configuration
# therefore exported one identical `tools:` line: on 2026-09-13, 18 committed
# skeletons shared one 277-entry digest. Claude Code picks a subagent from these
# files, so specialists that are byte-identical in what they can reach cannot
# be told apart on that dimension.
#
# Operator direction: every canonical is scoped by tool FAMILIES derived from
# its duty surface, no canonical exports the full catalog, and the skeleton
# renders the families. Text only (no Rails env, no DB), so it reads exactly
# what is committed.
RSpec.describe "committed Claude Code agent skeletons (tool scope)" do
  skeleton_dir = File.expand_path("../../../../../.claude/agents/powernode", __dir__)
  skeletons = Dir[File.join(skeleton_dir, "*.md")].sort.to_h do |path|
    [ File.basename(path, ".md"), File.read(path) ]
  end

  tools_line = ->(content) { content[/\A---\n.*?^tools: (.*?)$.*?^---$/m, 1] }

  it "found the committed skeleton set (scan sanity)" do
    expect(skeletons.size).to be >= 10
  end

  it "gives every canonical a `tools:` allowlist — none inherits the full catalog" do
    unscoped = skeletons.reject { |_, content| tools_line.call(content) }.keys

    expect(unscoped).to be_empty, "these skeletons omit `tools:` and so inherit every tool: #{unscoped.join(', ')}"
  end

  it "exports a distinct allowlist for every canonical" do
    groups = skeletons.filter_map { |slug, content| (line = tools_line.call(content)) && [ slug, line ] }
                      .group_by { |_, line| Digest::SHA256.hexdigest(line.split(",").map(&:strip).sort.join(",")) }
                      .values.select { |group| group.size > 1 }

    expect(groups).to be_empty,
      "canonicals sharing one tools digest cannot be told apart by what they reach: " \
      "#{groups.map { |group| group.map(&:first).join(' = ') }.join('; ')}"
  end

  it "renders each canonical's tool families in the skeleton" do
    missing = skeletons.reject { |_, content| content.match?(/^## Tool families\n\n.*`\w+`/) }.keys

    expect(missing).to be_empty, "these skeletons render no tool families: #{missing.join(', ')}"
  end
end
