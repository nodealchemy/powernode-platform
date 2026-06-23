# frozen_string_literal: true

require 'rails_helper'

# Repo-hygiene check: the schema / data-model docs must not present `Permission`
# as a current ActiveRecord model (or `permissions` as a live table). The 0.4.0
# refactor DROPPED the Permission model and the permissions table — permissions
# are now code-defined in the `Permissions` catalog (server/config/permissions.rb),
# and roles carry by-name grants via `role_permissions`. docs/concepts/permissions.md
# is authoritative: "there is no `permissions` table (and no `Permission` model)".
#
# Reproduces IMP-e71d4d2df687: database-schema.md and data-model.md still listed
# `Permission` as a top-level model/entity and wired it into the mermaid diagrams.
RSpec.describe 'Permission model references in schema docs' do
  repo_root = File.expand_path('../../..', __dir__)

  docs = [
    File.join(repo_root, 'docs', 'reference', 'database-schema.md'),
    File.join(repo_root, 'docs', 'concepts', 'data-model.md')
  ]

  # pattern => human description of the stale form it catches.
  # `Perm\b` / `Permission\b` boundaries keep these from matching the still-valid
  # `RolePermission` join-table rows.
  stale_patterns = {
    /^\|\s*`Permission`\s*\|/ => '`Permission` model/entity table row',
    /Role\s*-->\s*Permission\b/ => '`Role --> Permission` mermaid edge',
    /Perm\[Permission\]/ => '`Perm[Permission]` mermaid node',
    /Role\s*-->\s*Perm\b/ => '`Role --> Perm` mermaid edge',
    /Role,\s*Permission\b/ => '`Permission` in top-level model list'
  }

  it 'does not list the dropped Permission model / permissions table as current' do
    violations = []

    docs.each do |doc_path|
      rel = doc_path.delete_prefix("#{repo_root}/")
      File.readlines(doc_path).each_with_index do |line, idx|
        stale_patterns.each do |pattern, desc|
          violations << "#{rel}:#{idx + 1} — #{desc}" if line.match?(pattern)
        end
      end
    end

    expect(violations).to(
      be_empty,
      "Docs still present the dropped Permission model/table as current " \
      "(permissions are code-defined — see docs/concepts/permissions.md):\n" \
      "#{violations.join("\n")}"
    )
  end
end
