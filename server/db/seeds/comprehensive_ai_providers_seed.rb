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
  # 1. OPENAI PROVIDER
  # =============================================================================

  openai_provider = create_or_find_ai_provider(admin_account, admin_user, {
    name: 'OpenAI',
    provider_type: 'openai',
    api_base_url: 'https://api.openai.com/v1',
    api_endpoint: 'https://api.openai.com/v1/chat/completions',
    capabilities: [
      'text_generation',
      'chat',
      'conversation',
      'code_generation',
      'reasoning',
      'analysis',
      'creative_writing',
      'function_calling',
      'vision',
      'image_generation',
      'text_embedding',
      'audio_transcription'
    ],
    supported_models: [
      {
        'name' => 'gpt-4.1',
        'id' => 'gpt-4.1',
        'display_name' => 'GPT-4.1',
        'context_length' => 1047576,
        'max_output_tokens' => 32768,
        'cost_per_1k_tokens' => {
          'input' => 0.002,
          'output' => 0.008
        },
        'capabilities' => [ 'text', 'vision', 'function_calling', 'structured_output' ],
        'recommended_for' => [ 'coding', 'instruction_following', 'long_context', 'agentic_tasks' ]
      },
      {
        'name' => 'gpt-4.1-mini',
        'id' => 'gpt-4.1-mini',
        'display_name' => 'GPT-4.1 Mini',
        'context_length' => 1047576,
        'max_output_tokens' => 32768,
        'cost_per_1k_tokens' => {
          'input' => 0.0004,
          'output' => 0.0016
        },
        'capabilities' => [ 'text', 'vision', 'function_calling', 'structured_output' ],
        'recommended_for' => [ 'cost_effective', 'high_volume', 'general_purpose', 'agentic_tasks' ]
      },
      {
        'name' => 'gpt-4.1-nano',
        'id' => 'gpt-4.1-nano',
        'display_name' => 'GPT-4.1 Nano',
        'context_length' => 1047576,
        'max_output_tokens' => 32768,
        'cost_per_1k_tokens' => {
          'input' => 0.0001,
          'output' => 0.0004
        },
        'capabilities' => [ 'text', 'function_calling', 'structured_output' ],
        'recommended_for' => [ 'classification', 'extraction', 'routing', 'ultra_low_cost' ]
      },
      {
        'name' => 'o3',
        'id' => 'o3',
        'display_name' => 'o3',
        'context_length' => 200000,
        'max_output_tokens' => 100000,
        'cost_per_1k_tokens' => {
          'input' => 0.002,
          'output' => 0.008
        },
        'capabilities' => [ 'advanced_reasoning', 'complex_problem_solving', 'function_calling' ],
        'recommended_for' => [ 'math', 'coding', 'scientific_reasoning', 'complex_analysis' ]
      },
      {
        'name' => 'o4-mini',
        'id' => 'o4-mini',
        'display_name' => 'o4 Mini',
        'context_length' => 200000,
        'max_output_tokens' => 100000,
        'cost_per_1k_tokens' => {
          'input' => 0.0011,
          'output' => 0.0044
        },
        'capabilities' => [ 'reasoning', 'coding', 'function_calling' ],
        'recommended_for' => [ 'coding_tasks', 'stem_reasoning', 'faster_reasoning' ]
      },
      {
        'name' => 'gpt-4o',
        'id' => 'gpt-4o',
        'display_name' => 'GPT-4o',
        'context_length' => 128000,
        'max_output_tokens' => 16384,
        'cost_per_1k_tokens' => {
          'input' => 0.0025,
          'output' => 0.01
        },
        'capabilities' => [ 'text', 'vision', 'audio', 'function_calling', 'structured_output' ],
        'recommended_for' => [ 'multi_modal_tasks', 'vision_analysis', 'general_purpose' ]
      },
      {
        'name' => 'gpt-4o-mini',
        'id' => 'gpt-4o-mini',
        'display_name' => 'GPT-4o Mini',
        'context_length' => 128000,
        'max_output_tokens' => 16384,
        'cost_per_1k_tokens' => {
          'input' => 0.00015,
          'output' => 0.0006
        },
        'capabilities' => [ 'text', 'vision', 'function_calling' ],
        'recommended_for' => [ 'legacy_cost_effective', 'high_volume' ]
      }
    ],
    configuration_schema: {
      'api_version' => 'v1',
      'auth_type' => 'bearer',
      'default_model' => 'gpt-4.1-mini',
      'supports_streaming' => true,
      'supports_functions' => true,
      'max_retries' => 3,
      'timeout_seconds' => 60
    },
    rate_limits: {
      'requests_per_minute' => 10000,
      'tokens_per_minute' => 2000000,
      'requests_per_day' => 100000
    },
    pricing_info: {
      'currency' => 'USD',
      'billing_unit' => 'per_1k_tokens',
      'has_batch_api' => true,
      'has_cached_tokens' => false
    },
    documentation_url: 'https://platform.openai.com/docs',
    requires_auth: true,
    supports_streaming: true,
    supports_functions: true,
    supports_vision: true,
    supports_code_execution: false,
    priority_order: 1,
    metadata: {
      'organization' => 'OpenAI',
      'api_key_env' => 'OPENAI_API_KEY',
      'strengths' => [ 'function_calling', 'vision', 'multi_modal', 'broad_capabilities' ],
      'use_cases' => [ 'chatbots', 'content_generation', 'code_assistance', 'vision_analysis', 'text_embedding' ]
    }
  })

  puts "✅ OpenAI provider created/updated: #{openai_provider.id}"

  # =============================================================================
  # 2. GROK (X.AI) PROVIDER
  # =============================================================================

  grok_provider = create_or_find_ai_provider(admin_account, admin_user, {
    name: 'Grok (X.AI)',
    provider_type: 'grok',
    api_base_url: 'https://api.x.ai/v1',
    api_endpoint: 'https://api.x.ai/v1/chat/completions',
    capabilities: [
      'text_generation',
      'chat',
      'conversation',
      'reasoning',
      'code_generation',
      'analysis',
      'function_calling'
    ],
    supported_models: [
      {
        'name' => 'grok-3',
        'id' => 'grok-3',
        'display_name' => 'Grok 3',
        'context_length' => 131072,
        'max_output_tokens' => 16384,
        'cost_per_1k_tokens' => {
          'input' => 0.003,
          'output' => 0.015
        },
        'capabilities' => [ 'text', 'reasoning', 'conversation', 'function_calling' ],
        'recommended_for' => [ 'complex_reasoning', 'analysis', 'general_purpose' ]
      },
      {
        'name' => 'grok-3-mini',
        'id' => 'grok-3-mini',
        'display_name' => 'Grok 3 Mini',
        'context_length' => 131072,
        'max_output_tokens' => 16384,
        'cost_per_1k_tokens' => {
          'input' => 0.0003,
          'output' => 0.0005
        },
        'capabilities' => [ 'text', 'reasoning', 'conversation', 'function_calling' ],
        'recommended_for' => [ 'cost_effective', 'high_volume', 'quick_tasks' ]
      },
      {
        'name' => 'grok-3-fast',
        'id' => 'grok-3-fast',
        'display_name' => 'Grok 3 Fast',
        'context_length' => 131072,
        'max_output_tokens' => 16384,
        'cost_per_1k_tokens' => {
          'input' => 0.005,
          'output' => 0.025
        },
        'capabilities' => [ 'text', 'reasoning', 'conversation', 'function_calling' ],
        'recommended_for' => [ 'low_latency', 'real_time', 'fast_responses' ]
      },
      {
        'name' => 'grok-3-mini-fast',
        'id' => 'grok-3-mini-fast',
        'display_name' => 'Grok 3 Mini Fast',
        'context_length' => 131072,
        'max_output_tokens' => 16384,
        'cost_per_1k_tokens' => {
          'input' => 0.0006,
          'output' => 0.004
        },
        'capabilities' => [ 'text', 'reasoning', 'conversation', 'function_calling' ],
        'recommended_for' => [ 'low_latency', 'cost_effective', 'simple_tasks' ]
      },
      {
        'name' => 'grok-2',
        'id' => 'grok-2',
        'display_name' => 'Grok 2',
        'context_length' => 131072,
        'max_output_tokens' => 8192,
        'cost_per_1k_tokens' => {
          'input' => 0.002,
          'output' => 0.01
        },
        'capabilities' => [ 'text', 'conversation', 'function_calling' ],
        'recommended_for' => [ 'general_purpose', 'legacy_workflows' ]
      }
    ],
    configuration_schema: {
      'api_version' => 'v1',
      'auth_type' => 'bearer',
      'default_model' => 'grok-3-mini',
      'supports_streaming' => true,
      'supports_functions' => true,
      'max_retries' => 3,
      'timeout_seconds' => 60
    },
    rate_limits: {
      'requests_per_minute' => 60,
      'tokens_per_minute' => 600000,
      'requests_per_day' => 10000
    },
    pricing_info: {
      'currency' => 'USD',
      'billing_unit' => 'per_1k_tokens',
      'has_batch_api' => false,
      'has_cached_tokens' => false
    },
    documentation_url: 'https://docs.x.ai',
    requires_auth: true,
    supports_streaming: true,
    supports_functions: true,
    supports_vision: false,
    supports_code_execution: false,
    priority_order: 2,
    metadata: {
      'organization' => 'X.AI (xAI)',
      'api_key_env' => 'XAI_API_KEY',
      'strengths' => [ 'reasoning', 'cost_effective', 'function_calling', 'fast_responses' ],
      'use_cases' => [ 'general_purpose', 'conversational_agents', 'cost_optimization', 'high_volume' ],
      'notes' => 'OpenAI-compatible API with competitive pricing'
    }
  })

  puts "✅ Grok (X.AI) provider created/updated: #{grok_provider.id}"

  # =============================================================================
  # OLLAMA (SELF-HOSTED) PROVIDER
  # =============================================================================

  ollama_provider = create_or_find_ai_provider(admin_account, admin_user, {
    name: 'Ollama',
    provider_type: 'ollama',
    api_base_url: ENV.fetch('OLLAMA_API_ENDPOINT', 'http://localhost:11434'),
    api_endpoint: "#{ENV.fetch('OLLAMA_API_ENDPOINT', 'http://localhost:11434')}/api/chat",
    capabilities: [
      'text_generation',
      'chat',
      'conversation',
      'code_generation',
      'analysis'
    ],
    supported_models: [
      {
        'name' => 'Qwen 2.5 14B',
        'id' => 'qwen2.5:14b',
        'display_name' => 'Qwen 2.5 14B',
        'context_length' => 32_768,
        'max_output_tokens' => 8_192,
        'cost_per_1k_tokens' => { 'input' => 0.0, 'output' => 0.0 },
        'capabilities' => %w[text_generation chat code_generation],
        'recommended_for' => 'Documentation writing, general text generation. Self-hosted, zero cost.'
      },
      {
        'name' => 'Llama 3.1 8B',
        'id' => 'llama3.1:8b',
        'display_name' => 'Llama 3.1 8B',
        'context_length' => 131_072,
        'max_output_tokens' => 8_192,
        'cost_per_1k_tokens' => { 'input' => 0.0, 'output' => 0.0 },
        'capabilities' => %w[text_generation chat code_generation],
        'recommended_for' => 'General purpose fallback. Self-hosted, zero cost.'
      },
      {
        'name' => 'Qwen 2.5 Coder 14B',
        'id' => 'qwen2.5-coder:14b',
        'display_name' => 'Qwen 2.5 Coder 14B',
        'context_length' => 32_768,
        'max_output_tokens' => 8_192,
        'cost_per_1k_tokens' => { 'input' => 0.0, 'output' => 0.0 },
        'capabilities' => %w[text_generation chat code_generation],
        'recommended_for' => 'Code generation and review. Self-hosted, zero cost.'
      }
    ],
    configuration_schema: {
      'auth_type' => 'none',
      'base_url' => ENV.fetch('OLLAMA_API_ENDPOINT', 'http://localhost:11434'),
      'supports_streaming' => true,
      'self_hosted' => true,
      'max_retries' => 2,
      'timeout_seconds' => 120,
      'notes' => 'Self-hosted Ollama instance. Pull models with: ollama pull <model_name>'
    },
    rate_limits: {
      'requests_per_minute' => 1000,
      'tokens_per_minute' => 10_000_000,
      'requests_per_day' => 100_000
    },
    pricing_info: {
      'currency' => 'USD',
      'billing_unit' => 'per_1k_tokens',
      'has_batch_api' => false,
      'has_cached_tokens' => false,
      'self_hosted' => true
    },
    documentation_url: 'https://ollama.com/docs',
    requires_auth: false,
    supports_streaming: true,
    supports_functions: false,
    supports_vision: false,
    supports_code_execution: false,
    priority_order: 4,
    metadata: {
      'organization' => 'Ollama',
      'strengths' => %w[privacy zero_cost self_hosted offline_capable],
      'use_cases' => %w[documentation text_generation code_generation privacy_sensitive],
      'special_features' => %w[self_hosted zero_cost offline_capable]
    }
  })

  puts "✅ Ollama provider created/updated: #{ollama_provider.id}"

  # =============================================================================
  # 3. CLAUDE (ANTHROPIC) PROVIDER
  # =============================================================================

  claude_provider = create_or_find_ai_provider(admin_account, admin_user, {
    name: 'Claude AI (Anthropic)',
    provider_type: 'anthropic',
    api_base_url: 'https://api.anthropic.com/v1',
    api_endpoint: 'https://api.anthropic.com/v1/messages',
    capabilities: [
      'text_generation',
      'chat',
      'conversation',
      'reasoning',
      'analysis',
      'code_generation',
      'creative_writing',
      'structured_output',
      'function_calling',
      'document_analysis',
      'vision'
    ],
    supported_models: [
      {
        'name' => 'claude-opus-4.1',
        'id' => 'claude-opus-4-1-20250805',
        'display_name' => 'Claude Opus 4.1',
        'context_length' => 200000,
        'max_output_tokens' => 32000,
        'cost_per_1k_tokens' => {
          'input' => 0.015,
          'output' => 0.075
        },
        'capabilities' => [ 'text', 'code', 'complex_reasoning', 'highest_intelligence', 'vision', 'long_context', 'advanced_analysis', 'extended_thinking', 'agentic_workflows' ],
        'recommended_for' => [ 'complex_workflows', 'strategic_analysis', 'advanced_reasoning', 'research', 'critical_decision_making', 'multi_hour_tasks' ]
      },
      {
        'name' => 'claude-sonnet-4.5',
        'id' => 'claude-sonnet-4-5-20250929',
        'display_name' => 'Claude Sonnet 4.5',
        'context_length' => 200000,
        'max_output_tokens' => 64000,
        'cost_per_1k_tokens' => {
          'input' => 0.003,
          'output' => 0.015
        },
        'capabilities' => [ 'text', 'code', 'analysis', 'reasoning', 'vision', 'long_context', 'best_coding', 'complex_agents', 'computer_use' ],
        'recommended_for' => [ 'coding', 'complex_agents', 'workflow_orchestration', 'agentic_tasks', 'general_purpose' ]
      },
      {
        'name' => 'claude-haiku-4.5',
        'id' => 'claude-haiku-4-5-20251001',
        'display_name' => 'Claude Haiku 4.5',
        'context_length' => 200000,
        'max_output_tokens' => 64000,
        'cost_per_1k_tokens' => {
          'input' => 0.001,
          'output' => 0.005
        },
        'capabilities' => [ 'text', 'code', 'fast_response', 'vision', 'cost_effective', 'high_performance' ],
        'recommended_for' => [ 'quick_tasks', 'parallel_execution', 'high_volume', 'cost_optimization', 'coding_tasks' ]
      },
      {
        'name' => 'claude-3-5-sonnet',
        'id' => 'claude-3-5-sonnet-20241022',
        'display_name' => 'Claude 3.5 Sonnet (Legacy)',
        'context_length' => 200000,
        'max_output_tokens' => 8192,
        'cost_per_1k_tokens' => {
          'input' => 0.003,
          'output' => 0.015
        },
        'capabilities' => [ 'text', 'code', 'analysis', 'reasoning', 'vision', 'long_context' ],
        'recommended_for' => [ 'legacy_workflows', 'backward_compatibility' ]
      }
    ],
    configuration_schema: {
      'api_version' => '2023-06-01',
      'auth_type' => 'x-api-key',
      'default_model' => 'claude-haiku-4-5-20251001',
      'supports_streaming' => true,
      'supports_functions' => true,
      'max_retries' => 3,
      'timeout_seconds' => 60,
      'anthropic_version' => '2023-06-01'
    },
    rate_limits: {
      'requests_per_minute' => 4000,
      'tokens_per_minute' => 400000,
      'requests_per_day' => 1000000
    },
    pricing_info: {
      'currency' => 'USD',
      'billing_unit' => 'per_1k_tokens',
      'has_batch_api' => true,
      'has_cached_tokens' => true,
      'cache_discount' => 0.9
    },
    documentation_url: 'https://docs.anthropic.com',
    requires_auth: true,
    supports_streaming: true,
    supports_functions: true,
    supports_vision: true,
    supports_code_execution: false,
    priority_order: 3,
    metadata: {
      'organization' => 'Anthropic',
      'api_key_env' => 'ANTHROPIC_API_KEY',
      'strengths' => [ 'long_context', 'reasoning', 'safety', 'helpfulness', 'vision', 'document_analysis' ],
      'use_cases' => [ 'complex_reasoning', 'document_analysis', 'code_generation', 'creative_writing', 'research' ],
      'special_features' => [ 'prompt_caching', 'extended_thinking', 'computer_use' ]
    }
  })

  puts "✅ Claude (Anthropic) provider created/updated: #{claude_provider.id}"

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
