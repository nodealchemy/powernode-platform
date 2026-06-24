# frozen_string_literal: true

require 'rails_helper'

# Repo-hygiene check: ops/reference docs must not instruct operators to run the
# `scripts/backup/*.sh` wrappers — that directory has never existed in git
# history. Database backups and restores run as standalone-worker maintenance
# jobs (Maintenance::ScheduledBackupJob / DatabaseBackupJob / DatabaseRestoreJob /
# BackupCleanupJob, scheduled in worker/config/sidekiq.yml) that wrap
# `pg_dump -Fc` / `pg_restore`. An operator following the old runbooks would run
# a nonexistent script — dangerous mid-incident.
#
# Reproduces IMP-6ee4cd6e2a7a.
RSpec.describe 'backup runbook script references' do
  repo_root = File.expand_path('../../..', __dir__)
  docs_dir = File.join(repo_root, 'docs')

  forbidden = {
    %r{scripts/backup/} => 'reference to the nonexistent scripts/backup/ directory',
    /backup-database\.sh/ => 'reference to the nonexistent backup-database.sh script',
    /restore-database\.sh/ => 'reference to the nonexistent restore-database.sh script'
  }

  it 'does not point operators at the nonexistent scripts/backup/*.sh wrappers' do
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
      "Docs still reference nonexistent backup scripts (backups run as worker " \
      "maintenance jobs — see docs/operations/postgres-backup.md):\n#{violations.join("\n")}"
    )
  end
end
