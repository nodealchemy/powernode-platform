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
    # Any count of permissions written into prose ("371 static permissions",
    # "329 permissions"), not a bare number: a code line range such as
    # `file.rb:346-371` is not a count.
    /\b\d{2,}\s+(?:static\s+|total\s+|core\s+|registered\s+|catalog\s+|defined\s+)?permissions?\b/i =>
      'hardcoded permission count (the total is dynamic — Permissions.all_permissions.size)'
  }

  descriptions_for = lambda do |line|
    forbidden.filter_map { |pattern, desc| desc if line.match?(pattern) }
  end

  # IMP-faac96398df8: the count rule matched any bare "371", so two docs citing
  # code line ranges (`processor.rb:371-381`, `tool.rb:346-371`) turned this spec
  # red with no permission count in sight. The rule is about a COUNT of permissions.
  describe 'the hardcoded-count rule' do
    it 'flags a permission count written into prose' do
      expect(descriptions_for.call('The catalog defines 371 static permissions.').join)
        .to include('hardcoded permission count')
    end

    it 'does not flag a code line reference that happens to contain the number' do
      expect(descriptions_for.call('see `module_publication_processor.rb:371-381`')).to be_empty
      expect(descriptions_for.call('(`improvement_tool.rb:346-371`) already exists')).to be_empty
    end
  end

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
