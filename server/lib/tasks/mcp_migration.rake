# frozen_string_literal: true

namespace :mcp do
  desc "Migrate entire platform to MCP-only architecture"
  task migrate: :environment do
    puts "🚀 Starting complete MCP migration..."
    puts "⚠️  WARNING: This will remove all legacy AI services and channels"
    puts "📋 Creating backup before migration..."

    # Create backup
    migration_service = McpMigrationService.new
    backup_file = migration_service.create_migration_backup

    puts "✅ Backup created: #{backup_file}"
    puts ""

    # Auto-confirm for non-interactive execution
    confirmation = ENV["MCP_AUTO_CONFIRM"] || "y"
    puts "🔄 Auto-confirming migration (MCP_AUTO_CONFIRM=#{confirmation})"

    begin
      # Execute migration
      stats = migration_service.execute_complete_migration

      puts ""
      puts "🎉 MCP Migration completed successfully!"
      puts ""
      puts "📊 Migration Statistics:"
      puts "   • AI Agents migrated: #{stats[:agents_migrated]}"
      puts "   • Workflows migrated: #{stats[:workflows_migrated]}"
      puts "   • Legacy files removed: #{stats[:legacy_files_removed]}"
      puts "   • Errors encountered: #{stats[:errors_encountered]}"
      puts ""

      # Validate migration
      puts "🔍 Validating migration..."
      validation = migration_service.validate_migration

      puts "✅ Validation Results:"
      puts "   • Agents with MCP manifest: #{validation[:agents_with_mcp_manifest]}"
      puts "   • Workflows with MCP config: #{validation[:workflows_with_mcp_config]}"
      puts "   • Legacy files remaining: #{validation[:legacy_services_remaining]}"
      puts "   • MCP connections working: #{validation[:mcp_connections_working] ? '✅' : '❌'}"
      puts ""

      if validation[:mcp_connections_working]
        puts "🎯 Migration validation successful!"
        puts "💡 Next steps:"
        puts "   1. Run database migrations: rails db:migrate"
        puts "   2. Restart all services"
        puts "   3. Test MCP connections in frontend"
        puts "   4. Monitor system logs for any issues"
      else
        puts "⚠️  Migration validation failed - MCP connections not working"
        puts "🔧 Troubleshooting needed before proceeding"
      end

    rescue StandardError => e
      puts ""
      puts "❌ Migration failed: #{e.message}"
      puts "📋 Backup available at: #{backup_file}"
      puts "🔄 You can restore from backup if needed"
      exit 1
    end
  end

  desc "Migrate AI agents to MCP format"
  task migrate_agents: :environment do
    puts "🤖 Migrating AI agents to MCP format..."

    Account.find_each do |account|
      puts "Processing account: #{account.name}"

      migration_service = McpMigrationService.new(account: account)
      migration_service.migrate_agents_to_mcp

      puts "✅ Account #{account.name} agents migrated"
    end

    puts "🎉 All agents migrated to MCP format!"
  end

  desc "Migrate workflows to MCP orchestration"
  task migrate_workflows: :environment do
    puts "🔄 Migrating workflows to MCP orchestration..."

    Account.find_each do |account|
      puts "Processing account: #{account.name}"

      migration_service = McpMigrationService.new(account: account)
      migration_service.migrate_workflows_to_mcp

      puts "✅ Account #{account.name} workflows migrated"
    end

    puts "🎉 All workflows migrated to MCP orchestration!"
  end

  desc "Remove legacy AI services and files"
  task remove_legacy: :environment do
    puts "🗑️  Removing legacy AI services and files..."
    puts "⚠️  WARNING: This action is irreversible!"

    print "❓ Continue with legacy removal? (y/N): "
    confirmation = STDIN.gets.chomp.downcase

    unless confirmation == "y" || confirmation == "yes"
      puts "❌ Legacy removal cancelled"
      exit
    end

    migration_service = McpMigrationService.new

    # Remove legacy files
    migration_service.remove_legacy_services
    migration_service.remove_legacy_channels
    migration_service.remove_legacy_api_endpoints
    migration_service.update_frontend_imports

    puts "✅ Legacy files removed successfully"
    puts "💡 Remember to update your routes.rb to remove AI API routes"
  end

  desc "Validate MCP migration"
  task validate: :environment do
    puts "🔍 Validating MCP migration..."

    migration_service = McpMigrationService.new
    validation = migration_service.validate_migration

    puts ""
    puts "📊 Validation Results:"
    puts "=" * 50

    if validation[:agents_with_mcp_manifest] > 0
      puts "✅ Agents with MCP manifest: #{validation[:agents_with_mcp_manifest]}"
    else
      puts "❌ No agents found with MCP manifest"
    end

    if validation[:workflows_with_mcp_config] > 0
      puts "✅ Workflows with MCP config: #{validation[:workflows_with_mcp_config]}"
    else
      puts "❌ No workflows found with MCP config"
    end

    if validation[:legacy_services_remaining] == 0
      puts "✅ All legacy services removed"
    else
      puts "⚠️  Legacy services remaining: #{validation[:legacy_services_remaining]}"
    end

    if validation[:mcp_connections_working]
      puts "✅ MCP connections working"
    else
      puts "❌ MCP connections not working"
    end

    puts ""

    if validation[:mcp_connections_working] &&
       validation[:agents_with_mcp_manifest] > 0 &&
       validation[:legacy_services_remaining] == 0
      puts "🎉 MCP migration is complete and working!"
    else
      puts "⚠️  MCP migration validation failed"
      puts "🔧 Manual intervention required"
    end
  end

  desc "Test MCP connections and functionality"
  task test: :environment do
    puts "🧪 Testing MCP connections and functionality..."

    # Test basic MCP services
    puts "Testing MCP Protocol Service..."
    begin
      mcp_protocol = McpProtocolService.new
      init_response = mcp_protocol.initialize_connection({
        "protocolVersion" => "2024-11-05",
        "clientInfo" => { "name" => "rake_test" }
      })
      puts "✅ MCP Protocol Service working"
    rescue StandardError => e
      puts "❌ MCP Protocol Service failed: #{e.message}"
    end

    # Test MCP Registry
    puts "Testing MCP Registry Service..."
    begin
      mcp_registry = McpRegistryService.new
      tools = mcp_registry.list_tools
      puts "✅ MCP Registry Service working (#{tools.size} tools found)"
    rescue StandardError => e
      puts "❌ MCP Registry Service failed: #{e.message}"
    end

    # Test agent MCP functionality
    puts "Testing AI Agent MCP functionality..."
    begin
      agent = AiAgent.active.first
      if agent&.mcp_available?
        puts "✅ AI Agent MCP functionality working"
      else
        puts "⚠️  No MCP-enabled agents found"
      end
    rescue StandardError => e
      puts "❌ AI Agent MCP functionality failed: #{e.message}"
    end

    puts ""
    puts "🔬 MCP testing completed"
  end

  desc "Create MCP migration backup"
  task backup: :environment do
    puts "📋 Creating MCP migration backup..."

    migration_service = McpMigrationService.new
    backup_file = migration_service.create_migration_backup

    puts "✅ Backup created successfully: #{backup_file}"
    puts "💾 Backup contains:"
    puts "   • Agent configurations"
    puts "   • Workflow configurations"
    puts "   • Migration statistics"
    puts ""
    puts "💡 Store this backup safely before running migration"
  end

  desc "Generate MCP migration report"
  task report: :environment do
    puts "📊 Generating MCP migration report..."
    puts ""

    # Overall statistics
    total_agents = AiAgent.count
    agents_with_mcp = AiAgent.where.not(mcp_tool_manifest: {}).count
    total_workflows = AiWorkflow.count
    workflows_with_mcp = AiWorkflow.where.not(mcp_orchestration_config: {}).count

    puts "🔢 Overall Statistics:"
    puts "   • Total AI Agents: #{total_agents}"
    puts "   • Agents with MCP: #{agents_with_mcp} (#{((agents_with_mcp.to_f / total_agents) * 100).round(1)}%)"
    puts "   • Total Workflows: #{total_workflows}"
    puts "   • Workflows with MCP: #{workflows_with_mcp} (#{((workflows_with_mcp.to_f / total_workflows) * 100).round(1)}%)"
    puts ""

    # Account breakdown
    puts "📋 Account Breakdown:"
    Account.includes(:ai_agents, :ai_workflows).find_each do |account|
      account_agents = account.ai_agents.count
      account_mcp_agents = account.ai_agents.where.not(mcp_tool_manifest: {}).count
      account_workflows = account.ai_workflows.count
      account_mcp_workflows = account.ai_workflows.where.not(mcp_orchestration_config: {}).count

      puts "   #{account.name}:"
      puts "     • Agents: #{account_mcp_agents}/#{account_agents} MCP-enabled"
      puts "     • Workflows: #{account_mcp_workflows}/#{account_workflows} MCP-enabled"
    end

    puts ""

    # Migration readiness
    if agents_with_mcp == total_agents && workflows_with_mcp == total_workflows
      puts "🎉 Platform is fully migrated to MCP!"
    elsif agents_with_mcp > 0 || workflows_with_mcp > 0
      puts "⚠️  Platform is partially migrated to MCP"
      puts "💡 Run 'rails mcp:migrate' to complete migration"
    else
      puts "❌ Platform not yet migrated to MCP"
      puts "🚀 Run 'rails mcp:migrate' to start migration"
    end
  end
end
