# frozen_string_literal: true

require 'rails_helper'

# Repo-hygiene check: relative Markdown links in the GitHub issue templates must
# resolve to files that actually exist. A wrong relative depth (e.g. `../docs`
# instead of `../../docs` from `.github/ISSUE_TEMPLATE/`) renders as a dead link
# in the GitHub issue form even though the target file exists at the repo root.
#
# Reproduces IMP-ee554cc1b52d: both bug_report.md and feature_request.md linked
# the stability-tier doc as `(../docs/STABILITY.md)`, which resolves to the
# non-existent `.github/docs/STABILITY.md`.
RSpec.describe 'GitHub issue template links' do
  repo_root = File.expand_path('../../..', __dir__)
  template_dir = File.join(repo_root, '.github', 'ISSUE_TEMPLATE')

  # [text](target) where target is a relative path — exclude absolute URLs,
  # in-page anchors, and mailto: links.
  relative_link = %r{\]\((?!https?://|#|mailto:)([^)]+)\)}

  templates = Dir.glob(File.join(template_dir, '*.md')).sort
  it 'finds issue templates to check' do
    expect(templates).not_to be_empty
  end

  templates.each do |template_path|
    context File.basename(template_path) do
      links = File.read(template_path).scan(relative_link).flatten

      links.each do |link|
        rel_path = link.split('#', 2).first # drop any anchor fragment

        it "resolves relative link #{link.inspect} to an existing file" do
          resolved = File.expand_path(rel_path, File.dirname(template_path))
          expect(File.exist?(resolved)).to(
            be(true),
            "#{File.basename(template_path)} links to #{link.inspect}, which " \
            "resolves to #{resolved} — no such file"
          )
        end
      end
    end
  end
end
