# frozen_string_literal: true

# Flexible Provider Examples
# Demonstrates capability-driven AI provider creation without type constraints

puts "🔧 Creating Flexible AI Provider Examples..."

admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account.users.find_by(email: "admin@powernode.org")

if admin_account && admin_user
  puts "✅ Using admin account: #{admin_account.name} (ID: #{admin_account.id})"
  puts "✅ Using admin user: #{admin_user.name} (ID: #{admin_user.id})"

  # Example 1: Multi-Modal AI Provider (capability-focused)
  multimodal_provider = admin_account.ai_providers.find_or_create_by(
    slug: 'multimodal-ai'
  ) do |provider|
    provider.name = "Multi-Modal AI Service"
    provider.provider_type = nil  # No type required!
    provider.api_base_url = "https://api.multimodal-ai.com/v1"
    provider.api_endpoint = "https://api.multimodal-ai.com/v1/generate"

    # Capabilities define what this provider can do
    provider.capabilities = [
      'text_generation',
      'image_generation',
      'image_analysis',
      'vision',
      'audio_transcription',
      'translation',
      'summarization'
    ]

    # Models are defined directly, not hardcoded by type
    provider.supported_models = [
      {
        'name' => 'multimodal-large',
        'id' => 'mm-large-v2',
        'display_name' => 'MultiModal Large',
        'capabilities' => [ 'text', 'vision', 'audio' ],
        'context_length' => 128000,
        'cost_per_1k_tokens' => { 'input' => 0.01, 'output' => 0.03 }
      },
      {
        'name' => 'vision-specialist',
        'id' => 'vision-v1',
        'display_name' => 'Vision Specialist',
        'capabilities' => [ 'vision', 'image_analysis' ],
        'context_length' => 50000,
        'cost_per_1k_tokens' => { 'input' => 0.005, 'output' => 0.015 }
      }
    ]

    # Configuration is capability-driven
    provider.configuration_schema = {
      'api_key' => {
        'type' => 'string',
        'description' => 'API key for multimodal service',
        'required' => true
      },
      'model' => {
        'type' => 'string',
        'default' => 'multimodal-large',
        'enum' => [ 'multimodal-large', 'vision-specialist' ]
      },
      'max_tokens' => {
        'type' => 'integer',
        'default' => 4000,
        'description' => 'Maximum tokens for generation'
      },
      'enable_vision' => {
        'type' => 'boolean',
        'default' => true,
        'description' => 'Enable vision capabilities'
      },
      'image_quality' => {
        'type' => 'string',
        'default' => 'high',
        'enum' => [ 'low', 'medium', 'high' ]
      }
    }

    provider.rate_limits = {
      'requests_per_minute' => 100,
      'tokens_per_minute' => 50000,
      'images_per_hour' => 1000
    }

    provider.is_active = true
    provider.supports_streaming = true
    provider.supports_functions = true
    provider.supports_vision = true
    provider.priority_order = 20

    provider.metadata = {
      'provider_category' => 'multimodal',
      'specialties' => [ 'vision', 'audio', 'multimodal' ],
      'flexible_configuration' => true,
      'capability_driven' => true
    }
  end

  # Example 2: Local Code Assistant (no type needed)
  code_assistant = admin_account.ai_providers.find_or_create_by(
    slug: 'local-code-assistant'
  ) do |provider|
    provider.name = "Local Code Assistant"
    provider.provider_type = 'local'  # Optional categorization
    provider.api_base_url = "http://localhost:8080"
    provider.api_endpoint = "http://localhost:8080/v1/completions"

    # Code-focused capabilities
    provider.capabilities = [
      'code_generation',
      'code_execution',
      'text_generation',
      'reasoning',
      'analysis'
    ]

    provider.supported_models = [
      {
        'name' => 'codellama-7b',
        'id' => 'codellama-7b-instruct',
        'display_name' => 'Code Llama 7B',
        'capabilities' => [ 'code', 'instruction_following' ],
        'context_length' => 16384
      },
      {
        'name' => 'starcoder-3b',
        'id' => 'starcoder-3b',
        'display_name' => 'StarCoder 3B',
        'capabilities' => [ 'code', 'fast_inference' ],
        'context_length' => 8192
      }
    ]

    provider.configuration_schema = {
      'model' => {
        'type' => 'string',
        'default' => 'codellama-7b',
        'description' => 'Code model to use'
      },
      'temperature' => {
        'type' => 'number',
        'default' => 0.1,
        'description' => 'Low temperature for code generation'
      },
      'max_tokens' => {
        'type' => 'integer',
        'default' => 2048,
        'description' => 'Maximum tokens for code completion'
      },
      'stop_sequences' => {
        'type' => 'array',
        'default' => [ '```', '\n\n' ],
        'description' => 'Stop sequences for code generation'
      }
    }

    provider.rate_limits = {}  # No limits for local
    provider.is_active = true
    provider.requires_auth = false  # Local service
    provider.supports_streaming = true
    provider.supports_code_execution = true
    provider.priority_order = 30

    provider.metadata = {
      'provider_category' => 'local',
      'deployment_type' => 'self_hosted',
      'specialties' => [ 'code_generation', 'fast_inference' ],
      'cost_model' => 'free'
    }
  end

  # Example 3: API Gateway Provider (aggregates multiple services)
  api_gateway = admin_account.ai_providers.find_or_create_by(
    slug: 'ai-api-gateway'
  ) do |provider|
    provider.name = "AI API Gateway"
    provider.provider_type = 'api_gateway'
    provider.api_base_url = "https://gateway.ai-services.com/v1"
    provider.api_endpoint = "https://gateway.ai-services.com/v1/route"

    # Comprehensive capabilities (routes to best provider)
    provider.capabilities = [
      'text_generation',
      'chat',
      'reasoning',
      'code_generation',
      'image_generation',
      'translation',
      'summarization',
      'function_calling'
    ]

    provider.supported_models = [
      {
        'name' => 'auto-route',
        'id' => 'auto-route-v1',
        'display_name' => 'Auto-Route (Best Available)',
        'capabilities' => [ 'all' ],
        'description' => 'Automatically routes to best available model'
      },
      {
        'name' => 'cost-optimized',
        'id' => 'cost-optimized-v1',
        'display_name' => 'Cost Optimized Routing',
        'capabilities' => [ 'text', 'cost_efficient' ],
        'description' => 'Routes to most cost-effective model'
      },
      {
        'name' => 'performance-optimized',
        'id' => 'performance-optimized-v1',
        'display_name' => 'Performance Optimized',
        'capabilities' => [ 'text', 'fast_response' ],
        'description' => 'Routes to fastest available model'
      }
    ]

    provider.configuration_schema = {
      'api_key' => {
        'type' => 'string',
        'description' => 'Gateway API key',
        'required' => true
      },
      'routing_strategy' => {
        'type' => 'string',
        'default' => 'auto',
        'enum' => [ 'auto', 'cost', 'performance', 'capability' ],
        'description' => 'How to route requests'
      },
      'fallback_enabled' => {
        'type' => 'boolean',
        'default' => true,
        'description' => 'Enable fallback to other providers'
      },
      'max_retries' => {
        'type' => 'integer',
        'default' => 3,
        'description' => 'Maximum retry attempts'
      }
    }

    provider.rate_limits = {
      'requests_per_minute' => 1000,
      'tokens_per_minute' => 500000
    }

    provider.is_active = true
    provider.supports_streaming = true
    provider.supports_functions = true
    provider.priority_order = 5  # High priority gateway

    provider.metadata = {
      'provider_category' => 'gateway',
      'routing_enabled' => true,
      'multi_provider' => true,
      'load_balancing' => true,
      'fallback_support' => true
    }
  end

  puts "✅ Created Multi-Modal AI Service (ID: #{multimodal_provider.id})"
  puts "✅ Created Local Code Assistant (ID: #{code_assistant.id})"
  puts "✅ Created AI API Gateway (ID: #{api_gateway.id})"

  puts "\n📊 Flexible Provider Examples Summary:"
  puts "   Multi-Modal Provider: #{multimodal_provider.capabilities.count} capabilities"
  puts "   Code Assistant: #{code_assistant.capabilities.count} capabilities"
  puts "   API Gateway: #{api_gateway.capabilities.count} capabilities"

  puts "\n💡 Key Benefits:"
  puts "   ✅ No type constraints - providers defined by capabilities"
  puts "   ✅ Flexible model definitions - not hardcoded by type"
  puts "   ✅ Custom configuration schemas - tailored to provider needs"
  puts "   ✅ Capability-driven validation - ensures meaningful functionality"
  puts "   ✅ Provider-specific metadata - rich customization options"

else
  puts "❌ Missing required data (account or user)"
  puts "   Account: #{admin_account&.name || 'NOT FOUND'}"
  puts "   User: #{admin_user&.name || 'NOT FOUND'}"
end

puts "✅ Flexible provider examples completed!"
