# frozen_string_literal: true

namespace :claude do
  desc "Export platform agents as Claude Code subagent skeletons. Default: the CANONICAL set (global, " \
       "seeded agents) into .claude/agents/powernode/ (committed; freshness-gated). ACCOUNT_ID=<uuid> " \
       "(or INCLUDE_ACCOUNT=1 for the first account) exports that account's OWN agents instead, into " \
       ".claude/agents/powernode-local/ (gitignored). TARGET_DIR=<path> overrides the output directory."
  task sync_agents: :environment do
    account = if ENV["ACCOUNT_ID"].present?
      Account.find(ENV["ACCOUNT_ID"])
    elsif ENV["INCLUDE_ACCOUNT"].present?
      Account.order(:created_at).first or abort("INCLUDE_ACCOUNT set but no account exists")
    end

    if account.nil?
      puts "Syncing the CANONICAL Claude Code agent set (global seeded agents; set ACCOUNT_ID for an account's own agents)"
    else
      puts "Syncing Claude Code agent skeletons for the OWN agents of account: #{account.name} (#{account.id})"
    end

    result = Ai::ClaudeExport::AgentSkeletonSync.new(
      account: account,
      target_dir: ENV["TARGET_DIR"].presence
    ).sync!

    puts "#{result.total} syncable agent(s): #{result.written.size} written, " \
         "#{result.unchanged.size} unchanged, #{result.removed.size} stale removed"
    puts "  written: #{result.written.join(', ')}" if result.written.any?
    puts "  removed: #{result.removed.join(', ')}" if result.removed.any?
    if account.nil? && result.total.zero?
      puts "  NOTE: this database holds no canonical (global, is_system) agent — the platform agent seeds " \
           "have not run here, so nothing was exported."
    end
  end

  desc "Reverse path: read hand-authored Claude Code agent files (a file or directory of .claude/agents/*.md " \
       "WITHOUT the generated header) and file one Ai::AgentProposal (agent_create) per file with the would-be " \
       "canonical spec — nothing is created directly. ACCOUNT_ID=<uuid> selects the account (default: first)."
  task :import_agents, [ :path ] => :environment do |_t, args|
    path = args[:path].presence || ENV["IMPORT_PATH"].presence
    abort("usage: rails claude:import_agents[<path>]") if path.blank?
    abort("no such file or directory: #{path}") unless File.exist?(path)

    account = if ENV["ACCOUNT_ID"].present?
      Account.find(ENV["ACCOUNT_ID"])
    else
      Account.order(:created_at).first or abort("no account exists")
    end

    outcome = Ai::ClaudeExport::AgentImportProposer.new(account: account, path: path).propose!

    puts "#{outcome.proposals.size} agent_create proposal(s) filed for account #{account.name} (#{account.id})"
    outcome.proposals.each do |proposal|
      puts "  #{proposal.id}  #{proposal.proposed_changes['slug']}  (#{proposal.title})"
    end
    puts "  skipped (generated header / no frontmatter): #{outcome.skipped.join(', ')}" if outcome.skipped.any?
    puts "Review them in the platform (Ai::AgentProposal pending_review); approval queues the spec for seeding."
  end

  desc "Alias of claude:import_agents"
  task :propose_agents, [ :path ] => "claude:import_agents"
end
