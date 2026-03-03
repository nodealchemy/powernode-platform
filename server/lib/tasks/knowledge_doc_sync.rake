# frozen_string_literal: true

namespace :mcp do
  desc "Sync MCP knowledge stores to markdown docs for offline fallback"
  task sync_docs: :environment do
    account_id = ENV["ACCOUNT_ID"]

    account = if account_id.present?
      Account.find(account_id)
    else
      Account.joins(:ai_providers).where(ai_providers: { is_active: true }).first
    end

    unless account
      puts "No account found. Set ACCOUNT_ID or ensure an account has an active AI provider."
      exit 1
    end

    puts "Syncing knowledge docs for account: #{account.name} (#{account.id})"

    service = Ai::KnowledgeDocSyncService.new(account: account)
    result = service.sync_all!

    if result[:success]
      puts "Sync completed at #{result[:synced_at]}:"
      puts "  Learnings: #{result[:learnings][:count]} entries"
      puts "  Knowledge: #{result[:knowledge][:count]} entries"
      puts "  Skills:    #{result[:skills][:count]} entries"
      puts "  Graph:     #{result[:graph][:nodes]} nodes, #{result[:graph][:edges]} edges"
      puts "  TODOs:     #{result[:todos][:count]} items"
      puts "Output: docs/platform/knowledge/ + docs/TODO.md"
    else
      puts "Sync failed: #{result[:error]}"
      exit 1
    end
  end
end
