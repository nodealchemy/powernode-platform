# frozen_string_literal: true

namespace :claude do
  desc "Sync platform Ai::Agent records to native Claude Code subagent skeletons under " \
       ".claude/agents/powernode/ (ACCOUNT_ID=<uuid> to override the default account; " \
       "TARGET_DIR=<path> to override the output directory, mainly for testing)"
  task sync_agents: :environment do
    account = if ENV["ACCOUNT_ID"].present?
      Account.find(ENV["ACCOUNT_ID"])
    else
      Account.order(:created_at).first
    end

    if account.nil?
      puts "No account found — syncing GLOBAL agents only (set ACCOUNT_ID to include an account's own agents)"
    else
      puts "Syncing Claude Code agent skeletons for account: #{account.name} (#{account.id})"
    end

    result = Ai::ClaudeExport::AgentSkeletonSync.new(
      account: account,
      target_dir: ENV["TARGET_DIR"].presence
    ).sync!

    puts "#{result.total} syncable agent(s): #{result.written.size} written, " \
         "#{result.unchanged.size} unchanged, #{result.removed.size} stale removed"
    puts "  written: #{result.written.join(', ')}" if result.written.any?
    puts "  removed: #{result.removed.join(', ')}" if result.removed.any?
  end
end
