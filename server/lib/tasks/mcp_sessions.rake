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

    puts ""
    puts "=== Summary ==="
    puts "  Sessions revoked:      #{active_count}"
    puts "  Agents deactivated:    #{agents_deactivated}"
    puts "  OAuth apps processed:  #{app_ids.size}"
    puts "  Tokens revoked:        #{tokens_revoked}"
    puts "  Records deleted:       #{total_deleted}"
    puts "  Done."
  end
end
