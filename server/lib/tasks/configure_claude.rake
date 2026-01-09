# frozen_string_literal: true

namespace :ai do
  desc "Configure Claude API credentials from environment or argument"
  task configure_claude: :environment do
    api_key = ENV["ANTHROPIC_API_KEY"] || ENV["CLAUDE_API_KEY"]

    if api_key.blank?
      puts "ERROR: No API key provided."
      puts ""
      puts "Usage options:"
      puts "  1. Set environment variable: export ANTHROPIC_API_KEY=your-key"
      puts "  2. Run with variable: ANTHROPIC_API_KEY=your-key rails ai:configure_claude"
      puts ""
      exit 1
    end

    account = Account.first
    if account.nil?
      puts "ERROR: No account found. Run db:seed first."
      exit 1
    end

    # Find or create Anthropic provider
    claude_provider = account.ai_providers.find_or_create_by!(provider_type: "anthropic") do |p|
      p.name = "Claude AI (Anthropic)"
      p.slug = "anthropic"
      p.api_base_url = "https://api.anthropic.com/v1"
      p.api_endpoint = "https://api.anthropic.com/v1/messages"
      p.capabilities = %w[text_generation chat code_generation vision analysis]
      p.supported_models = [
        { "id" => "claude-opus-4-20250514", "name" => "Claude Opus 4", "context_length" => 200_000 },
        { "id" => "claude-sonnet-4-20250514", "name" => "Claude Sonnet 4", "context_length" => 200_000 },
        { "id" => "claude-haiku-3-20250514", "name" => "Claude Haiku 3", "context_length" => 200_000 }
      ]
      p.configuration_schema = {
        "api_version" => "2023-06-01",
        "auth_type" => "x-api-key",
        "supports_streaming" => true,
        "supports_functions" => true
      }
      p.is_active = true
    end

    puts "Claude Provider: #{claude_provider.name} (#{claude_provider.id})"

    # Create or update credential
    credential = claude_provider.ai_provider_credentials.find_or_initialize_by(
      account: account,
      name: "Default Claude API Key"
    )

    credential.assign_attributes(
      credentials: {
        "api_key" => api_key,
        "model" => "claude-sonnet-4-20250514"
      },
      is_active: true,
      is_default: true,
      access_scopes: ["*"],
      rate_limits: { "requests_per_minute" => 60 }
    )

    if credential.save
      puts "✓ Credential configured successfully!"
      puts "  ID: #{credential.id}"
      puts "  Key: #{api_key[0..10]}...#{api_key[-4..]}"
      puts "  Model: claude-sonnet-4-20250514"
    else
      puts "ERROR: Failed to save credential"
      puts credential.errors.full_messages.join("\n")
      exit 1
    end

    # Ensure Claude agents are linked
    claude_agents = account.ai_agents.where(ai_provider: claude_provider)
    puts ""
    puts "Claude Agents configured: #{claude_agents.count}"
    claude_agents.each do |agent|
      puts "  - #{agent.name} (#{agent.status})"
    end

    puts ""
    puts "✓ Claude configuration complete!"
    puts ""
    puts "Test with:"
    puts "  rails runner 'puts AiProviderCredential.find(\"#{credential.id}\").decrypted_credentials[\"api_key\"][0..10]'"
  end

  desc "List all AI providers and their credentials"
  task list_providers: :environment do
    account = Account.first

    puts "AI Providers for #{account.name}:"
    puts "=" * 60

    account.ai_providers.each do |provider|
      puts ""
      puts "#{provider.name} (#{provider.provider_type})"
      puts "  ID: #{provider.id}"
      puts "  Active: #{provider.is_active}"
      puts "  Endpoint: #{provider.api_endpoint}"

      creds = provider.ai_provider_credentials.where(account: account)
      if creds.any?
        puts "  Credentials:"
        creds.each do |c|
          status = c.is_active ? "active" : "inactive"
          default = c.is_default ? " (default)" : ""
          puts "    - #{c.name}: #{status}#{default}"
        end
      else
        puts "  Credentials: None configured"
      end

      agents = account.ai_agents.where(ai_provider: provider)
      if agents.any?
        puts "  Agents: #{agents.count}"
        agents.limit(3).each { |a| puts "    - #{a.name}" }
        puts "    ... and #{agents.count - 3} more" if agents.count > 3
      end
    end
  end
end
