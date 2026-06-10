# frozen_string_literal: true

namespace :dev_loop do
  desc "Seed a Ralph Loop task queue from an audit findings backlog. " \
       "Usage: rails 'dev_loop:seed_audit[/path/to/findings.md]' " \
       "(SEVERITIES=S2,S3 ACCOUNT_ID=<uuid> to override defaults)"
  task :seed_audit, [:path] => :environment do |_t, args|
    path = args[:path]
    abort "Usage: rails 'dev_loop:seed_audit[/path/to/findings.md]'" if path.blank?
    abort "File not found: #{path}" unless File.exist?(path)

    severities = ENV["SEVERITIES"].presence&.split(/[,;\s]+/) ||
                 Ai::DevLoop::AuditBacklogSeeder::DEFAULT_SEVERITIES
    account = ENV["ACCOUNT_ID"].present? ? Account.find(ENV["ACCOUNT_ID"]) : Account.order(:created_at).first
    abort "No account found" unless account

    result = Ai::DevLoop::AuditBacklogSeeder.new(account: account, path: path, severities: severities).call

    puts "Loop: #{result.ralph_loop.name} (#{result.ralph_loop.id})"
    puts "Parsed #{result.total_parsed} findings — created #{result.created} tasks, " \
         "skipped #{result.skipped} already-seeded"
    puts "Queue: #{result.ralph_loop.ralph_tasks.pending.count} pending " \
         "(#{result.ralph_loop.ralph_tasks.where(execution_type: 'human').count} human-decision)"
  end
end
