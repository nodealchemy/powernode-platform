# frozen_string_literal: true

require 'rails_helper'

# Repo-hygiene check: relative Markdown links in the PostgreSQL backup runbook
# must resolve to paths that exist on disk. Reproduces IMP-628100dbbc03 — the doc
# pointed readers to Vault backup guidance at `../infrastructure/vault-example/`,
# a directory that has never existed in the repository.
RSpec.describe 'postgres-backup.md relative links' do
  repo_root = File.expand_path('../../..', __dir__)
  doc_path = File.join(repo_root, 'docs', 'operations', 'postgres-backup.md')

  # [text](target) where target is a relative path — exclude absolute URLs,
  # in-page anchors, and mailto: links.
  relative_link = %r{\]\((?!https?://|#|mailto:)([^)]+)\)}

  it 'resolves every relative link to an existing path' do
    broken = []

    File.read(doc_path).scan(relative_link).flatten.each do |target|
      rel_path = target.split('#', 2).first # drop any anchor fragment
      next if rel_path.empty? # pure in-page anchor

      resolved = File.expand_path(rel_path, File.dirname(doc_path))
      broken << target unless File.exist?(resolved)
    end

    expect(broken).to(
      be_empty,
      "postgres-backup.md links to paths that do not exist:\n#{broken.join("\n")}"
    )
  end
end
