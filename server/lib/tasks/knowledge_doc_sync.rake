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
      puts ""

      result.each do |scope, scope_data|
        next unless scope_data.is_a?(Hash) && scope_data.key?(:learnings)

        label = scope.to_s.titleize
        learnings_count = scope_data.dig(:learnings, :count) || 0
        knowledge_count = scope_data.dig(:knowledge, :count) || 0
        skills_count = scope_data.dig(:skills, :count) || 0

        parts = []
        parts << "#{learnings_count} learnings" if learnings_count > 0
        parts << "#{knowledge_count} knowledge" if knowledge_count > 0
        parts << "#{skills_count} skills" if skills_count > 0

        if scope_data[:graph]
          parts << "#{scope_data[:graph][:nodes]} graph nodes"
          parts << "#{scope_data[:graph][:edges]} graph edges"
        end
        parts << "#{scope_data[:todos][:count]} TODOs" if scope_data[:todos]

        puts "  #{label.ljust(12)} #{parts.join(', ')}"
      end

      puts ""
      puts "Output: docs/platform/knowledge/ + extension docs/ + docs/TODO.md"
    else
      puts "Sync failed: #{result[:error]}"
      exit 1
    end
  end
end
