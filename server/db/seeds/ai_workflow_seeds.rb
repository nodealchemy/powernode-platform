# frozen_string_literal: true

# AI Workflow System Seeds
# This file creates sample workflows, agents, and supporting data for demonstration

puts "🤖 Seeding AI Workflow System..."

# Find the admin account (assuming it exists)
admin_account = Account.find_by(name: 'Admin Account') || Account.first
unless admin_account
  puts "❌ No admin account found. Please run main seeds first."
  return
end

# Find the admin user (look for super_admin role)
admin_user = admin_account.users.joins(:roles).where(roles: { name: 'super_admin' }).first ||
             admin_account.users.first

unless admin_user
  puts "❌ No admin user found in admin account."
  return
end

puts "✅ Using admin account: #{admin_account.name} (ID: #{admin_account.id})"
puts "✅ Using admin user: #{admin_user.full_name} (ID: #{admin_user.id})"

# Helper method to create AI Provider if it doesn't exist
def create_or_find_ai_provider(account, user, provider_data)
  provider = account.ai_providers.find_by(name: provider_data[:name])
  return provider if provider

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
    is_active: true,
    metadata: provider_data[:metadata]
  )
end

# Helper method to create AI Agent if it doesn't exist
def create_or_find_ai_agent(account, user, provider, agent_data)
  agent = account.ai_agents.find_by(name: agent_data[:name])
  return agent if agent

  puts "🤖 Creating AI Agent: #{agent_data[:name]}"
  account.ai_agents.create!(
    name: agent_data[:name],
    description: agent_data[:description],
    agent_type: agent_data[:agent_type],
    provider: provider,
    creator: user,
    mcp_capabilities: { 'chat' => true, 'text_generation' => true },
    mcp_metadata: agent_data[:configuration],
    metadata: agent_data[:metadata],
    status: 'active'
  )
end

# 1. Create AI Providers
puts "\n📡 Creating AI Providers..."

# Ollama Provider (Remote Server)
ollama_base_url = ENV['OLLAMA_BASE_URL'] || 'http://localhost:11434'
ollama_provider = create_or_find_ai_provider(admin_account, admin_user, {
  name: 'Remote Ollama Server',
  provider_type: 'custom',
  api_base_url: ollama_base_url,
  api_endpoint: "#{ollama_base_url}/api/generate",
  capabilities: [ 'text_generation', 'chat' ],
  supported_models: [
    { 'name' => 'llama2', 'id' => 'llama2' },
    { 'name' => 'llama2:13b', 'id' => 'llama2:13b' },
    { 'name' => 'codellama', 'id' => 'codellama' },
    { 'name' => 'mistral', 'id' => 'mistral' },
    { 'name' => 'neural-chat', 'id' => 'neural-chat' }
  ],
  configuration_schema: {
    'api_version' => 'v1',
    'timeout' => 60,
    'max_retries' => 3,
    'models' => [
      'llama2',
      'llama2:13b',
      'codellama',
      'mistral',
      'neural-chat'
    ],
    'default_model' => 'llama2',
    'streaming' => true,
    'base_url' => ollama_base_url
  },
  rate_limits: {},
  metadata: {
    'setup_instructions' => 'Configure your Ollama server URL via OLLAMA_BASE_URL environment variable (default: http://localhost:11434). Pull models with: ollama pull llama2',
    'recommended_models' => [ 'llama2', 'codellama' ],
    'cost_per_token' => 0.0,
    'remote_deployment' => true,
    'configuration_notes' => 'Set OLLAMA_BASE_URL environment variable to point to your Ollama server instance'
  }
})

# OpenAI Provider (for comparison)
openai_provider = create_or_find_ai_provider(admin_account, admin_user, {
  name: 'OpenAI GPT',
  provider_type: 'openai',
  api_base_url: 'https://api.openai.com/v1',
  api_endpoint: 'https://api.openai.com/v1/chat/completions',
  capabilities: [ 'text_generation', 'chat' ],
  supported_models: [
    { 'name' => 'gpt-4o', 'id' => 'gpt-4o' },
    { 'name' => 'gpt-4o-mini', 'id' => 'gpt-4o-mini' },
    { 'name' => 'gpt-3.5-turbo', 'id' => 'gpt-3.5-turbo' }
  ],
  configuration_schema: {
    'api_version' => 'v1',
    'timeout' => 30,
    'max_retries' => 3,
    'models' => [
      'gpt-4o',
      'gpt-4o-mini',
      'gpt-3.5-turbo'
    ],
    'default_model' => 'gpt-4o-mini',
    'streaming' => true
  },
  rate_limits: {
    'requests_per_minute' => 3500,
    'tokens_per_minute' => 90000
  },
  metadata: {
    'cost_per_1k_tokens' => {
      'input' => 0.00015,
      'output' => 0.0006
    },
    'context_window' => 128000,
    'requires_api_key' => true
  }
})

# 2. Create AI Agents
puts "\n🤖 Creating AI Agents..."

# Blog Content Generator Agent
blog_generator_agent = create_or_find_ai_agent(admin_account, admin_user, ollama_provider, {
  name: 'Blog Content Generator',
  description: 'Generates comprehensive blog posts on various topics with SEO optimization',
  agent_type: 'content_generator',
  configuration: {
    'instructions' => 'You are a professional content writer specializing in creating engaging, informative blog posts. Write in a conversational yet authoritative tone, include relevant examples, and structure content with clear headings and subheadings.',
    'system_prompt' => 'You are a professional content writer specializing in creating engaging, informative blog posts. Write in a conversational yet authoritative tone, include relevant examples, and structure content with clear headings and subheadings.',
    'model' => 'llama2',
    'temperature' => 0.7,
    'max_tokens' => 2000,
    'output_format' => 'markdown',
    'include_meta' => true,
    'seo_optimization' => true
  },
  metadata: {
    'specialties' => [ 'technology', 'business', 'lifestyle', 'education' ],
    'output_format' => 'markdown',
    'average_words' => 1500,
    'typical_execution_time' => '60-120 seconds'
  }
})

# SEO Optimizer Agent
seo_optimizer_agent = create_or_find_ai_agent(admin_account, admin_user, ollama_provider, {
  name: 'SEO Optimizer',
  description: 'Analyzes and optimizes content for search engine visibility',
  agent_type: 'data_analyst',
  configuration: {
    'instructions' => 'You are an SEO specialist. Analyze the provided content and suggest improvements for search engine optimization. Focus on keyword density, meta descriptions, header structure, and readability.',
    'system_prompt' => 'You are an SEO specialist. Analyze the provided content and suggest improvements for search engine optimization. Focus on keyword density, meta descriptions, header structure, and readability.',
    'model' => 'llama2',
    'temperature' => 0.3,
    'max_tokens' => 1000,
    'analysis_areas' => [
      'keyword_optimization',
      'meta_descriptions',
      'header_structure',
      'readability_score',
      'internal_linking'
    ]
  },
  metadata: {
    'focus_areas' => [ 'on-page SEO', 'content optimization', 'keyword analysis' ],
    'output_type' => 'structured_analysis',
    'typical_execution_time' => '30-45 seconds'
  }
})

# Code Reviewer Agent
code_reviewer_agent = create_or_find_ai_agent(admin_account, admin_user, ollama_provider, {
  name: 'Code Review Assistant',
  description: 'Reviews code for best practices, security issues, and optimization opportunities',
  agent_type: 'code_assistant',
  configuration: {
    'instructions' => 'You are a senior software engineer conducting code reviews. Analyze the provided code for security vulnerabilities, performance issues, code quality, and adherence to best practices. Provide specific, actionable feedback.',
    'system_prompt' => 'You are a senior software engineer conducting code reviews. Analyze the provided code for security vulnerabilities, performance issues, code quality, and adherence to best practices. Provide specific, actionable feedback.',
    'model' => 'codellama',
    'temperature' => 0.2,
    'max_tokens' => 1500,
    'review_categories' => [
      'security',
      'performance',
      'maintainability',
      'best_practices',
      'documentation'
    ]
  },
  metadata: {
    'supported_languages' => [ 'javascript', 'python', 'ruby', 'java', 'go', 'rust' ],
    'review_depth' => 'comprehensive',
    'typical_execution_time' => '45-90 seconds'
  }
})

# Data Analyzer Agent
data_analyzer_agent = create_or_find_ai_agent(admin_account, admin_user, ollama_provider, {
  name: 'Business Data Analyzer',
  description: 'Analyzes business data and generates insights and recommendations',
  agent_type: 'data_analyst',
  configuration: {
    'instructions' => 'You are a business intelligence analyst. Analyze the provided data and generate actionable insights, trends, and recommendations. Present findings in a clear, business-focused manner.',
    'system_prompt' => 'You are a business intelligence analyst. Analyze the provided data and generate actionable insights, trends, and recommendations. Present findings in a clear, business-focused manner.',
    'model' => 'llama2',
    'temperature' => 0.4,
    'max_tokens' => 1200,
    'analysis_types' => [
      'trend_analysis',
      'performance_metrics',
      'predictive_insights',
      'recommendations'
    ]
  },
  metadata: {
    'data_formats' => [ 'csv', 'json', 'structured_text' ],
    'output_format' => 'executive_summary',
    'typical_execution_time' => '60-90 seconds'
  }
})

# 3. Create Workflow Templates
puts "\n📋 Creating Workflow Templates..."

# Blog Generation Workflow Template
blog_workflow_template = Ai::WorkflowTemplate.find_by(name: 'Complete Blog Generation Pipeline')

unless blog_workflow_template
  puts "📝 Creating Blog Generation Workflow Template..."

  blog_workflow_template = Ai::WorkflowTemplate.create!(
    name: 'Complete Blog Generation Pipeline',
    description: 'End-to-end blog post generation with topic research, content creation, SEO optimization, and publishing workflow',
    category: 'content_creation',
    is_public: true,
    version: '1.0.0',
    tags: [ 'blog', 'content', 'seo', 'automation', 'publishing' ],
    is_featured: true,
    workflow_definition: {
      'workflow' => {
        'name' => 'Blog Generation Workflow',
        'description' => 'Automated blog post generation and optimization',
        'execution_mode' => 'sequential',
        'timeout_seconds' => 300,
        'cost_limit' => 5.0
      },
      'nodes' => [
        {
          'node_id' => 'start',
          'node_type' => 'start',
          'name' => 'Start',
          'description' => 'Workflow starting point',
          'position' => { 'x' => 100, 'y' => 100 },
          'configuration' => {}
        },
        {
          'node_id' => 'topic_research',
          'node_type' => 'ai_agent',
          'name' => 'Topic Research',
          'description' => 'Research and validate blog topic',
          'position' => { 'x' => 300, 'y' => 100 },
          'configuration' => {
            'agent_id' => '{{blog_generator_agent_id}}',
            'prompt_template' => 'Research the topic "{{topic}}" and create an outline for a comprehensive blog post. Include: 1) Main points to cover, 2) Target audience, 3) Key takeaways, 4) Suggested keywords',
            'input_variables' => [ 'topic' ],
            'output_variables' => [ 'research_results', 'outline', 'keywords' ]
          }
        },
        {
          'node_id' => 'content_generation',
          'node_type' => 'ai_agent',
          'name' => 'Content Generation',
          'description' => 'Generate the main blog content',
          'position' => { 'x' => 500, 'y' => 100 },
          'configuration' => {
            'agent_id' => '{{blog_generator_agent_id}}',
            'prompt_template' => 'Based on this research and outline: {{outline}}\n\nWrite a comprehensive blog post about "{{topic}}". Include:\n- Engaging introduction\n- Well-structured main content with headers\n- Practical examples\n- Actionable conclusions\n- Target word count: {{word_count}} words',
            'input_variables' => [ 'topic', 'outline', 'word_count' ],
            'output_variables' => [ 'blog_content', 'word_count_actual' ]
          }
        },
        {
          'node_id' => 'seo_optimization',
          'node_type' => 'ai_agent',
          'name' => 'SEO Optimization',
          'description' => 'Optimize content for search engines',
          'position' => { 'x' => 700, 'y' => 100 },
          'configuration' => {
            'agent_id' => '{{seo_optimizer_agent_id}}',
            'prompt_template' => 'Analyze and optimize this blog post for SEO:\n\nTitle: {{topic}}\nContent: {{blog_content}}\nTarget Keywords: {{keywords}}\n\nProvide:\n1) Optimized title and meta description\n2) Header structure improvements\n3) Keyword optimization suggestions\n4) Internal linking opportunities\n5) Readability improvements',
            'input_variables' => [ 'topic', 'blog_content', 'keywords' ],
            'output_variables' => [ 'seo_title', 'meta_description', 'optimized_content', 'seo_recommendations' ]
          }
        },
        {
          'node_id' => 'quality_check',
          'node_type' => 'condition',
          'name' => 'Quality Check',
          'description' => 'Verify content meets quality standards',
          'position' => { 'x' => 900, 'y' => 100 },
          'configuration' => {
            'conditions' => [
              {
                'variable' => 'word_count_actual',
                'operator' => 'greater_than',
                'value' => 800
              },
              {
                'variable' => 'seo_title',
                'operator' => 'exists'
              }
            ],
            'logic_operator' => 'AND'
          }
        },
        {
          'node_id' => 'publish_webhook',
          'node_type' => 'webhook',
          'name' => 'Publish Content',
          'description' => 'Send content to publishing platform',
          'position' => { 'x' => 1100, 'y' => 50 },
          'configuration' => {
            'url' => '{{publishing_webhook_url}}',
            'method' => 'POST',
            'headers' => {
              'Content-Type' => 'application/json',
              'Authorization' => 'Bearer {{api_key}}'
            },
            'payload_template' => {
              'title' => '{{seo_title}}',
              'content' => '{{optimized_content}}',
              'meta_description' => '{{meta_description}}',
              'tags' => [ '{{topic}}' ],
              'status' => 'draft'
            }
          }
        },
        {
          'node_id' => 'revision_needed',
          'node_type' => 'ai_agent',
          'name' => 'Request Revision',
          'description' => 'Generate revision suggestions',
          'position' => { 'x' => 1100, 'y' => 200 },
          'configuration' => {
            'agent_id' => '{{blog_generator_agent_id}}',
            'prompt_template' => 'The blog post needs revision. Current content: {{blog_content}}\n\nProvide specific suggestions to improve:\n1) Content length (target: {{word_count}} words)\n2) Structure and flow\n3) SEO optimization\n4) Engagement factors',
            'output_variables' => [ 'revision_suggestions' ]
          }
        },
        {
          'node_id' => 'end',
          'node_type' => 'end',
          'name' => 'Complete',
          'description' => 'Workflow completion',
          'position' => { 'x' => 1300, 'y' => 100 },
          'configuration' => {
            'output_mapping' => {
              'published' => '{{publish_webhook.success}}',
              'revision_needed' => '{{revision_suggestions}}',
              'seo_title' => '{{seo_title}}',
              'meta_description' => '{{meta_description}}'
            }
          }
        }
      ],
      'edges' => [
        {
          'edge_id' => 'start_to_research',
          'source_node_id' => 'start',
          'target_node_id' => 'topic_research'
        },
        {
          'edge_id' => 'research_to_content',
          'source_node_id' => 'topic_research',
          'target_node_id' => 'content_generation'
        },
        {
          'edge_id' => 'content_to_seo',
          'source_node_id' => 'content_generation',
          'target_node_id' => 'seo_optimization'
        },
        {
          'edge_id' => 'seo_to_quality',
          'source_node_id' => 'seo_optimization',
          'target_node_id' => 'quality_check'
        },
        {
          'edge_id' => 'quality_to_publish',
          'source_node_id' => 'quality_check',
          'target_node_id' => 'publish_webhook',
          'condition_type' => 'path',
          'condition_value' => 'true'
        },
        {
          'edge_id' => 'quality_to_revision',
          'source_node_id' => 'quality_check',
          'target_node_id' => 'revision_needed',
          'condition_type' => 'path',
          'condition_value' => 'false'
        },
        {
          'edge_id' => 'publish_to_end',
          'source_node_id' => 'publish_webhook',
          'target_node_id' => 'end'
        },
        {
          'edge_id' => 'revision_to_end',
          'source_node_id' => 'revision_needed',
          'target_node_id' => 'end'
        }
      ],
      'variables' => [
        {
          'name' => 'topic',
          'variable_type' => 'string',
          'is_required' => true,
          'description' => 'The blog topic to write about'
        },
        {
          'name' => 'word_count',
          'variable_type' => 'number',
          'default_value' => 1500,
          'description' => 'Target word count for the blog post'
        },
        {
          'name' => 'publishing_webhook_url',
          'variable_type' => 'string',
          'description' => 'URL to send completed content for publishing'
        },
        {
          'name' => 'api_key',
          'variable_type' => 'string',
          'description' => 'API key for publishing platform'
        }
      ]
    },
    metadata: {
      'use_cases' => [
        'Blog content automation',
        'SEO-optimized article generation',
        'Content marketing workflows',
        'Editorial process automation'
      ],
      'benefits' => [
        'Consistent content quality',
        'SEO optimization built-in',
        'Reduced manual work',
        'Scalable content production'
      ],
      'requirements' => [
        'AI agent for content generation',
        'SEO optimization agent',
        'Publishing platform webhook'
      ]
    }
  )
end

# Code Review Workflow Template
code_review_template = Ai::WorkflowTemplate.find_by(name: 'Automated Code Review Pipeline')

unless code_review_template
  puts "🔍 Creating Code Review Workflow Template..."

  code_review_template = Ai::WorkflowTemplate.create!(
    name: 'Automated Code Review Pipeline',
    description: 'Comprehensive code review workflow with security analysis, performance optimization, and documentation checks',
    category: 'development',
    is_public: true,
    version: '1.0.0',
    tags: [ 'code_review', 'security', 'performance', 'quality_assurance' ],
    is_featured: true,
    workflow_definition: {
      'workflow' => {
        'name' => 'Code Review Workflow',
        'description' => 'Automated code quality and security analysis',
        'execution_mode' => 'parallel',
        'timeout_seconds' => 180,
        'cost_limit' => 3.0
      },
      'nodes' => [
        {
          'node_id' => 'start',
          'node_type' => 'start',
          'name' => 'Start Review',
          'description' => 'Begin code review process',
          'position' => { 'x' => 50, 'y' => 300 },
          'configuration' => {}
        },
        {
          'node_id' => 'code_analysis',
          'node_type' => 'ai_agent',
          'name' => 'Code Quality Analysis',
          'description' => 'Analyze code quality and best practices',
          'position' => { 'x' => 200, 'y' => 100 },
          'configuration' => {
            'agent_id' => '{{code_reviewer_agent_id}}',
            'prompt_template' => 'Review this {{language}} code for quality, maintainability, and best practices:\n\n```{{language}}\n{{code}}\n```\n\nFocus on:\n1) Code structure and organization\n2) Naming conventions\n3) Error handling\n4) Code reusability\n5) Documentation quality',
            'output_variables' => [ 'quality_score', 'quality_issues', 'improvement_suggestions' ]
          }
        },
        {
          'node_id' => 'security_analysis',
          'node_type' => 'ai_agent',
          'name' => 'Security Analysis',
          'description' => 'Check for security vulnerabilities',
          'position' => { 'x' => 200, 'y' => 300 },
          'configuration' => {
            'agent_id' => '{{code_reviewer_agent_id}}',
            'prompt_template' => 'Perform a security analysis of this {{language}} code:\n\n```{{language}}\n{{code}}\n```\n\nLook for:\n1) Input validation issues\n2) SQL injection vulnerabilities\n3) XSS vulnerabilities\n4) Authentication/authorization issues\n5) Data exposure risks\n6) Dependency vulnerabilities',
            'output_variables' => [ 'security_score', 'vulnerabilities', 'security_recommendations' ]
          }
        },
        {
          'node_id' => 'performance_analysis',
          'node_type' => 'ai_agent',
          'name' => 'Performance Analysis',
          'description' => 'Identify performance optimization opportunities',
          'position' => { 'x' => 200, 'y' => 500 },
          'configuration' => {
            'agent_id' => '{{code_reviewer_agent_id}}',
            'prompt_template' => 'Analyze this {{language}} code for performance optimization:\n\n```{{language}}\n{{code}}\n```\n\nEvaluate:\n1) Algorithm efficiency\n2) Memory usage\n3) Database query optimization\n4) Caching opportunities\n5) Scalability concerns',
            'output_variables' => [ 'performance_score', 'bottlenecks', 'optimization_suggestions' ]
          }
        },
        {
          'node_id' => 'consolidate_results',
          'node_type' => 'ai_agent',
          'name' => 'Consolidate Review',
          'description' => 'Generate comprehensive review report',
          'position' => { 'x' => 500, 'y' => 300 },
          'configuration' => {
            'agent_id' => '{{code_reviewer_agent_id}}',
            'prompt_template' => 'Create a comprehensive code review report based on these analyses:\n\nQuality Analysis: {{quality_issues}}\nSecurity Analysis: {{vulnerabilities}}\nPerformance Analysis: {{bottlenecks}}\n\nGenerate:\n1) Executive summary\n2) Priority issues (Critical/High/Medium/Low)\n3) Specific recommendations\n4) Overall code rating\n5) Next steps',
            'output_variables' => [ 'review_report', 'overall_rating', 'critical_issues' ]
          }
        },
        {
          'node_id' => 'approval_check',
          'node_type' => 'condition',
          'name' => 'Approval Check',
          'description' => 'Determine if code meets standards',
          'position' => { 'x' => 700, 'y' => 300 },
          'configuration' => {
            'conditions' => [
              {
                'variable' => 'overall_rating',
                'operator' => 'greater_than_or_equal',
                'value' => 7
              },
              {
                'variable' => 'critical_issues',
                'operator' => 'length_equals',
                'value' => 0
              }
            ],
            'logic_operator' => 'AND'
          }
        },
        {
          'node_id' => 'approve_webhook',
          'node_type' => 'webhook',
          'name' => 'Approve Code',
          'description' => 'Send approval notification',
          'position' => { 'x' => 900, 'y' => 200 },
          'configuration' => {
            'url' => '{{approval_webhook_url}}',
            'method' => 'POST',
            'payload_template' => {
              'status' => 'approved',
              'rating' => '{{overall_rating}}',
              'report' => '{{review_report}}',
              'reviewer' => 'AI Code Review System'
            }
          }
        },
        {
          'node_id' => 'request_changes_webhook',
          'node_type' => 'webhook',
          'name' => 'Request Changes',
          'description' => 'Send change request notification',
          'position' => { 'x' => 900, 'y' => 400 },
          'configuration' => {
            'url' => '{{approval_webhook_url}}',
            'method' => 'POST',
            'payload_template' => {
              'status' => 'changes_requested',
              'rating' => '{{overall_rating}}',
              'critical_issues' => '{{critical_issues}}',
              'report' => '{{review_report}}',
              'reviewer' => 'AI Code Review System'
            }
          }
        },
        {
          'node_id' => 'end',
          'node_type' => 'end',
          'name' => 'Review Complete',
          'description' => 'Code review workflow complete',
          'position' => { 'x' => 1100, 'y' => 300 },
          'configuration' => {
            'output_mapping' => {
              'status' => '{{approval_check.result}}',
              'overall_rating' => '{{overall_rating}}',
              'review_report' => '{{review_report}}'
            }
          }
        }
      ],
      'edges' => [
        {
          'edge_id' => 'start_to_quality',
          'source_node_id' => 'start',
          'target_node_id' => 'code_analysis'
        },
        {
          'edge_id' => 'start_to_security',
          'source_node_id' => 'start',
          'target_node_id' => 'security_analysis'
        },
        {
          'edge_id' => 'start_to_performance',
          'source_node_id' => 'start',
          'target_node_id' => 'performance_analysis'
        },
        {
          'edge_id' => 'quality_to_consolidate',
          'source_node_id' => 'code_analysis',
          'target_node_id' => 'consolidate_results'
        },
        {
          'edge_id' => 'security_to_consolidate',
          'source_node_id' => 'security_analysis',
          'target_node_id' => 'consolidate_results'
        },
        {
          'edge_id' => 'performance_to_consolidate',
          'source_node_id' => 'performance_analysis',
          'target_node_id' => 'consolidate_results'
        },
        {
          'edge_id' => 'consolidate_to_approval',
          'source_node_id' => 'consolidate_results',
          'target_node_id' => 'approval_check'
        },
        {
          'edge_id' => 'approval_to_approve',
          'source_node_id' => 'approval_check',
          'target_node_id' => 'approve_webhook',
          'condition_type' => 'path',
          'condition_value' => 'true'
        },
        {
          'edge_id' => 'approval_to_changes',
          'source_node_id' => 'approval_check',
          'target_node_id' => 'request_changes_webhook',
          'condition_type' => 'path',
          'condition_value' => 'false'
        },
        {
          'edge_id' => 'approve_to_end',
          'source_node_id' => 'approve_webhook',
          'target_node_id' => 'end'
        },
        {
          'edge_id' => 'changes_to_end',
          'source_node_id' => 'request_changes_webhook',
          'target_node_id' => 'end'
        }
      ]
    }
  )
end

# 4. Create Sample Workflows
puts "\n🔄 Creating Sample Workflows..."

# Blog Generation Workflow Instance
blog_workflow = admin_account.ai_workflows.find_by(name: 'My Blog Generation Workflow')

unless blog_workflow
  puts "📝 Creating Blog Generation Workflow instance..."

  blog_workflow = admin_account.ai_workflows.create!(
    name: 'My Blog Generation Workflow',
    description: 'Automated blog post generation with Ollama integration',
    status: 'active',
    visibility: 'private',
    version: '1.0.0',
    configuration: {
      'retry_failed_nodes' => true,
      'max_retries' => 2,
      'parallel_execution_limit' => 3
    },
    metadata: {
      'created_from_template' => blog_workflow_template.id,
      'last_optimization' => Time.current.iso8601,
      'performance_stats' => {
        'average_execution_time' => 0,
        'success_rate' => 100.0,
        'total_runs' => 0
      }
    },
    creator: admin_user
  )

  # Create workflow nodes
  start_node = blog_workflow.workflow_nodes.create!(
    node_id: 'start_node',
    node_type: 'start',
    name: 'Start Blog Generation',
    description: 'Initialize blog generation process',
    position: { 'x' => 100, 'y' => 150 },
    configuration: {
      'start_parameters' => {
        'auto_start' => true,
        'timeout_minutes' => 30
      }
    },
    metadata: { 'color' => '#10B981' }
  )

  research_node = blog_workflow.workflow_nodes.create!(
    node_id: 'topic_research',
    node_type: 'ai_agent',
    name: 'Topic Research & Outline',
    description: 'Research topic and create blog outline',
    position: { 'x' => 350, 'y' => 150 },
    configuration: {
      'agent_id' => blog_generator_agent.id,
      'prompt_template' => 'Research the topic "{{topic}}" for a {{target_audience}} audience. Create a comprehensive outline including:\n\n1. Hook/introduction angle\n2. 3-5 main sections with subpoints\n3. Key statistics or data to include\n4. Target keywords for SEO\n5. Call-to-action suggestions\n\nTarget word count: {{word_count}} words',
      'input_variables' => [ 'topic', 'target_audience', 'word_count' ],
      'output_variables' => [ 'outline', 'keywords', 'research_notes' ],
      'temperature' => 0.7,
      'max_tokens' => 1000
    },
    metadata: { 'color' => '#3B82F6', 'estimated_duration' => '45s' }
  )

  content_node = blog_workflow.workflow_nodes.create!(
    node_id: 'content_generation',
    node_type: 'ai_agent',
    name: 'Generate Blog Content',
    description: 'Create the full blog post content',
    position: { 'x' => 600, 'y' => 150 },
    configuration: {
      'agent_id' => blog_generator_agent.id,
      'prompt_template' => 'Write a comprehensive blog post based on this outline:\n\n{{outline}}\n\nRequirements:\n- Topic: {{topic}}\n- Target audience: {{target_audience}}\n- Word count: approximately {{word_count}} words\n- Include the keywords: {{keywords}}\n- Use markdown formatting\n- Write in an engaging, conversational tone\n- Include practical examples where relevant\n- End with a strong conclusion and call-to-action',
      'input_variables' => [ 'topic', 'target_audience', 'word_count', 'outline', 'keywords' ],
      'output_variables' => [ 'blog_content', 'actual_word_count' ],
      'temperature' => 0.8,
      'max_tokens' => 2500
    },
    metadata: { 'color' => '#8B5CF6', 'estimated_duration' => '90s' }
  )

  seo_node = blog_workflow.workflow_nodes.create!(
    node_id: 'seo_optimization',
    node_type: 'ai_agent',
    name: 'SEO Optimization',
    description: 'Optimize content for search engines',
    position: { 'x' => 850, 'y' => 150 },
    configuration: {
      'agent_id' => seo_optimizer_agent.id,
      'prompt_template' => 'Optimize this blog post for SEO:\n\nTopic: {{topic}}\nContent: {{blog_content}}\nTarget Keywords: {{keywords}}\n\nProvide:\n1. SEO-optimized title (50-60 characters)\n2. Meta description (150-160 characters)\n3. Header structure analysis\n4. Keyword density recommendations\n5. Any content improvements for better SEO',
      'input_variables' => [ 'topic', 'blog_content', 'keywords' ],
      'output_variables' => [ 'seo_title', 'meta_description', 'seo_analysis', 'optimized_content' ],
      'temperature' => 0.3,
      'max_tokens' => 800
    },
    metadata: { 'color' => '#EF4444', 'estimated_duration' => '30s' }
  )

  end_node = blog_workflow.workflow_nodes.create!(
    node_id: 'end_node',
    node_type: 'end',
    name: 'Blog Complete',
    description: 'Blog generation workflow complete',
    position: { 'x' => 1100, 'y' => 150 },
    configuration: {
      'output_mapping' => {
        'seo_title' => '{{seo_title}}',
        'meta_description' => '{{meta_description}}',
        'optimized_content' => '{{optimized_content}}'
      }
    },
    metadata: { 'color' => '#10B981' }
  )

  # Create workflow edges
  blog_workflow.edges.create!(
    edge_id: 'start_to_research',
    source_node_id: 'start_node',
    target_node_id: 'topic_research',
    metadata: { 'transition_type' => 'automatic' }
  )

  blog_workflow.edges.create!(
    edge_id: 'research_to_content',
    source_node_id: 'topic_research',
    target_node_id: 'content_generation',
    metadata: { 'transition_type' => 'automatic' }
  )

  blog_workflow.edges.create!(
    edge_id: 'content_to_seo',
    source_node_id: 'content_generation',
    target_node_id: 'seo_optimization',
    metadata: { 'transition_type' => 'automatic' }
  )

  blog_workflow.edges.create!(
    edge_id: 'seo_to_end',
    source_node_id: 'seo_optimization',
    target_node_id: 'end_node',
    metadata: { 'transition_type' => 'automatic' }
  )

  # Create workflow variables
  blog_workflow.variables.create!([
    {
      name: 'topic',
      variable_type: 'string',
      is_required: true,
      description: 'The main topic for the blog post'
    },
    {
      name: 'word_count',
      variable_type: 'number',
      default_value: 1500,
      is_required: false,
      description: 'Target word count for the blog post'
    },
    {
      name: 'target_audience',
      variable_type: 'string',
      default_value: 'general',
      is_required: false,
      description: 'Target audience for the content'
    }
  ])
end

# Data Analysis Workflow
data_analysis_workflow = admin_account.ai_workflows.find_by(name: 'Business Data Analysis Pipeline')

unless data_analysis_workflow
  puts "📊 Creating Data Analysis Workflow..."

  data_analysis_workflow = admin_account.ai_workflows.create!(
    name: 'Business Data Analysis Pipeline',
    description: 'Automated analysis of business data with insights and recommendations',
    status: 'active',
    visibility: 'private',
    version: '1.0.0',
    configuration: {
      'retry_failed_nodes' => true,
      'max_retries' => 1,
      'data_retention_days' => 30
    },
    creator: admin_user
  )

  # Create start node
  data_analysis_workflow.workflow_nodes.create!(
    node_id: 'start_node',
    node_type: 'start',
    name: 'Start Analysis',
    description: 'Begin data analysis process',
    position: { 'x' => 50, 'y' => 150 },
    configuration: {},
    metadata: { 'color' => '#10B981' }
  )

  # Create analysis nodes
  data_analysis_workflow.workflow_nodes.create!(
    node_id: 'data_validation',
    node_type: 'ai_agent',
    name: 'Data Validation',
    description: 'Validate and prepare data for analysis',
    position: { 'x' => 200, 'y' => 150 },
    configuration: {
      'agent_id' => data_analyzer_agent.id,
      'prompt_template' => 'Analyze this {{analysis_type}} data for {{time_period}}:\n\n{{data_source}}\n\nValidate the data and provide:\n1. Data quality assessment\n2. Missing data identification\n3. Data structure summary\n4. Recommendations for data cleaning',
      'output_variables' => [ 'data_quality', 'data_summary', 'validation_results' ]
    }
  )

  data_analysis_workflow.workflow_nodes.create!(
    node_id: 'trend_analysis',
    node_type: 'ai_agent',
    name: 'Trend Analysis',
    description: 'Identify trends and patterns in the data',
    position: { 'x' => 450, 'y' => 150 },
    configuration: {
      'agent_id' => data_analyzer_agent.id,
      'prompt_template' => 'Perform trend analysis on this {{analysis_type}} data:\n\n{{data_source}}\n\nIdentify:\n1. Key trends over {{time_period}}\n2. Growth patterns\n3. Seasonal variations\n4. Anomalies or outliers\n5. Performance indicators',
      'output_variables' => [ 'trends', 'growth_patterns', 'anomalies' ]
    }
  )

  data_analysis_workflow.workflow_nodes.create!(
    node_id: 'insights_generation',
    node_type: 'ai_agent',
    name: 'Generate Business Insights',
    description: 'Create actionable business insights',
    position: { 'x' => 700, 'y' => 150 },
    configuration: {
      'agent_id' => data_analyzer_agent.id,
      'prompt_template' => 'Based on this {{analysis_type}} analysis:\n\nTrends: {{trends}}\nPatterns: {{growth_patterns}}\nAnomalies: {{anomalies}}\n\nGenerate:\n1. Key business insights\n2. Actionable recommendations\n3. Risk factors to monitor\n4. Opportunities for improvement\n5. Executive summary',
      'output_variables' => [ 'insights', 'recommendations', 'executive_summary' ]
    }
  )

  # Create end node
  data_analysis_workflow.workflow_nodes.create!(
    node_id: 'end_node',
    node_type: 'end',
    name: 'Analysis Complete',
    description: 'Data analysis workflow complete',
    position: { 'x' => 950, 'y' => 150 },
    configuration: {
      'output_mapping' => {
        'insights' => '{{insights}}',
        'recommendations' => '{{recommendations}}',
        'executive_summary' => '{{executive_summary}}'
      }
    },
    metadata: { 'color' => '#10B981' }
  )

  # Create edges
  data_analysis_workflow.edges.create!(
    edge_id: 'start_to_validation',
    source_node_id: 'start_node',
    target_node_id: 'data_validation'
  )

  data_analysis_workflow.edges.create!(
    edge_id: 'validation_to_trends',
    source_node_id: 'data_validation',
    target_node_id: 'trend_analysis'
  )

  data_analysis_workflow.edges.create!(
    edge_id: 'trends_to_insights',
    source_node_id: 'trend_analysis',
    target_node_id: 'insights_generation'
  )

  data_analysis_workflow.edges.create!(
    edge_id: 'insights_to_end',
    source_node_id: 'insights_generation',
    target_node_id: 'end_node'
  )
end

# 5. Create Workflow Schedules
puts "\n⏰ Creating Workflow Schedules..."

# Daily blog generation schedule
unless blog_workflow.workflow_schedules.exists?(name: 'Daily Tech Blog Generation')
  puts "📅 Creating daily blog schedule..."

  blog_workflow.workflow_schedules.create!(
    name: 'Daily Tech Blog Generation',
    description: 'Generate a daily tech blog post automatically',
    cron_expression: '0 9 * * 1-5', # 9 AM weekdays
    timezone: 'UTC',
    is_active: false, # Start inactive for demo
    input_variables: {
      'topic' => 'Latest trends in AI and machine learning',
      'word_count' => 1200,
      'target_audience' => 'technical'
    },
    configuration: {
      'max_consecutive_errors' => 3,
      'skip_if_running' => true,
      'notifications' => {
        'on_success' => true,
        'on_failure' => true,
        'on_disable' => true
      }
    },
    metadata: {
      'purpose' => 'automated_content_creation',
      'content_type' => 'technology_blog'
    },
    created_by: admin_user
  )
end

# Weekly data analysis schedule
unless data_analysis_workflow.workflow_schedules.exists?(name: 'Weekly Business Analysis')
  puts "📈 Creating weekly analysis schedule..."

  data_analysis_workflow.workflow_schedules.create!(
    name: 'Weekly Business Analysis',
    description: 'Analyze weekly business metrics and generate reports',
    cron_expression: '0 8 * * 1', # 8 AM Mondays
    timezone: 'UTC',
    is_active: false, # Start inactive for demo
    input_variables: {
      'analysis_type' => 'sales',
      'time_period' => 'Last 7 days'
    },
    configuration: {
      'max_consecutive_errors' => 2,
      'skip_if_running' => true
    },
    created_by: admin_user
  )
end

# 6. Create Workflow Triggers
puts "\n🎯 Creating Workflow Triggers..."

# Blog generation webhook trigger
unless blog_workflow.workflow_triggers.exists?(name: 'Blog Request Webhook')
  puts "🔗 Creating blog webhook trigger..."

  blog_webhook_trigger = blog_workflow.workflow_triggers.create!(
    trigger_type: 'webhook',
    name: 'Blog Request Webhook',
    is_active: true,
    webhook_url: "http://localhost:3000/api/v1/ai/workflows/#{blog_workflow.id}/triggers/webhook/blog_generation_#{SecureRandom.hex(8)}",
    webhook_secret: 'blog_generation_secret_key_2024',
    configuration: {
      'method' => 'POST',
      'webhook_path' => '/blog-generation',
      'webhook_secret' => 'blog_generation_secret_key_2024',
      'validate_signature' => true,
      'variable_mapping' => {
        'topic' => 'blog_topic',
        'word_count' => 'target_words',
        'target_audience' => 'audience'
      },
      'required_headers' => [ 'X-Content-Type' ],
      'allowed_methods' => [ 'POST' ]
    },
    metadata: {
      'integration_guide' => 'Send POST request with blog_topic, target_words, and audience parameters',
      'example_payload' => {
        'blog_topic' => 'Introduction to Machine Learning',
        'target_words' => 1500,
        'audience' => 'technical'
      }
    }
  )
end

# API-based data analysis trigger
unless data_analysis_workflow.workflow_triggers.exists?(name: 'Data Analysis API Trigger')
  puts "📡 Creating API trigger for data analysis..."

  data_analysis_workflow.workflow_triggers.create!(
    trigger_type: 'api_call',
    name: 'Data Analysis API Trigger',
    is_active: true,
    configuration: {
      'authentication_required' => true,
      'rate_limit' => 10, # per hour
      'variable_mapping' => {
        'data_source' => 'data',
        'analysis_type' => 'type',
        'time_period' => 'period'
      }
    }
  )
end

# 7. Create Workflow Variables
puts "\n🔧 Creating Workflow Variables..."

# Blog workflow variables
unless blog_workflow.workflow_variables.exists?(name: 'default_word_count')
  puts "📝 Creating blog workflow variables..."

  blog_workflow.workflow_variables.create!([
    {
      name: 'default_word_count',
      variable_type: 'number',
      scope: 'workflow',
      default_value: 1000,
      is_required: false,
      is_input: true,
      is_output: false,
      description: 'Default number of words for blog posts',
      validation_rules: {
        'min_value' => 100,
        'max_value' => 5000
      }
    },
    {
      name: 'author_name',
      variable_type: 'string',
      scope: 'workflow',
      default_value: 'AI Assistant',
      is_required: false,
      is_input: true,
      is_output: false,
      description: 'Author name for generated blog posts'
    },
    {
      name: 'include_seo_tags',
      variable_type: 'boolean',
      scope: 'workflow',
      default_value: true,
      is_required: false,
      is_input: true,
      is_output: false,
      description: 'Include SEO meta tags in generated content'
    },
    {
      name: 'content_format',
      variable_type: 'string',
      scope: 'workflow',
      default_value: 'markdown',
      is_required: false,
      is_input: true,
      is_output: false,
      description: 'Output format for generated content',
      validation_rules: {
        'allowed_values' => [ 'markdown', 'html', 'plain_text' ]
      }
    }
  ])
end

# Data analysis workflow variables
unless data_analysis_workflow.workflow_variables.exists?(name: 'chart_type')
  puts "📊 Creating data analysis workflow variables..."

  data_analysis_workflow.workflow_variables.create!([
    {
      name: 'chart_type',
      variable_type: 'string',
      scope: 'workflow',
      default_value: 'bar_chart',
      is_required: false,
      is_input: true,
      is_output: false,
      description: 'Type of chart to generate for data visualization',
      validation_rules: {
        'allowed_values' => [ 'bar_chart', 'line_chart', 'pie_chart', 'scatter_plot' ]
      }
    },
    {
      name: 'data_sample_size',
      variable_type: 'number',
      scope: 'workflow',
      default_value: 1000,
      is_required: false,
      is_input: true,
      is_output: false,
      description: 'Maximum number of data points to analyze',
      validation_rules: {
        'min_value' => 10,
        'max_value' => 10000
      }
    },
    {
      name: 'include_statistics',
      variable_type: 'boolean',
      scope: 'workflow',
      default_value: true,
      is_required: false,
      is_input: true,
      is_output: false,
      description: 'Include statistical analysis in the results'
    },
    {
      name: 'output_format',
      variable_type: 'string',
      scope: 'workflow',
      default_value: 'json',
      is_required: false,
      is_input: true,
      is_output: false,
      description: 'Format for analysis results output',
      validation_rules: {
        'allowed_values' => [ 'json', 'csv', 'xlsx', 'pdf' ]
      }
    }
  ])
end

# Customer Support Automation Workflow
customer_support_workflow = admin_account.ai_workflows.find_by(name: 'Customer Support Automation')

unless customer_support_workflow
  puts "🎧 Creating Customer Support Automation Workflow..."

  customer_support_workflow = admin_account.ai_workflows.create!(
    name: 'Customer Support Automation',
    description: 'Automated customer support workflow with sentiment analysis, intent classification, and response generation',
    status: 'active',
    visibility: 'private',
    version: '1.0.0',
    configuration: {
      'retry_failed_nodes' => true,
      'max_retries' => 2,
      'parallel_execution_limit' => 4,
      'human_approval_timeout' => 3600 # 1 hour
    },
    creator: admin_user
  )

  # Create start node
  support_trigger = customer_support_workflow.workflow_nodes.create!(
    node_id: 'support_trigger',
    node_type: 'start',
    name: 'Support Request Start',
    description: 'Incoming customer support request',
    position: { 'x' => 100, 'y' => 250 },
    configuration: {
      'trigger_type' => 'webhook',
      'auto_process' => true,
      'queue_priority' => 'high'
    },
    metadata: { 'color' => '#10B981' },
    is_start_node: true
  )

  # Create sentiment analysis node
  sentiment_node = customer_support_workflow.workflow_nodes.create!(
    node_id: 'sentiment_analysis',
    node_type: 'ai_agent',
    name: 'Sentiment Analysis',
    description: 'Analyze customer sentiment and urgency',
    position: { 'x' => 300, 'y' => 250 },
    configuration: {
      'agent_id' => data_analyzer_agent.id,
      'prompt_template' => 'Analyze the sentiment and urgency of this customer message:\n\n"{{customer_message}}"\n\nProvide:\n1. Sentiment score (-1 to 1)\n2. Urgency level (low/medium/high/critical)\n3. Key emotions detected\n4. Escalation recommendation (yes/no)',
      'input_variables' => [ 'customer_message', 'customer_email' ],
      'output_variables' => [ 'sentiment_score', 'urgency_level', 'emotions', 'escalation_needed' ],
      'temperature' => 0.2,
      'max_tokens' => 300
    },
    metadata: { 'color' => '#F59E0B', 'estimated_duration' => '15s' }
  )

  # Create intent classification node (parallel with sentiment)
  intent_node = customer_support_workflow.workflow_nodes.create!(
    node_id: 'intent_classification',
    node_type: 'ai_agent',
    name: 'Intent Classification',
    description: 'Classify customer request intent and category',
    position: { 'x' => 300, 'y' => 400 },
    configuration: {
      'agent_id' => data_analyzer_agent.id,
      'prompt_template' => 'Classify this customer support request:\n\n"{{customer_message}}"\n\nCategories: billing, technical, product, account, refund, bug_report, feature_request\n\nProvide:\n1. Primary category\n2. Secondary category (if applicable)\n3. Intent confidence (0-1)\n4. Required information to resolve\n5. Suggested department (support/billing/technical/management)',
      'input_variables' => [ 'customer_message' ],
      'output_variables' => [ 'primary_category', 'secondary_category', 'confidence', 'required_info', 'department' ],
      'temperature' => 0.1,
      'max_tokens' => 200
    },
    metadata: { 'color' => '#8B5CF6', 'estimated_duration' => '12s' }
  )

  # Create routing decision node
  routing_node = customer_support_workflow.workflow_nodes.create!(
    node_id: 'request_routing',
    node_type: 'condition',
    name: 'Route Request',
    description: 'Route based on urgency and category',
    position: { 'x' => 550, 'y' => 325 },
    configuration: {
      'conditions' => [
        {
          'name' => 'critical_urgent',
          'logic' => 'OR',
          'rules' => [
            { 'field' => 'urgency_level', 'operator' => 'equals', 'value' => 'critical' },
            { 'field' => 'escalation_needed', 'operator' => 'equals', 'value' => 'yes' }
          ]
        },
        {
          'name' => 'technical_issue',
          'logic' => 'AND',
          'rules' => [
            { 'field' => 'primary_category', 'operator' => 'in', 'value' => [ 'technical', 'bug_report' ] },
            { 'field' => 'urgency_level', 'operator' => 'not_equals', 'value' => 'critical' }
          ]
        },
        {
          'name' => 'standard_support',
          'logic' => 'AND',
          'rules' => [
            { 'field' => 'confidence', 'operator' => 'greater_than', 'value' => 0.8 },
            { 'field' => 'urgency_level', 'operator' => 'in', 'value' => [ 'low', 'medium' ] }
          ]
        }
      ]
    },
    metadata: { 'color' => '#EF4444', 'decision_point' => true }
  )

  # Human approval for critical issues
  human_approval_node = customer_support_workflow.workflow_nodes.create!(
    node_id: 'human_escalation',
    node_type: 'human_approval',
    name: 'Human Escalation',
    description: 'Escalate critical issues to human agent',
    position: { 'x' => 750, 'y' => 150 },
    configuration: {
      'approvers' => [ 'support_manager', 'senior_support_agent' ],
      'approval_type' => 'assignment',
      'assignee_role' => 'support_manager',
      'timeout_minutes' => 60,
      'notification_channels' => [ 'email', 'slack' ],
      'context_data' => [
        'customer_message', 'sentiment_score', 'urgency_level',
        'primary_category', 'customer_email'
      ],
      'approval_options' => [
        { 'value' => 'escalate_to_manager', 'label' => 'Escalate to Manager', 'color' => 'red' },
        { 'value' => 'assign_to_specialist', 'label' => 'Assign to Specialist', 'color' => 'orange' },
        { 'value' => 'continue_automated', 'label' => 'Continue with AI', 'color' => 'green' }
      ]
    },
    metadata: { 'color' => '#F87171', 'requires_human' => true }
  )

  # Auto-response for standard requests
  auto_response_node = customer_support_workflow.workflow_nodes.create!(
    node_id: 'auto_response',
    node_type: 'ai_agent',
    name: 'Generate Response',
    description: 'Generate automated response',
    position: { 'x' => 750, 'y' => 325 },
    configuration: {
      'agent_id' => blog_generator_agent.id,
      'prompt_template' => 'Generate a helpful customer support response for this {{primary_category}} request:\n\nCustomer message: "{{customer_message}}"\nSentiment: {{sentiment_score}}\nUrgency: {{urgency_level}}\n\nGuidelines:\n- Be empathetic and professional\n- Address their specific concern\n- Provide clear next steps\n- Include relevant links if needed\n- Match the tone to their sentiment',
      'input_variables' => [ 'customer_message', 'primary_category', 'sentiment_score', 'urgency_level' ],
      'output_variables' => [ 'response_text', 'suggested_next_steps', 'escalation_flag' ],
      'temperature' => 0.6,
      'max_tokens' => 500
    },
    metadata: { 'color' => '#06B6D4', 'estimated_duration' => '25s' }
  )

  # Technical knowledge base lookup
  kb_lookup_node = customer_support_workflow.workflow_nodes.create!(
    node_id: 'kb_lookup',
    node_type: 'api_call',
    name: 'Knowledge Base Search',
    description: 'Search technical documentation',
    position: { 'x' => 750, 'y' => 500 },
    configuration: {
      'method' => 'POST',
      'url' => '{{knowledge_base_api_url}}',
      'headers' => {
        'Authorization' => 'Bearer {{kb_api_key}}',
        'Content-Type' => 'application/json'
      },
      'request_body' => {
        'query' => '{{customer_message}}',
        'category' => '{{primary_category}}',
        'limit' => 3,
        'min_relevance' => 0.7
      },
      'response_mapping' => {
        'kb_results' => 'data.results',
        'relevance_scores' => 'data.scores'
      },
      'timeout_seconds' => 30
    },
    metadata: { 'color' => '#8B5CF6', 'external_service' => 'knowledge_base' }
  )

  # Response validation and quality check
  validation_node = customer_support_workflow.workflow_nodes.create!(
    node_id: 'response_validation',
    node_type: 'ai_agent',
    name: 'Validate Response',
    description: 'Quality check for generated response',
    position: { 'x' => 950, 'y' => 400 },
    configuration: {
      'agent_id' => data_analyzer_agent.id,
      'prompt_template' => 'Review this customer support response for quality:\n\nOriginal request: "{{customer_message}}"\nCategory: {{primary_category}}\nGenerated response: "{{response_text}}"\n\nEvaluate:\n1. Relevance to the customer issue (1-10)\n2. Tone appropriateness (1-10)\n3. Completeness of response (1-10)\n4. Professional language (1-10)\n5. Overall quality score (1-10)\n6. Approval recommendation (approve/revise/escalate)',
      'input_variables' => [ 'customer_message', 'primary_category', 'response_text' ],
      'output_variables' => [ 'quality_scores', 'overall_quality', 'approval_recommendation', 'improvement_suggestions' ],
      'temperature' => 0.1,
      'max_tokens' => 300
    },
    metadata: { 'color' => '#10B981', 'quality_gate' => true }
  )

  # Final response dispatch
  dispatch_node = customer_support_workflow.workflow_nodes.create!(
    node_id: 'response_dispatch',
    node_type: 'webhook',
    name: 'Send Response',
    description: 'Send response to customer',
    position: { 'x' => 1150, 'y' => 325 },
    configuration: {
      'url' => '{{customer_response_webhook}}',
      'method' => 'POST',
      'headers' => {
        'Authorization' => 'Bearer {{support_api_key}}',
        'Content-Type' => 'application/json'
      },
      'payload_template' => {
        'customer_email' => '{{customer_email}}',
        'response_text' => '{{response_text}}',
        'category' => '{{primary_category}}',
        'priority' => '{{urgency_level}}',
        'quality_score' => '{{overall_quality}}',
        'generated_at' => '{{current_timestamp}}',
        'workflow_id' => '{{workflow_run_id}}'
      }
    },
    metadata: { 'color' => '#059669', 'is_end_node' => true }
  )

  # Create edges for customer support workflow
  customer_support_workflow.edges.create!([
    # Trigger to parallel sentiment/intent analysis
    {
      edge_id: 'trigger_to_sentiment',
      source_node_id: 'support_trigger',
      target_node_id: 'sentiment_analysis'
    },
    {
      edge_id: 'trigger_to_intent',
      source_node_id: 'support_trigger',
      target_node_id: 'intent_classification'
    },
    # Both analyses to routing
    {
      edge_id: 'sentiment_to_routing',
      source_node_id: 'sentiment_analysis',
      target_node_id: 'request_routing'
    },
    {
      edge_id: 'intent_to_routing',
      source_node_id: 'intent_classification',
      target_node_id: 'request_routing'
    },
    # Routing to different paths
    {
      edge_id: 'routing_to_human',
      source_node_id: 'request_routing',
      target_node_id: 'human_escalation',
      condition: {
        'expression' => 'routing_decision == "critical_urgent"'
      }
    },
    {
      edge_id: 'routing_to_kb',
      source_node_id: 'request_routing',
      target_node_id: 'kb_lookup',
      condition: {
        'expression' => 'routing_decision == "technical_issue"'
      }
    },
    {
      edge_id: 'routing_to_auto',
      source_node_id: 'request_routing',
      target_node_id: 'auto_response',
      condition: {
        'expression' => 'routing_decision == "standard_support"'
      }
    },
    # KB lookup to auto response
    {
      edge_id: 'kb_to_auto',
      source_node_id: 'kb_lookup',
      target_node_id: 'auto_response'
    },
    # Auto response to validation
    {
      edge_id: 'auto_to_validation',
      source_node_id: 'auto_response',
      target_node_id: 'response_validation'
    },
    # Human approval to dispatch (if approved)
    {
      edge_id: 'human_to_dispatch',
      source_node_id: 'human_escalation',
      target_node_id: 'response_dispatch'
    },
    # Validation to dispatch
    {
      edge_id: 'validation_to_dispatch',
      source_node_id: 'response_validation',
      target_node_id: 'response_dispatch'
    }
  ])

  # Create variables for customer support workflow
  customer_support_workflow.variables.create!([
    {
      name: 'customer_message',
      variable_type: 'string',
      is_required: true,
      description: 'The customer support request message'
    },
    {
      name: 'customer_email',
      variable_type: 'string',
      is_required: true,
      description: 'Customer email address'
    },
    {
      name: 'knowledge_base_api_url',
      variable_type: 'string',
      default_value: 'https://api.company.com/kb/search',
      description: 'Knowledge base API endpoint'
    },
    {
      name: 'customer_response_webhook',
      variable_type: 'string',
      is_required: true,
      description: 'Webhook URL to send customer response'
    }
  ])
end

# E-commerce Order Processing Workflow
ecommerce_workflow = admin_account.ai_workflows.find_by(name: 'E-commerce Order Processing')

unless ecommerce_workflow
  puts "🛒 Creating E-commerce Order Processing Workflow..."

  ecommerce_workflow = admin_account.ai_workflows.create!(
    name: 'E-commerce Order Processing',
    description: 'Complete order processing pipeline with inventory check, fraud detection, and fulfillment automation',
    status: 'active',
    visibility: 'private',
    version: '1.0.0',
    configuration: {
      'retry_failed_nodes' => true,
      'max_retries' => 3,
      'parallel_execution_limit' => 5,
      'failure_tolerance' => 0.1 # 10% failure tolerance
    },
    creator: admin_user
  )

  # Order received start node
  order_trigger = ecommerce_workflow.workflow_nodes.create!(
    node_id: 'order_received',
    node_type: 'start',
    name: 'Order Received',
    description: 'New order webhook start',
    position: { 'x' => 100, 'y' => 300 },
    configuration: {
      'trigger_type' => 'webhook',
      'auto_process' => true,
      'validation_required' => true
    },
    metadata: { 'color' => '#10B981' },
    is_start_node: true
  )

  # Parallel processing: Inventory check and Fraud detection
  inventory_check = ecommerce_workflow.workflow_nodes.create!(
    node_id: 'inventory_check',
    node_type: 'api_call',
    name: 'Check Inventory',
    description: 'Verify product availability and reserve stock',
    position: { 'x' => 300, 'y' => 200 },
    configuration: {
      'method' => 'POST',
      'url' => '{{inventory_api_url}}/check',
      'headers' => {
        'Authorization' => 'Bearer {{inventory_api_key}}',
        'Content-Type' => 'application/json'
      },
      'request_body' => {
        'order_id' => '{{order_id}}',
        'items' => '{{order_items}}',
        'reserve_stock' => true
      },
      'response_mapping' => {
        'availability_status' => 'data.status',
        'available_items' => 'data.available_items',
        'backordered_items' => 'data.backordered_items',
        'estimated_fulfillment' => 'data.estimated_date'
      },
      'retry_attempts' => 3,
      'timeout_seconds' => 45
    },
    metadata: { 'color' => '#3B82F6', 'external_service' => 'inventory_system' }
  )

  fraud_detection = ecommerce_workflow.workflow_nodes.create!(
    node_id: 'fraud_detection',
    node_type: 'ai_agent',
    name: 'Fraud Detection',
    description: 'Analyze order for potential fraud indicators',
    position: { 'x' => 300, 'y' => 400 },
    configuration: {
      'agent_id' => data_analyzer_agent.id,
      'prompt_template' => 'Analyze this order for fraud risk:\n\nOrder Details:\n- Amount: ${{order_amount}}\n- Customer: {{customer_email}}\n- Shipping: {{shipping_address}}\n- Billing: {{billing_address}}\n- Payment: {{payment_method}}\n- Previous orders: {{customer_order_count}}\n- Account age: {{customer_account_age}}\n\nEvaluate:\n1. Risk score (0-100, where 100 is highest risk)\n2. Risk factors identified\n3. Recommendation (approve/review/decline)\n4. Confidence level (0-1)',
      'input_variables' => [
        'order_amount', 'customer_email', 'shipping_address',
        'billing_address', 'payment_method', 'customer_order_count', 'customer_account_age'
      ],
      'output_variables' => [ 'risk_score', 'risk_factors', 'recommendation', 'confidence_level' ],
      'temperature' => 0.1,
      'max_tokens' => 400
    },
    metadata: { 'color' => '#EF4444', 'security_check' => true }
  )

  # Order validation combining both checks
  order_validation = ecommerce_workflow.workflow_nodes.create!(
    node_id: 'order_validation',
    node_type: 'condition',
    name: 'Validate Order',
    description: 'Validate inventory and fraud results',
    position: { 'x' => 550, 'y' => 300 },
    configuration: {
      'conditions' => [
        {
          'name' => 'fraud_detected',
          'logic' => 'OR',
          'rules' => [
            { 'field' => 'risk_score', 'operator' => 'greater_than', 'value' => 80 },
            { 'field' => 'recommendation', 'operator' => 'equals', 'value' => 'decline' }
          ]
        },
        {
          'name' => 'insufficient_stock',
          'logic' => 'OR',
          'rules' => [
            { 'field' => 'availability_status', 'operator' => 'equals', 'value' => 'out_of_stock' },
            { 'field' => 'backordered_items', 'operator' => 'array_not_empty' }
          ]
        },
        {
          'name' => 'order_approved',
          'logic' => 'AND',
          'rules' => [
            { 'field' => 'risk_score', 'operator' => 'less_than_or_equal', 'value' => 30 },
            { 'field' => 'availability_status', 'operator' => 'equals', 'value' => 'available' },
            { 'field' => 'recommendation', 'operator' => 'equals', 'value' => 'approve' }
          ]
        }
      ]
    },
    metadata: { 'color' => '#F59E0B', 'decision_point' => true }
  )

  # Order decline path
  decline_order = ecommerce_workflow.workflow_nodes.create!(
    node_id: 'decline_order',
    node_type: 'webhook',
    name: 'Decline Order',
    description: 'Cancel order and notify customer',
    position: { 'x' => 750, 'y' => 150 },
    configuration: {
      'url' => '{{order_management_webhook}}/decline',
      'method' => 'POST',
      'payload_template' => {
        'order_id' => '{{order_id}}',
        'reason' => 'Order declined due to {{decline_reason}}',
        'risk_score' => '{{risk_score}}',
        'customer_email' => '{{customer_email}}',
        'notify_customer' => true,
        'refund_required' => true
      }
    },
    metadata: { 'color' => '#DC2626', 'is_end_node' => true }
  )

  # Manual review for medium risk
  manual_review = ecommerce_workflow.workflow_nodes.create!(
    node_id: 'manual_review',
    node_type: 'human_approval',
    name: 'Manual Review',
    description: 'Human review for medium-risk orders',
    position: { 'x' => 750, 'y' => 250 },
    configuration: {
      'approvers' => [ 'fraud_analyst', 'risk_manager' ],
      'approval_type' => 'order_review',
      'assignee_role' => 'fraud_analyst',
      'timeout_minutes' => 240, # 4 hours
      'escalation_timeout' => 480, # 8 hours
      'context_data' => [
        'order_id', 'customer_email', 'order_amount', 'risk_score',
        'risk_factors', 'availability_status'
      ],
      'approval_options' => [
        { 'value' => 'approve_order', 'label' => 'Approve Order', 'color' => 'green' },
        { 'value' => 'decline_order', 'label' => 'Decline Order', 'color' => 'red' },
        { 'value' => 'request_verification', 'label' => 'Request Customer Verification', 'color' => 'yellow' }
      ]
    },
    metadata: { 'color' => '#F59E0B', 'requires_human' => true }
  )

  # Payment processing
  payment_processing = ecommerce_workflow.workflow_nodes.create!(
    node_id: 'payment_processing',
    node_type: 'api_call',
    name: 'Process Payment',
    description: 'Charge customer payment method',
    position: { 'x' => 950, 'y' => 350 },
    configuration: {
      'method' => 'POST',
      'url' => '{{payment_gateway_url}}/charge',
      'headers' => {
        'Authorization' => 'Bearer {{payment_api_key}}',
        'Content-Type' => 'application/json'
      },
      'request_body' => {
        'order_id' => '{{order_id}}',
        'amount' => '{{order_amount}}',
        'currency' => '{{order_currency}}',
        'payment_method' => '{{payment_method_id}}',
        'description' => 'Order #{{order_id}}'
      },
      'response_mapping' => {
        'payment_status' => 'data.status',
        'transaction_id' => 'data.transaction_id',
        'payment_error' => 'data.error_message'
      },
      'retry_attempts' => 2,
      'timeout_seconds' => 60
    },
    metadata: { 'color' => '#059669', 'payment_gateway' => true }
  )

  # Order fulfillment preparation
  fulfillment_prep = ecommerce_workflow.workflow_nodes.create!(
    node_id: 'fulfillment_prep',
    node_type: 'loop',
    name: 'Prepare Fulfillment',
    description: 'Generate pick lists and shipping labels',
    position: { 'x' => 1150, 'y' => 350 },
    configuration: {
      'iteration_source' => 'order_items',
      'loop_type' => 'for_each',
      'item_variable' => 'current_item',
      'max_iterations' => 50,
      'parallel_processing' => true,
      'sub_workflow' => {
        'steps' => [
          {
            'step_type' => 'api_call',
            'name' => 'generate_pick_list',
            'url' => '{{warehouse_api_url}}/pick-list',
            'payload' => {
              'item_sku' => '{{current_item.sku}}',
              'quantity' => '{{current_item.quantity}}',
              'location' => '{{current_item.warehouse_location}}'
            }
          },
          {
            'step_type' => 'api_call',
            'name' => 'reserve_shipping_label',
            'url' => '{{shipping_api_url}}/labels/reserve',
            'payload' => {
              'order_id' => '{{order_id}}',
              'item_weight' => '{{current_item.weight}}',
              'shipping_method' => '{{shipping_method}}'
            }
          }
        ]
      },
      'output_aggregation' => {
        'pick_lists' => 'collect(pick_list_id)',
        'shipping_labels' => 'collect(label_id)',
        'total_processing_time' => 'sum(processing_time)'
      }
    },
    metadata: { 'color' => '#8B5CF6', 'warehouse_integration' => true }
  )

  # Order confirmation
  order_confirmation = ecommerce_workflow.workflow_nodes.create!(
    node_id: 'order_confirmation',
    node_type: 'ai_agent',
    name: 'Generate Confirmation',
    description: 'Create personalized order confirmation',
    position: { 'x' => 1350, 'y' => 350 },
    configuration: {
      'agent_id' => blog_generator_agent.id,
      'prompt_template' => 'Generate a personalized order confirmation email for:\n\nCustomer: {{customer_email}}\nOrder ID: {{order_id}}\nItems: {{order_items}}\nTotal: ${{order_amount}}\nShipping: {{shipping_method}}\nEstimated delivery: {{estimated_delivery}}\n\nInclude:\n1. Warm, professional greeting\n2. Order summary with item details\n3. Payment confirmation\n4. Shipping information\n5. Tracking information (when available)\n6. Customer service contact info\n7. Thank you message',
      'input_variables' => [
        'customer_email', 'order_id', 'order_items', 'order_amount',
        'shipping_method', 'estimated_delivery'
      ],
      'output_variables' => [ 'confirmation_email', 'email_subject', 'personalization_score' ],
      'temperature' => 0.7,
      'max_tokens' => 600
    },
    metadata: { 'color' => '#06B6D4', 'customer_communication' => true }
  )

  # Create edges for e-commerce workflow
  ecommerce_workflow.edges.create!([
    # Trigger to parallel processing
    {
      edge_id: 'trigger_to_inventory',
      source_node_id: 'order_received',
      target_node_id: 'inventory_check'
    },
    {
      edge_id: 'trigger_to_fraud',
      source_node_id: 'order_received',
      target_node_id: 'fraud_detection'
    },
    # Both checks to validation
    {
      edge_id: 'inventory_to_validation',
      source_node_id: 'inventory_check',
      target_node_id: 'order_validation'
    },
    {
      edge_id: 'fraud_to_validation',
      source_node_id: 'fraud_detection',
      target_node_id: 'order_validation'
    },
    # Validation outcomes
    {
      edge_id: 'validation_to_decline',
      source_node_id: 'order_validation',
      target_node_id: 'decline_order',
      condition: {
        'expression' => 'validation_result == "fraud_detected"'
      }
    },
    {
      edge_id: 'validation_to_review',
      source_node_id: 'order_validation',
      target_node_id: 'manual_review',
      condition: {
        'expression' => 'validation_result == "insufficient_stock"'
      }
    },
    {
      edge_id: 'validation_to_payment',
      source_node_id: 'order_validation',
      target_node_id: 'payment_processing',
      condition: {
        'expression' => 'validation_result == "order_approved"'
      }
    },
    # Manual review to payment (if approved)
    {
      edge_id: 'review_to_payment',
      source_node_id: 'manual_review',
      target_node_id: 'payment_processing'
    },
    # Payment to fulfillment
    {
      edge_id: 'payment_to_fulfillment',
      source_node_id: 'payment_processing',
      target_node_id: 'fulfillment_prep'
    },
    # Fulfillment to confirmation
    {
      edge_id: 'fulfillment_to_confirmation',
      source_node_id: 'fulfillment_prep',
      target_node_id: 'order_confirmation'
    }
  ])
end

# Marketing Campaign Optimization Workflow
marketing_workflow = admin_account.ai_workflows.find_by(name: 'Marketing Campaign Optimizer')

unless marketing_workflow
  puts "📈 Creating Marketing Campaign Optimizer Workflow..."

  marketing_workflow = admin_account.ai_workflows.create!(
    name: 'Marketing Campaign Optimizer',
    description: 'Automated marketing campaign analysis and optimization with A/B testing and performance tracking',
    status: 'active',
    visibility: 'private',
    version: '1.0.0',
    configuration: {
      'retry_failed_nodes' => true,
      'max_retries' => 2,
      'parallel_execution_limit' => 6
    },
    creator: admin_user
  )

  # Campaign data ingestion
  data_ingestion = marketing_workflow.workflow_nodes.create!(
    node_id: 'data_ingestion',
    node_type: 'api_call',
    name: 'Collect Campaign Data',
    description: 'Gather campaign performance data from multiple sources',
    position: { 'x' => 150, 'y' => 300 },
    configuration: {
      'method' => 'POST',
      'url' => '{{analytics_api_url}}/campaigns/data',
      'request_body' => {
        'campaign_ids' => '{{campaign_ids}}',
        'date_range' => '{{analysis_period}}',
        'metrics' => [ 'impressions', 'clicks', 'conversions', 'cost', 'revenue' ],
        'dimensions' => [ 'source', 'medium', 'audience', 'creative' ]
      },
      'response_mapping' => {
        'campaign_data' => 'data.campaigns',
        'benchmark_data' => 'data.benchmarks',
        'historical_trends' => 'data.trends'
      }
    }
  )

  # Performance analysis
  performance_analysis = marketing_workflow.workflow_nodes.create!(
    node_id: 'performance_analysis',
    node_type: 'ai_agent',
    name: 'Analyze Performance',
    description: 'Analyze campaign performance and identify trends',
    position: { 'x' => 400, 'y' => 200 },
    configuration: {
      'agent_id' => data_analyzer_agent.id,
      'prompt_template' => 'Analyze this marketing campaign performance data:\n\n{{campaign_data}}\n\nBenchmarks: {{benchmark_data}}\nHistorical trends: {{historical_trends}}\n\nProvide analysis for:\n1. Top performing campaigns (CTR, conversion rate, ROAS)\n2. Underperforming campaigns\n3. Key performance trends\n4. Seasonal patterns\n5. Audience segment performance\n6. Creative performance comparison',
      'output_variables' => [ 'top_performers', 'underperformers', 'key_trends', 'performance_summary' ]
    }
  )

  # A/B test analysis
  ab_test_analysis = marketing_workflow.workflow_nodes.create!(
    node_id: 'ab_test_analysis',
    node_type: 'ai_agent',
    name: 'A/B Test Analysis',
    description: 'Analyze ongoing A/B tests and determine winners',
    position: { 'x' => 400, 'y' => 400 },
    configuration: {
      'agent_id' => data_analyzer_agent.id,
      'prompt_template' => 'Analyze these A/B test results:\n\n{{campaign_data}}\n\nFor each test:\n1. Statistical significance (confidence level)\n2. Winning variant identification\n3. Performance lift calculation\n4. Sample size adequacy\n5. Recommendation (continue/stop/expand winner)',
      'output_variables' => [ 'test_results', 'winning_variants', 'statistical_confidence', 'test_recommendations' ]
    }
  )

  # Optimization recommendations
  optimization_engine = marketing_workflow.workflow_nodes.create!(
    node_id: 'optimization_recommendations',
    node_type: 'ai_agent',
    name: 'Generate Optimizations',
    description: 'Create actionable optimization recommendations',
    position: { 'x' => 650, 'y' => 300 },
    configuration: {
      'agent_id' => data_analyzer_agent.id,
      'prompt_template' => 'Based on this analysis:\n\nPerformance: {{performance_summary}}\nA/B Tests: {{test_results}}\nTrends: {{key_trends}}\n\nGenerate optimization recommendations:\n1. Budget reallocation suggestions\n2. Audience targeting adjustments\n3. Creative optimization ideas\n4. Bidding strategy changes\n5. New test proposals\n6. Campaign scaling opportunities\n7. Priority ranking (High/Medium/Low)',
      'output_variables' => [ 'budget_recommendations', 'targeting_adjustments', 'creative_suggestions', 'scaling_opportunities', 'priority_actions' ]
    }
  )

  # Auto-implementation for low-risk changes
  auto_implementation = marketing_workflow.workflow_nodes.create!(
    node_id: 'auto_implementation',
    node_type: 'condition',
    name: 'Auto-Implementation Check',
    description: 'Determine which changes can be auto-implemented',
    position: { 'x' => 900, 'y' => 200 },
    configuration: {
      'conditions' => [
        {
          'name' => 'safe_auto_implement',
          'logic' => 'AND',
          'rules' => [
            { 'field' => 'statistical_confidence', 'operator' => 'greater_than', 'value' => 95 },
            { 'field' => 'budget_impact', 'operator' => 'less_than', 'value' => 1000 },
            { 'field' => 'risk_level', 'operator' => 'equals', 'value' => 'low' }
          ]
        }
      ]
    }
  )

  # Campaign updates
  campaign_updates = marketing_workflow.workflow_nodes.create!(
    node_id: 'campaign_updates',
    node_type: 'loop',
    name: 'Apply Campaign Updates',
    description: 'Implement approved optimizations',
    position: { 'x' => 1150, 'y' => 200 },
    configuration: {
      'iteration_source' => 'priority_actions',
      'loop_type' => 'for_each',
      'item_variable' => 'current_action',
      'sub_workflow' => {
        'steps' => [
          {
            'step_type' => 'api_call',
            'name' => 'update_campaign',
            'url' => '{{campaign_management_api}}/campaigns/{{current_action.campaign_id}}',
            'method' => 'PATCH',
            'payload' => '{{current_action.changes}}'
          }
        ]
      }
    }
  )

  # Manual approval for high-risk changes
  manual_approval_marketing = marketing_workflow.workflow_nodes.create!(
    node_id: 'manual_approval_marketing',
    node_type: 'human_approval',
    name: 'Marketing Manager Approval',
    description: 'Get approval for high-impact changes',
    position: { 'x' => 900, 'y' => 400 },
    configuration: {
      'approvers' => [ 'marketing_manager', 'marketing_director' ],
      'assignee_role' => 'marketing_manager',
      'timeout_minutes' => 120,
      'context_data' => [
        'budget_recommendations', 'targeting_adjustments',
        'performance_summary', 'priority_actions'
      ]
    }
  )

  # Performance report generation
  report_generation = marketing_workflow.workflow_nodes.create!(
    node_id: 'performance_report',
    node_type: 'ai_agent',
    name: 'Generate Report',
    description: 'Create comprehensive performance report',
    position: { 'x' => 1350, 'y' => 300 },
    configuration: {
      'agent_id' => blog_generator_agent.id,
      'prompt_template' => 'Create a marketing performance report:\n\nAnalysis Period: {{analysis_period}}\nCampaigns: {{campaign_ids}}\nKey Results: {{performance_summary}}\nOptimizations: {{priority_actions}}\nA/B Tests: {{test_results}}\n\nGenerate executive summary with:\n1. Key performance highlights\n2. Top insights and findings\n3. Optimization recommendations implemented\n4. Expected impact projections\n5. Next steps and future tests',
      'output_variables' => [ 'executive_report', 'key_metrics_summary', 'action_items' ]
    }
  )

  # Create edges for marketing workflow
  marketing_workflow.edges.create!([
    {
      edge_id: 'ingestion_to_performance',
      source_node_id: 'data_ingestion',
      target_node_id: 'performance_analysis'
    },
    {
      edge_id: 'ingestion_to_ab',
      source_node_id: 'data_ingestion',
      target_node_id: 'ab_test_analysis'
    },
    {
      edge_id: 'performance_to_optimization',
      source_node_id: 'performance_analysis',
      target_node_id: 'optimization_recommendations'
    },
    {
      edge_id: 'ab_to_optimization',
      source_node_id: 'ab_test_analysis',
      target_node_id: 'optimization_recommendations'
    },
    {
      edge_id: 'optimization_to_auto',
      source_node_id: 'optimization_recommendations',
      target_node_id: 'auto_implementation'
    },
    {
      edge_id: 'auto_to_updates',
      source_node_id: 'auto_implementation',
      target_node_id: 'campaign_updates',
      condition: {
        'expression' => 'implementation_decision == "safe_auto_implement"'
      }
    },
    {
      edge_id: 'auto_to_manual',
      source_node_id: 'auto_implementation',
      target_node_id: 'manual_approval_marketing',
      condition: {
        'expression' => 'implementation_decision == "default"'
      }
    },
    {
      edge_id: 'manual_to_updates',
      source_node_id: 'manual_approval_marketing',
      target_node_id: 'campaign_updates'
    },
    {
      edge_id: 'updates_to_report',
      source_node_id: 'campaign_updates',
      target_node_id: 'performance_report'
    }
  ])
end

# 8. Create Sample Workflow Runs
puts "\n🚀 Creating Sample Workflow Runs..."

# Create a completed blog generation run
unless blog_workflow.workflow_runs.exists?(status: 'completed')
  puts "📝 Creating sample blog generation run..."

  blog_run = blog_workflow.workflow_runs.create!(
    account: admin_account,
    run_id: "run_#{SecureRandom.hex(8)}",
    status: 'completed',
    trigger_type: 'manual',
    triggered_by_user: admin_user,
    input_variables: {
      'topic' => 'Introduction to AI Workflows',
      'word_count' => 1200,
      'target_audience' => 'developers'
    },
    output_variables: {
      'generated_content' => '# Introduction to AI Workflows\n\nAI workflows are revolutionizing how we approach automation...',
      'word_count' => 1187,
      'seo_keywords' => [ 'AI workflows', 'automation', 'artificial intelligence' ],
      'reading_time' => '5 minutes'
    },
    duration_ms: 45000,
    total_cost: 0.12,
    total_nodes: 3,
    completed_nodes: 3,
    failed_nodes: 0,
    started_at: 2.hours.ago,
    completed_at: 2.hours.ago + 45.seconds,
    metadata: {
      'model_used' => 'llama2',
      'provider' => 'ollama_local',
      'tokens_used' => 2400,
      'generation_quality' => 'high'
    }
  )

  # Create node executions for the blog run
  blog_workflow.workflow_nodes.each_with_index do |node, index|
    blog_run.ai_workflow_node_executions.create!(
      ai_workflow_node: node,
      execution_id: "exec_#{SecureRandom.hex(6)}",
      node_id: node.node_id,
      node_type: node.node_type,
      status: 'completed',
      input_data: index == 0 ? blog_run.input_variables : {},
      output_data: {
        'processed' => true,
        'node_type' => node.node_type,
        'execution_order' => index + 1
      },
      configuration_snapshot: node.configuration,
      duration_ms: 15000,
      cost: 0.04,
      started_at: blog_run.started_at + (index * 15).seconds,
      completed_at: blog_run.started_at + ((index + 1) * 15).seconds
    )
  end
end

# Create a running data analysis run
unless data_analysis_workflow.workflow_runs.exists?(status: 'running')
  puts "📊 Creating sample data analysis run..."

  analysis_run = data_analysis_workflow.workflow_runs.create!(
    account: admin_account,
    run_id: "run_#{SecureRandom.hex(8)}",
    status: 'running',
    trigger_type: 'api_call',
    triggered_by_user: admin_user,
    input_variables: {
      'data_source' => 'user_engagement_metrics',
      'analysis_type' => 'trend_analysis',
      'time_period' => '30_days'
    },
    total_cost: 0.08,
    total_nodes: 3,
    completed_nodes: 1,
    failed_nodes: 0,
    started_at: 30.minutes.ago,
    metadata: {
      'model_used' => 'gpt-4',
      'provider' => 'openai',
      'estimated_completion' => 15.minutes.from_now
    }
  )

  # Create some completed and running node executions
  data_analysis_workflow.workflow_nodes.limit(2).each_with_index do |node, index|
    status = index == 0 ? 'completed' : 'running'

    analysis_run.ai_workflow_node_executions.create!(
      ai_workflow_node: node,
      execution_id: "exec_#{SecureRandom.hex(6)}",
      node_id: node.node_id,
      node_type: node.node_type,
      status: status,
      input_data: index == 0 ? analysis_run.input_variables : {},
      output_data: status == 'completed' ? {
        'data_processed' => 15000,
        'preliminary_insights' => [ 'User engagement increased 23%', 'Peak activity at 2-4 PM' ]
      } : {},
      configuration_snapshot: node.configuration,
      duration_ms: status == 'completed' ? 25000 : nil,
      cost: status == 'completed' ? 0.04 : 0.0,
      started_at: analysis_run.started_at + (index * 10).minutes,
      completed_at: status == 'completed' ? analysis_run.started_at + ((index + 1) * 10).minutes : nil
    )
  end
end

# 9. Create Sample Template Installations
puts "\n📦 Creating Template Installations..."

# Install blog template for admin account
unless admin_account.ai_workflow_template_installations.exists?(ai_workflow_template: blog_workflow_template)
  puts "💾 Installing blog template..."

  admin_account.ai_workflow_template_installations.create!(
    ai_workflow_template: blog_workflow_template,
    ai_workflow: blog_workflow,
    installed_by_user: admin_user,
    installation_id: "install_#{SecureRandom.hex(8)}",
    template_version: '1.0.0',
    customizations: {
      'default_word_count' => 1500,
      'preferred_agent' => blog_generator_agent.id,
      'auto_seo_optimize' => true
    },
    variable_mappings: {
      'topic' => 'blog_topic',
      'word_count' => 'default_word_count',
      'author' => 'author_name'
    },
    auto_update: false,
    metadata: {
      'installation_notes' => 'Configured for daily tech blog generation with Ollama integration',
      'installation_date' => Time.current.iso8601
    }
  )
end

puts "\n✅ AI Workflow System seeded successfully!"

# Print summary
puts "\n📊 SEEDING SUMMARY:"
puts "===================="
puts "🔧 AI Providers: #{admin_account.ai_providers.count}"
puts "🤖 AI Agents: #{admin_account.ai_agents.count}"
puts "📋 Workflow Templates: #{Ai::WorkflowTemplate.count}"
puts "🔄 Workflows: #{admin_account.ai_workflows.count}"
puts "⏰ Schedules: #{Ai::WorkflowSchedule.where(ai_workflow_id: admin_account.ai_workflows.pluck(:id)).count}"
puts "🎯 Triggers: #{Ai::WorkflowTrigger.where(ai_workflow_id: admin_account.ai_workflows.pluck(:id)).count}"
puts "📦 Template Installations: #{admin_account.ai_workflow_template_installations.count}"

puts "\n🚀 Ready to test workflows!"
puts "\nSample workflow execution:"
puts "curl -X POST http://localhost:3000/api/v1/ai/workflows/#{blog_workflow&.id}/execute \\"
puts "  -H 'Authorization: Bearer YOUR_TOKEN' \\"
puts "  -H 'Content-Type: application/json' \\"
puts "  -d '{\"input_variables\": {\"topic\": \"Getting Started with AI Workflows\", \"word_count\": 1000}}'"

puts "\n🔗 Webhook endpoint:"
puts "POST /api/v1/ai/workflow-triggers/webhook"
puts "Headers: X-Powernode-Webhook-Secret: blog_generation_secret_key_2024"
puts "Body: {\"blog_topic\": \"Your Topic\", \"target_words\": 1500, \"audience\": \"general\"}"
