# frozen_string_literal: true

namespace :mcp do
  desc "Clear all MCP OAuth sessions, deactivate transient agents, and revoke tokens"
  task clear_sessions: :environment do
    puts "=== MCP Session Clear ==="
    puts ""

    # 1. Revoke all active sessions (triggers deactivate_agent_on_end callback)
    active_sessions = McpSession.active
    active_count = active_sessions.count
    puts "Revoking #{active_count} active session(s)..."
    active_sessions.find_each { |s| s.revoke! }

    # 2. Force-deactivate agents on recently-revoked sessions.
    #    The deactivate_agent_on_end callback skips cleanup during the 10-minute
    #    reconnect grace period. For a full clear we bypass that by calling
    #    deactivate_agent directly on any session that still has a linked agent.
    grace_sessions = McpSession.where(status: "revoked")
                               .where.not(ai_agent_id: nil)
    agents_deactivated = 0
    grace_sessions.find_each do |session|
      Ai::McpClientIdentityService.force_deactivate_agent(session)
      agents_deactivated += 1
    end
    puts "Force-deactivated #{agents_deactivated} agent(s) (bypassed grace period)"

    # 3. Revoke all Doorkeeper tokens for MCP-related OAuth applications
    app_ids = McpSession.where.not(oauth_application_id: nil)
                        .distinct
                        .pluck(:oauth_application_id)
    tokens_revoked = 0
    OauthApplication.where(id: app_ids).find_each do |app|
      count = app.access_tokens.where(revoked_at: nil).count
      app.revoke_all_tokens!
      tokens_revoked += count
    end
    puts "Revoked tokens for #{app_ids.size} OAuth app(s) (#{tokens_revoked} active token(s))"

    # 4. Delete all MCP session records
    total_deleted = McpSession.delete_all
    puts "Deleted #{total_deleted} session record(s)"

    # 5. Destroy all MCP client agents (now orphaned since all sessions are gone).
    #    Nullify FKs on conversations/messages to preserve history, remove team
    #    memberships, then destroy the agent records.
    mcp_agents = Ai::Agent.where(agent_type: "mcp_client")
    agents_destroyed = 0
    mcp_agents.find_each do |agent|
      Ai::Conversation.where(ai_agent_id: agent.id).update_all(ai_agent_id: nil)
      Ai::Message.where(ai_agent_id: agent.id).update_all(ai_agent_id: nil)
      Ai::AgentTeamMember.where(ai_agent_id: agent.id).destroy_all
      agent.destroy!
      agents_destroyed += 1
    end
    puts "Destroyed #{agents_destroyed} orphaned MCP client agent(s)"

    puts ""
    puts "=== Summary ==="
    puts "  Sessions revoked:      #{active_count}"
    puts "  Agents deactivated:    #{agents_deactivated}"
    puts "  OAuth apps processed:  #{app_ids.size}"
    puts "  Tokens revoked:        #{tokens_revoked}"
    puts "  Records deleted:       #{total_deleted}"
    puts "  Agents destroyed:      #{agents_destroyed}"
    puts "  Done."
  end

  # Reports MCP client agents duplicated per (account, client name, user) and,
  # only with CONFIRM=yes, merges them into the lowest-numbered keeper.
  #   rails mcp:dedupe_client_agents                       # report only
  #   rails mcp:dedupe_client_agents ACCOUNT_ID=<uuid>     # report one account
  #   rails mcp:dedupe_client_agents CONFIRM=yes           # merge + delete
  desc "Report (and with CONFIRM=yes merge) duplicate MCP client agents"
  task dedupe_client_agents: :environment do
    account = ENV["ACCOUNT_ID"].present? ? Account.find(ENV["ACCOUNT_ID"]) : nil
    confirm = ENV["CONFIRM"] == "yes"
    result = Ai::McpClientIdentityService.merge_duplicate_agents!(confirm: confirm, account: account)
    label = ->(d) { "#{d[:name]} (#{d[:id]})" }
    drops = lambda do |d|
      d[:drops].empty? ? "drops none" : "drops " + d[:drops].map { |k, n| "#{k}=#{n}" }.join(" ")
    end

    puts "=== MCP Client Agent Duplicates ==="
    result[:groups].each do |g|
      puts "  #{g[:client_name]} / user #{g[:user_id]}: keep #{label.call(g[:keeper])}, #{g[:duplicates].size} duplicate(s)"
    end
    puts "Duplicates to merge: #{result[:count]}"
    puts "  first: #{result[:first].map(&label).join(', ')}" if result[:count].positive?
    puts "  last:  #{label.call(result[:last])}" if result[:count] > 3
    result[:groups].each do |g|
      g[:duplicates].reject { |d| d[:skip_reason] }.each { |d| puts "  #{label.call(d)} #{drops.call(d)}" }
    end
    result[:skipped].each { |d| puts "  skipped #{label.call(d)}: #{d[:reason]}" }

    if result[:dry_run]
      puts ""
      puts "Dry run: nothing changed. Re-run with CONFIRM=yes to merge #{result[:count]} agent(s)."
    else
      puts ""
      puts "Merged #{result[:merged]} agent(s)."
      result[:errors].each { |e| puts "  FAILED #{e[:name]} (#{e[:id]}): #{e[:error]}" }
    end
  end
end
