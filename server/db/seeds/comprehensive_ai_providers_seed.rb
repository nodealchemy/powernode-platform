# frozen_string_literal: true

# Comprehensive AI Providers Seed Data
# Creates OpenAI, Grok (X.AI), Ollama, and Claude (Anthropic) AI providers
# for workflow agents and AI orchestration

puts "\n🤖 Creating Comprehensive AI Provider Ecosystem..."

admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account&.users&.find_by(email: "admin@powernode.org")

if admin_account && admin_user
  puts "✅ Using admin account: #{admin_account.name} (ID: #{admin_account.id})"
  puts "✅ Using admin user: #{admin_user.name} (ID: #{admin_user.id})"

  # Helper method to create AI Provider if it doesn't exist
  def create_or_find_ai_provider(account, user, provider_data)
    provider = account.ai_providers.find_by(name: provider_data[:name])
    if provider
      puts "⏭️  AI Provider already exists: #{provider_data[:name]}"
      return provider
    end

    puts "📡 Creating AI Provider: #{provider_data[:name]}"
    account.ai_providers.create!(
      name: provider_data[:name],
      provider_type: provider_data[:provider_type],
      api_base_url: provider_data[:api_base_url],
      api_endpoint: provider_data[:api_endpoint],
      capabilities: provider_data[:capabilities],
      supported_models: provider_data[:supported_models],
      configuration_schema: provider_data[:configuration_schema],
      rate_limits: provider_data[:rate_limits],
      pricing_info: provider_data[:pricing_info],
      documentation_url: provider_data[:documentation_url],
      is_active: true,
      requires_auth: provider_data[:requires_auth],
      supports_streaming: provider_data[:supports_streaming],
      supports_functions: provider_data[:supports_functions],
      supports_vision: provider_data[:supports_vision],
      supports_code_execution: provider_data[:supports_code_execution],
      priority_order: provider_data[:priority_order],
      metadata: provider_data[:metadata]
    )
  end

  # =============================================================================
  # PROVIDERS — one entry per Ai::ProviderCatalog config (the single source
  # of truth for built-in provider data; see app/models/ai/provider_catalog.rb)
  # =============================================================================

  created_providers = Ai::ProviderCatalog.all.each_with_object({}) do |provider_data, memo|
    provider = create_or_find_ai_provider(admin_account, admin_user, provider_data)
    puts "✅ #{provider_data[:name]} provider created/updated: #{provider.id}"
    memo[provider_data[:provider_type]] = provider
  end

  openai_provider = created_providers['openai']
  grok_provider = created_providers['grok']
  ollama_provider = created_providers['ollama']
  claude_provider = created_providers['anthropic']

  # =============================================================================
  # SUMMARY
  # =============================================================================

  puts "\n" + "=" * 80
  puts "✅ AI PROVIDER ECOSYSTEM SUCCESSFULLY CREATED"
  puts "=" * 80
  puts "\n📊 Provider Summary (by priority):"
  puts "   1. OpenAI          - #{openai_provider.supported_models.length} models (GPT-4.1, o3, o4-mini, GPT-4o)"
  puts "   2. Grok (X.AI)     - #{grok_provider.supported_models.length} models (Grok 3, Grok 3 Mini, Grok 2)"
  puts "   3. Claude (Anthropic) - #{claude_provider.supported_models.length} models (Opus 4.1, Sonnet 4.5, Haiku 4.5)"
  puts "   4. Ollama          - #{ollama_provider.supported_models&.length || 0} models (self-hosted, zero cost)"

  puts "\n🎯 Recommended Use Cases:"
  puts "   • Cost-First Default:  GPT-4.1 Mini → Grok 3 Mini → Haiku 4.5 → Ollama"
  puts "   • Best Coding:         Claude Sonnet 4.5, GPT-4.1"
  puts "   • Complex Agents:      Claude Sonnet 4.5, o3"
  puts "   • General Purpose:     GPT-4.1 Mini, Grok 3 Mini"
  puts "   • Cost Optimization:   GPT-4.1 Nano (cheapest), Ollama (free)"
  puts "   • Complex Reasoning:   Claude Opus 4.1, o3"
  puts "   • Low Latency:         Grok 3 Fast, Grok 3 Mini Fast"
  puts "   • Privacy/Offline:     Ollama (all models)"
  puts "   • Long Context:        GPT-4.1 family (1M tokens), Claude models (200K)"

  puts "\n💡 Next Steps:"
  puts "   1. Configure API keys in environment variables or credentials"
  puts "   2. Test provider connectivity"
  puts "   3. Create AI agents using these providers"
  puts "   4. Build workflows with multi-provider orchestration"

  puts "\n" + "=" * 80

else
  puts "❌ Error: Could not find admin account and user"
  puts "   Please ensure database is seeded with admin account first"
end
