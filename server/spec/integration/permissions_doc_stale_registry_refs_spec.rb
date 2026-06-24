# frozen_string_literal: true

require 'rails_helper'

# Repo-hygiene check: permissions docs must not cite registry internals removed
# by the 0.4.0 permissions-standardization. Permissions are now code-defined in
# the `Permissions` catalog (server/config/permissions.rb); there is no Permission
# model/table, no seeder, and no per-topic seed files. concepts/permissions.md:30
# is authoritative.
#
# Reproduces IMP-7a9f8e9442a8 — docs still cited the deleted
# permission_seeder.rb / ai_autonomy_permissions.rb, the renamed
# `Permissions::ALL_PERMISSIONS` constant (now CORE_PERMISSIONS +
# Permissions.all_permissions), and a hardcoded "371 static permissions" count.
RSpec.describe 'permissions docs stale registry references' do
  repo_root = File.expand_path('../../..', __dir__)
  docs_dir = File.join(repo_root, 'docs')

  forbidden = {
    /permission_seeder/ => 'reference to the deleted permission_seeder.rb',
    /ai_autonomy_permissions/ => 'reference to the deleted ai_autonomy_permissions.rb seed file',
    /\bALL_PERMISSIONS\b/ => 'reference to the renamed Permissions::ALL_PERMISSIONS (now CORE_PERMISSIONS / Permissions.all_permissions)',
    /\b371\b/ => 'hardcoded permission count (the total is dynamic — Permissions.all_permissions.size)'
  }

  it 'does not cite removed/renamed permission registry internals' do
    violations = []

    Dir.glob(File.join(docs_dir, '**', '*.md')).sort.each do |md_path|
      rel = md_path.delete_prefix("#{repo_root}/")
      File.readlines(md_path).each_with_index do |line, idx|
        forbidden.each do |pattern, desc|
          violations << "#{rel}:#{idx + 1} — #{desc}" if line.match?(pattern)
        end
      end
    end

    expect(violations).to(
      be_empty,
      "Permissions docs still cite removed/renamed registry internals " \
      "(catalog is the source of truth — see docs/concepts/permissions.md):\n" \
      "#{violations.join("\n")}"
    )
  end
end
