# frozen_string_literal: true

require 'rails_helper'

# Repo-hygiene check: the "Related Files" links in the AI provider cost-tracking
# note must resolve (correct `../` depth from server/docs/platform/) and any
# `path:line` / `path:start-end` anchor must point inside the target file.
#
# Reproduces IMP-57954e6451d4 — the links used `../` (one level short, resolving
# under server/docs/ instead of server/) and cited
# server/app/models/ai_provider.rb (moved to the Ai:: namespace at
# server/app/models/ai/provider.rb) with a 273-298 range past the 265-line file.
RSpec.describe 'AI_PROVIDER_COST_TRACKING_UPDATE.md related-file links' do
  repo_root = File.expand_path('../../..', __dir__)
  doc_path = File.join(
    repo_root, 'server', 'docs', 'platform', 'AI_PROVIDER_COST_TRACKING_UPDATE.md'
  )

  # [text](../relative/path) — only the in-repo source links (start with `..`).
  relative_link = %r{\]\((\.\.[^)]+)\)}

  it 'resolves every ../ source link and keeps line anchors inside the file' do
    problems = []

    File.read(doc_path).scan(relative_link).flatten.each do |target|
      # Split off an optional trailing :line or :start-end editor anchor.
      m = target.match(/\A(?<path>.*?)(?::(?<start>\d+)(?:-(?<finish>\d+))?)?\z/)
      resolved = File.expand_path(m[:path], File.dirname(doc_path))

      unless File.exist?(resolved)
        problems << "#{target} — path #{m[:path]} does not resolve"
        next
      end

      last = m[:finish] || m[:start]
      next unless last

      line_count = File.foreach(resolved).count
      if last.to_i > line_count
        problems << "#{target} — line #{last} is past EOF (#{line_count} lines)"
      end
    end

    expect(problems).to(
      be_empty,
      "Stale Related Files links in AI_PROVIDER_COST_TRACKING_UPDATE.md:\n#{problems.join("\n")}"
    )
  end
end
