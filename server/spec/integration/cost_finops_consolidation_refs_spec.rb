# frozen_string_literal: true

require 'rails_helper'

# Repo-hygiene check for the "Materials previously at" provenance list in
# docs/concepts/cost-and-finops.md.
#
# Reproduces IMP-aae510affb58: two inline-code cross-refs that the markdown
# link-checker misses (docs/.verify/check-links.sh deliberately strips backtick
# spans) were dead —
#   (1) `docs/platform/AI_PROVIDER_PRICING_REFERENCE.md` used the wrong prefix; that
#       doc was not removed — it is still current at
#       server/docs/platform/AI_PROVIDER_PRICING_REFERENCE.md.
#   (2) `docs/platform/AI_PROVIDER_ROUTING.md` exists nowhere in the repo.
#
# Every reference in this file to either doc must resolve on disk (relative to the
# repo root or to the doc's own directory). The genuinely-removed
# COST_ATTRIBUTION_SYSTEM.md entry is intentionally out of scope: it is accurate
# historical provenance with no surviving location to point at.
RSpec.describe 'cost-and-finops.md consolidation cross-references' do
  repo_root = File.expand_path('../../..', __dir__)
  doc_path  = File.join(repo_root, 'docs', 'concepts', 'cost-and-finops.md')
  doc_dir   = File.dirname(doc_path)
  doc       = File.read(doc_path)

  # Path-like tokens (inline-code or markdown-link targets) ending in either doc.
  tracked = %r{[\w./-]*AI_PROVIDER_(?:PRICING_REFERENCE|ROUTING)\.md}

  it 'has no dead reference to the pricing reference or routing doc' do
    problems = doc.scan(tracked).uniq.reject do |token|
      File.exist?(File.expand_path(token, repo_root)) ||
        File.exist?(File.expand_path(token, doc_dir))
    end

    expect(problems).to(
      be_empty,
      "Dead AI provider doc cross-refs in cost-and-finops.md:\n#{problems.join("\n")}"
    )
  end
end
