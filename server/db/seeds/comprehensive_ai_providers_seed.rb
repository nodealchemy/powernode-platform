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
        'recommended_for' => [ 'cost_effective', 'high_volume', 'simple_tasks' ]
      },
      {
        'name' => 'gpt-4-turbo',
        'id' => 'gpt-4-turbo-2024-04-09',
        'display_name' => 'GPT-4 Turbo',
        'context_length' => 128000,
        'max_output_tokens' => 4096,
        'cost_per_1k_tokens' => {
          'input' => 0.01,
          'output' => 0.03
        },
        'capabilities' => [ 'text', 'vision', 'function_calling', 'json_mode' ],
        'recommended_for' => [ 'complex_reasoning', 'large_context', 'multi_step_tasks' ]
      },
      {
        'name' => 'gpt-3.5-turbo',
        'id' => 'gpt-3.5-turbo',
        'display_name' => 'GPT-3.5 Turbo',
        'context_length' => 16385,
        'max_output_tokens' => 4096,
        'cost_per_1k_tokens' => {
          'input' => 0.0005,
          'output' => 0.0015
        },
        'capabilities' => [ 'text', 'function_calling' ],
        'recommended_for' => [ 'simple_chat', 'basic_automation', 'high_speed' ]
      },
      {
        'name' => 'o1-preview',
        'id' => 'o1-preview',
        'display_name' => 'o1 Preview',
        'context_length' => 128000,
        'max_output_tokens' => 32768,
        'cost_per_1k_tokens' => {
          'input' => 0.015,
          'output' => 0.06
        },
        'capabilities' => [ 'advanced_reasoning', 'complex_problem_solving' ],
        'recommended_for' => [ 'math', 'coding', 'scientific_reasoning', 'complex_analysis' ]
      },
      {
        'name' => 'o1-mini',
        'id' => 'o1-mini',
        'display_name' => 'o1 Mini',
        'context_length' => 128000,
        'max_output_tokens' => 65536,
        'cost_per_1k_tokens' => {
          'input' => 0.00110,
          'output' => 0.00440
        },
        'capabilities' => [ 'reasoning', 'coding', 'stem' ],
        'recommended_for' => [ 'coding_tasks', 'stem_reasoning', 'faster_reasoning' ]
      }
    ],
    configuration_schema: {
      'api_version' => 'v1',
      'auth_type' => 'bearer',
      'default_model' => 'gpt-4o',
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
    priority_order: 2,
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
    provider_type: 'custom',
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
        'name' => 'grok-beta',
        'id' => 'grok-beta',
        'display_name' => 'Grok Beta',
        'context_length' => 131072,
        'max_output_tokens' => 4096,
        'cost_per_1k_tokens' => {
          'input' => 0.005,
          'output' => 0.015
        },
        'capabilities' => [ 'text', 'real_time_data', 'conversation', 'function_calling' ],
        'recommended_for' => [ 'real_time_information', 'conversational_ai', 'up_to_date_data' ]
      },
      {
        'name' => 'grok-vision-beta',
        'id' => 'grok-vision-beta',
        'display_name' => 'Grok Vision Beta',
        'context_length' => 8192,
        'max_output_tokens' => 4096,
        'cost_per_1k_tokens' => {
          'input' => 0.005,
          'output' => 0.015
        },
        'capabilities' => [ 'text', 'vision', 'image_analysis' ],
        'recommended_for' => [ 'vision_tasks', 'image_understanding', 'multi_modal' ]
      }
    ],
    configuration_schema: {
      'api_version' => 'v1',
      'auth_type' => 'bearer',
      'default_model' => 'grok-beta',
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
    supports_vision: true,
    supports_code_execution: false,
    priority_order: 3,
    metadata: {
      'organization' => 'X.AI (xAI)',
      'api_key_env' => 'XAI_API_KEY',
      'strengths' => [ 'real_time_data', 'conversational_ai', 'up_to_date_information' ],
      'use_cases' => [ 'real_time_queries', 'current_events', 'conversational_agents', 'vision_analysis' ],
      'notes' => 'Access to real-time data and X platform integration'
    }
  })

  puts "✅ Grok (X.AI) provider created/updated: #{grok_provider.id}"

  # =============================================================================
  # 3. OLLAMA PROVIDER (Local/Self-Hosted)
  # =============================================================================

  ollama_provider = create_or_find_ai_provider(admin_account, admin_user, {
    name: 'Ollama (Local)',
    provider_type: 'ollama',
    api_base_url: 'http://localhost:11434',
    api_endpoint: 'http://localhost:11434/api/chat',
    capabilities: [
      'text_generation',
      'chat',
      'conversation',
      'code_generation',
      'text_embedding'
    ],
    supported_models: [
      {
        'name' => 'llama3.3',
        'id' => 'llama3.3:latest',
        'display_name' => 'Llama 3.3 70B',
        'context_length' => 128000,
        'max_output_tokens' => 4096,
        'cost_per_1k_tokens' => {
          'input' => 0.0,
          'output' => 0.0
        },
        'capabilities' => [ 'text', 'reasoning', 'multilingual' ],
        'recommended_for' => [ 'general_purpose', 'cost_free', 'privacy_sensitive' ]
      },
      {
        'name' => 'llama3.2',
        'id' => 'llama3.2:latest',
        'display_name' => 'Llama 3.2',
        'context_length' => 128000,
        'max_output_tokens' => 2048,
        'cost_per_1k_tokens' => {
          'input' => 0.0,
          'output' => 0.0
        },
        'capabilities' => [ 'text', 'vision', 'lightweight' ],
        'recommended_for' => [ 'vision_tasks', 'edge_devices', 'local_deployment' ]
      },
      {
        'name' => 'mistral',
        'id' => 'mistral:latest',
        'display_name' => 'Mistral 7B',
        'context_length' => 32768,
        'max_output_tokens' => 8192,
        'cost_per_1k_tokens' => {
          'input' => 0.0,
          'output' => 0.0
        },
        'capabilities' => [ 'text', 'fast_inference', 'efficient' ],
        'recommended_for' => [ 'quick_responses', 'local_hosting', 'resource_efficient' ]
      },
      {
        'name' => 'codellama',
        'id' => 'codellama:latest',
        'display_name' => 'Code Llama',
        'context_length' => 16384,
        'max_output_tokens' => 4096,
        'cost_per_1k_tokens' => {
          'input' => 0.0,
          'output' => 0.0
        },
        'capabilities' => [ 'code', 'programming', 'debugging' ],
        'recommended_for' => [ 'code_generation', 'code_review', 'programming_assistance' ]
      },
      {
        'name' => 'qwen2.5-coder',
        'id' => 'qwen2.5-coder:latest',
        'display_name' => 'Qwen 2.5 Coder',
        'context_length' => 131072,
        'max_output_tokens' => 8192,
        'cost_per_1k_tokens' => {
          'input' => 0.0,
          'output' => 0.0
        },
        'capabilities' => [ 'code', 'long_context', 'reasoning' ],
        'recommended_for' => [ 'code_generation', 'large_codebases', 'refactoring' ]
      },
      {
        'name' => 'deepseek-r1',
        'id' => 'deepseek-r1:latest',
        'display_name' => 'DeepSeek R1',
        'context_length' => 64000,
        'max_output_tokens' => 8000,
        'cost_per_1k_tokens' => {
          'input' => 0.0,
          'output' => 0.0
        },
        'capabilities' => [ 'reasoning', 'problem_solving', 'math' ],
        'recommended_for' => [ 'complex_reasoning', 'math_problems', 'scientific_tasks' ]
      }
    ],
    configuration_schema: {
      'api_version' => 'v1',
      'auth_type' => 'none',
      'default_model' => 'llama3.3:latest',
      'supports_streaming' => true,
      'supports_functions' => false,
      'max_retries' => 3,
      'timeout_seconds' => 120,
      'keep_alive' => '5m'
    },
    rate_limits: {
      'requests_per_minute' => 1000,
      'tokens_per_minute' => 1000000,
      'requests_per_day' => 1000000,
      'concurrent_requests' => 10
    },
    pricing_info: {
      'currency' => 'USD',
      'billing_unit' => 'free',
      'cost_model' => 'self_hosted',
      'infrastructure_cost' => 'user_provided'
    },
    documentation_url: 'https://ollama.ai/docs',
    requires_auth: false,
    supports_streaming: true,
    supports_functions: false,
    supports_vision: true,
    supports_code_execution: false,
    priority_order: 4,
    metadata: {
      'organization' => 'Ollama',
      'deployment_type' => 'local',
      'api_key_env' => 'OLLAMA_HOST',
      'strengths' => [ 'privacy', 'no_cost', 'local_control', 'offline_capable' ],
      'use_cases' => [ 'privacy_sensitive_data', 'offline_usage', 'cost_optimization', 'local_development' ],
      'notes' => 'Requires local Ollama installation. No API key needed. Free to use.',
      'installation' => 'https://ollama.ai/download'
    }
  })

  puts "✅ Ollama provider created/updated: #{ollama_provider.id}"

  # =============================================================================
  # 4. CLAUDE (ANTHROPIC) PROVIDER
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
      'default_model' => 'claude-sonnet-4-5-20250929',
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
    priority_order: 1,
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
  puts "\n📊 Provider Summary:"
  puts "   1. OpenAI          - #{openai_provider.supported_models.length} models (GPT-4o, o1, GPT-3.5)"
  puts "   2. Grok (X.AI)     - #{grok_provider.supported_models.length} models (Grok Beta, Grok Vision)"
  puts "   3. Ollama (Local)  - #{ollama_provider.supported_models.length} models (Llama, Mistral, CodeLlama)"
  puts "   4. Claude (Anthropic) - #{claude_provider.supported_models.length} models (Opus 4.1, Sonnet 4.5, Haiku 4.5, 3.5 Sonnet)"

  puts "\n🎯 Recommended Use Cases:"
  puts "   • Best Coding:         Claude Sonnet 4.5 (world's best coding model)"
  puts "   • Complex Agents:      Claude Sonnet 4.5, OpenAI o1-preview"
  puts "   • General Purpose:     OpenAI GPT-4o, Claude Sonnet 4.5"
  puts "   • Cost Optimization:   Ollama (free), GPT-4o Mini, Claude Haiku 4.5"
  puts "   • Complex Reasoning:   Claude Opus 4.1, OpenAI o1-preview"
  puts "   • Multi-Hour Tasks:    Claude Opus 4.1 (sustained 7+ hour workflows)"
  puts "   • Parallel Execution:  Claude Haiku 4.5 (fast + powerful)"
  puts "   • Vision Analysis:     OpenAI GPT-4o, Claude Sonnet 4.5, Grok Vision"
  puts "   • Real-Time Data:      Grok Beta"
  puts "   • Privacy/Offline:     Ollama (all models)"
  puts "   • Long Context:        Claude models (200K tokens, up to 1M beta)"

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
