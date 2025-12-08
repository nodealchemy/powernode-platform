# frozen_string_literal: true

FactoryBot.define do
  factory :ai_workflow_template do
    sequence(:name) { |n| "#{Faker::App.name} Template #{n}" }
    description { Faker::Lorem.paragraph }
    category { 'general' }
    version { '1.0.0' }
    difficulty_level { 'beginner' }
    is_public { false }
    is_featured { false }
    usage_count { 0 }
    rating { 0.0 }
    rating_count { 0 }

    # Set workflow_definition with required nodes and edges structure
    workflow_definition do
      {
        nodes: [
          {
            node_id: 'start_node',
            node_type: 'start',
            name: 'Start',
            position: { x: 100, y: 300 },
            configuration: { enabled: true }
          },
          {
            node_id: 'end_node',
            node_type: 'end',
            name: 'End',
            position: { x: 400, y: 300 },
            configuration: { enabled: true }
          }
        ],
        edges: [
          {
            source_node_id: 'start_node',
            target_node_id: 'end_node',
            edge_type: 'default',
            condition: {},
            configuration: { label: 'Complete' }
          }
        ]
      }
    end

    metadata do
      {
        complexity: 'simple',
        estimated_execution_time: 300,
        use_cases: ['general_automation'],
        tags: ['ai', 'automation']
      }
    end

    trait :public do
      is_public { true }
    end

    trait :content_generation do
      category { 'content_generation' }
      name { 'Blog Post Generator' }
      description { 'Automated blog post creation with AI assistance' }
      template_data do
        {
          workflow: {
            name: 'Blog Post Generation',
            description: 'Generate high-quality blog posts on any topic',
            configuration: {
              execution_mode: 'sequential',
              max_execution_time: 1800,
              output_format: 'markdown'
            },
            nodes: [
              {
                node_id: 'start_node',
                node_type: 'start',
                name: 'Start',
                position: { x: 100, y: 300 },
                configuration: {}
              },
              {
                node_id: 'topic_analyzer',
                node_type: 'ai_agent',
                name: 'Topic Analyzer',
                position: { x: 300, y: 300 },
                configuration: {
                  model: 'gpt-4',
                  temperature: 0.3,
                  system_prompt: 'Analyze the given topic and create a detailed outline.'
                }
              },
              {
                node_id: 'content_writer',
                node_type: 'ai_agent',
                name: 'Content Writer',
                position: { x: 500, y: 300 },
                configuration: {
                  model: 'gpt-4',
                  temperature: 0.8,
                  system_prompt: 'Write engaging blog content based on the provided outline.'
                }
              },
              {
                node_id: 'content_reviewer',
                node_type: 'ai_agent',
                name: 'Content Reviewer',
                position: { x: 700, y: 300 },
                configuration: {
                  model: 'claude-3-sonnet',
                  temperature: 0.2,
                  system_prompt: 'Review and improve the blog post for quality and coherence.'
                }
              },
              {
                node_id: 'end_node',
                node_type: 'end',
                name: 'End',
                position: { x: 900, y: 300 },
                configuration: {}
              }
            ],
            edges: [
              {
                source_node_id: 'start_node',
                target_node_id: 'topic_analyzer',
                edge_type: 'default'
              },
              {
                source_node_id: 'topic_analyzer',
                target_node_id: 'content_writer',
                edge_type: 'default'
              },
              {
                source_node_id: 'content_writer',
                target_node_id: 'content_reviewer',
                edge_type: 'default'
              },
              {
                source_node_id: 'content_reviewer',
                target_node_id: 'end_node',
                edge_type: 'default'
              }
            ]
          },
          variables: [
            {
              name: 'blog_topic',
              type: 'string',
              required: true,
              description: 'The main topic for the blog post'
            },
            {
              name: 'target_audience',
              type: 'string',
              required: false,
              default_value: 'general',
              description: 'Target audience for the content'
            },
            {
              name: 'word_count',
              type: 'number',
              required: false,
              default_value: 1000,
              description: 'Approximate word count'
            }
          ]
        }
      end
      metadata do
        {
          complexity: 'medium',
          estimated_execution_time: 900,
          use_cases: ['blog_writing', 'content_marketing'],
          tags: ['content', 'ai', 'blog', 'writing']
        }
      end
    end

    trait :data_processing do
      category { 'data_processing' }
      name { 'Data Processing Pipeline' }
      description { 'ETL workflow for data transformation and analysis' }
      template_data do
        {
          workflow: {
            name: 'Data Processing Pipeline',
            configuration: {
              execution_mode: 'parallel',
              max_execution_time: 7200
            },
            nodes: [
              {
                node_id: 'data_extractor',
                node_type: 'api_call',
                name: 'Data Extractor',
                configuration: {
                  method: 'GET',
                  url: '{{data_source_url}}',
                  headers: { 'Authorization': 'Bearer {{api_token}}' }
                }
              },
              {
                node_id: 'data_transformer',
                node_type: 'transform',
                name: 'Data Transformer',
                configuration: {
                  script: 'output = transformData(input);',
                  language: 'javascript'
                }
              },
              {
                node_id: 'data_loader',
                node_type: 'api_call',
                name: 'Data Loader',
                configuration: {
                  method: 'POST',
                  url: '{{target_database_url}}',
                  headers: { 'Content-Type': 'application/json' }
                }
              }
            ]
          },
          variables: [
            {
              name: 'data_source_url',
              type: 'string',
              required: true,
              description: 'Source data API endpoint'
            },
            {
              name: 'target_database_url',
              type: 'string',
              required: true,
              description: 'Target database endpoint'
            },
            {
              name: 'api_token',
              type: 'string',
              required: true,
              sensitive: true,
              description: 'API authentication token'
            }
          ]
        }
      end
    end

    trait :customer_support do
      category { 'customer_support' }
      name { 'Customer Support Automation' }
      description { 'Automated customer inquiry processing' }
      template_data do
        {
          workflow: {
            name: 'Customer Support Automation',
            nodes: [
              {
                node_id: 'inquiry_classifier',
                node_type: 'ai_agent',
                name: 'Inquiry Classifier',
                configuration: {
                  model: 'gpt-3.5-turbo',
                  system_prompt: 'Classify customer inquiries by category and urgency.'
                }
              },
              {
                node_id: 'urgency_check',
                node_type: 'condition',
                name: 'Urgency Check',
                configuration: {
                  expression: 'classification.urgency == "high"'
                }
              },
              {
                node_id: 'auto_responder',
                node_type: 'ai_agent',
                name: 'Auto Responder',
                configuration: {
                  model: 'gpt-4',
                  system_prompt: 'Generate helpful customer support responses.'
                }
              },
              {
                node_id: 'escalation_alert',
                node_type: 'webhook',
                name: 'Escalation Alert',
                configuration: {
                  url: '{{support_team_webhook}}',
                  method: 'POST'
                }
              }
            ]
          },
          variables: [
            {
              name: 'customer_inquiry',
              type: 'string',
              required: true,
              description: 'Customer inquiry text'
            },
            {
              name: 'customer_id',
              type: 'string',
              required: true,
              description: 'Customer identifier'
            }
          ]
        }
      end
    end

    trait :social_media do
      category { 'marketing' }
      name { 'Social Media Content Creator' }
      description { 'Generate and schedule social media content' }
      template_data do
        {
          workflow: {
            name: 'Social Media Content Creation',
            nodes: [
              {
                node_id: 'content_generator',
                node_type: 'ai_agent',
                name: 'Content Generator',
                configuration: {
                  model: 'gpt-4',
                  temperature: 0.9,
                  system_prompt: 'Create engaging social media content.'
                }
              },
              {
                node_id: 'hashtag_generator',
                node_type: 'ai_agent',
                name: 'Hashtag Generator',
                configuration: {
                  model: 'gpt-3.5-turbo',
                  system_prompt: 'Generate relevant hashtags for social media posts.'
                }
              },
              {
                node_id: 'platform_scheduler',
                node_type: 'api_call',
                name: 'Platform Scheduler',
                configuration: {
                  method: 'POST',
                  url: '{{social_media_api_url}}/schedule'
                }
              }
            ]
          }
        }
      end
    end

    trait :email_marketing do
      category { 'marketing' }
      name { 'Email Campaign Generator' }
      description { 'Generate personalized email marketing campaigns' }
    end

    trait :code_review do
      category { 'development' }
      name { 'Code Review Assistant' }
      description { 'Automated code review and improvement suggestions' }
      template_data do
        {
          workflow: {
            name: 'Code Review Assistant',
            nodes: [
              {
                node_id: 'code_analyzer',
                node_type: 'ai_agent',
                name: 'Code Analyzer',
                configuration: {
                  model: 'claude-3-sonnet',
                  system_prompt: 'Analyze code for quality, security, and best practices.'
                }
              },
              {
                node_id: 'security_scanner',
                node_type: 'ai_agent',
                name: 'Security Scanner',
                configuration: {
                  model: 'gpt-4',
                  system_prompt: 'Scan code for security vulnerabilities.'
                }
              },
              {
                node_id: 'report_generator',
                node_type: 'transform',
                name: 'Report Generator',
                configuration: {
                  script: 'generateCodeReviewReport(input);'
                }
              }
            ]
          },
          variables: [
            {
              name: 'code_content',
              type: 'text',
              required: true,
              description: 'Code to review'
            },
            {
              name: 'programming_language',
              type: 'string',
              required: true,
              description: 'Programming language'
            }
          ]
        }
      end
    end

    trait :with_installations do
      after(:create) do |template|
        3.times do
          account = create(:account)
          create(:ai_workflow_template_installation,
                 ai_workflow_template: template,
                 account: account,
                 installed_by_user: create(:user, account: account).id)
        end
      end
    end

    trait :popular do
      after(:create) do |template|
        10.times do
          account = create(:account)
          create(:ai_workflow_template_installation,
                 ai_workflow_template: template,
                 account: account)
        end
      end
    end

    trait :complex do
      metadata do
        {
          complexity: 'high',
          estimated_execution_time: 3600,
          node_count: 15,
          use_cases: ['enterprise_automation', 'complex_workflows'],
          tags: ['advanced', 'enterprise', 'complex']
        }
      end
    end

    trait :with_dependencies do
      template_data do
        base_data = attributes_for(:ai_workflow_template)[:template_data]
        base_data.merge(
          dependencies: {
            required_integrations: ['openai', 'slack', 'webhook'],
            minimum_permissions: [
              'ai_workflows.create',
              'ai_workflows.execute',
              'ai_providers.read'
            ],
            external_apis: [
              { name: 'OpenAI API', required: true },
              { name: 'Slack API', required: false }
            ]
          }
        )
      end
    end

    trait :versioned do
      version { '2.1.0' }
      metadata do
        {
          changelog: [
            { version: '2.1.0', changes: 'Added error handling improvements' },
            { version: '2.0.0', changes: 'Major workflow redesign' },
            { version: '1.0.0', changes: 'Initial release' }
          ],
          breaking_changes: false,
          upgrade_notes: 'No breaking changes in this version'
        }
      end
    end
  end
end