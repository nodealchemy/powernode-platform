# frozen_string_literal: true

FactoryBot.define do
  factory :ai_workflow_template_installation do
    ai_workflow_template
    ai_workflow { create(:ai_workflow, account: account) }
    account
    installed_by_user { create(:user, account: account) }
    installation_id { "inst_#{SecureRandom.hex(12)}" }
    template_version { '1.0.0' }
    customizations { {} }
    variable_mappings { {} }
    metadata do
      {
        installation_method: 'template_marketplace',
        installation_source: 'web_ui',
        timestamp: Time.current.iso8601
      }
    end

    trait :pending do
      metadata do
        {
          installation_method: 'api',
          queued_at: Time.current.iso8601,
          estimated_completion: 5.minutes.from_now.iso8601,
          status: 'pending'
        }
      end
    end

    trait :in_progress do
      metadata do
        {
          started_at: 2.minutes.ago.iso8601,
          current_step: 'creating_workflow',
          total_steps: 5,
          completed_steps: 2,
          progress_percentage: 40,
          status: 'in_progress'
        }
      end
    end

    trait :failed do
      metadata do
        {
          error_type: 'insufficient_permissions',
          error_message: 'User lacks required permissions to install this template',
          error_code: 'PERMISSION_DENIED',
          timestamp: Time.current.iso8601,
          retry_count: 2,
          status: 'failed',
          started_at: 10.minutes.ago.iso8601,
          failed_at: 8.minutes.ago.iso8601,
          failure_step: 'permission_validation'
        }
      end
    end

    trait :with_customizations do
      customizations do
        {
          workflow: {
            name: 'Customized Workflow Name',
            configuration: {
              max_execution_time: 7200,
              notification_settings: {
                email: 'custom@example.com'
              }
            }
          },
          nodes: {
            'ai_agent_node': {
              configuration: {
                model: 'gpt-4',
                temperature: 0.5,
                system_prompt: 'Custom system prompt for this installation'
              }
            }
          }
        }
      end
      variable_mappings do
        [
          {
            name: 'custom_variable',
            type: 'string',
            default_value: 'custom_default',
            description: 'Custom variable for this installation'
          }
        ]
      end
    end

    trait :with_created_workflow do
      after(:create) do |installation|
        workflow = create(:ai_workflow,
                         account: installation.account,
                         name: "#{installation.ai_workflow_template.name} (Installed)",
                         description: installation.ai_workflow_template.description,
                         metadata: {
                           created_from_template: true,
                           template_id: installation.ai_workflow_template.id,
                           installation_id: installation.id
                         })

        installation.update!(ai_workflow: workflow)
      end
    end

    trait :enterprise_template do
      ai_workflow_template { create(:ai_workflow_template, :complex) }
      customizations do
        {
          workflow: {
            configuration: {
              execution_mode: 'parallel',
              max_parallel_nodes: 10,
              resource_limits: {
                max_memory_mb: 1024,
                max_cpu_percent: 80
              },
              enterprise_features: {
                audit_logging: true,
                advanced_monitoring: true,
                priority_execution: 'high'
              }
            }
          },
          security: {
            encryption_enabled: true,
            access_control: 'strict',
            data_retention_days: 90
          }
        }
      end
    end

    trait :blog_generation_template do
      ai_workflow_template { create(:ai_workflow_template, :content_generation) }
      customizations do
        {
          workflow: {
            name: 'My Blog Generator',
            configuration: {
              default_word_count: 1200,
              writing_style: 'professional',
              seo_optimization: true
            }
          },
          nodes: {
            'topic_analyzer': {
              configuration: {
                temperature: 0.2,
                analysis_depth: 'comprehensive'
              }
            },
            'content_writer': {
              configuration: {
                temperature: 0.8,
                creativity_level: 'high',
                include_examples: true
              }
            }
          }
        }
      end
      variable_mappings do
        [
          {
            name: 'brand_voice',
            type: 'string',
            default_value: 'friendly and professional',
            description: 'Brand voice for content generation'
          },
          {
            name: 'target_keywords',
            type: 'array',
            default_value: [],
            description: 'SEO keywords to include'
          }
        ]
      end
    end

    trait :data_processing_template do
      ai_workflow_template { create(:ai_workflow_template, :data_processing) }
      customizations do
        {
          workflow: {
            name: 'Custom Data Pipeline',
            configuration: {
              batch_size: 1000,
              parallel_processing: true,
              error_tolerance: 0.05,
              data_validation: {
                schema_validation: true,
                duplicate_detection: true,
                quality_threshold: 0.95
              }
            }
          }
        }
      end
      variable_mappings do
        [
          {
            name: 'data_source_type',
            type: 'string',
            default_value: 'postgresql',
            description: 'Type of data source'
          },
          {
            name: 'output_format',
            type: 'string',
            default_value: 'json',
            description: 'Output data format'
          }
        ]
      end
    end

    trait :with_deployment_config do
      customizations do
        {
          deployment: {
            environment: 'production',
            scaling: {
              min_instances: 1,
              max_instances: 5,
              target_cpu_utilization: 70
            },
            monitoring: {
              metrics_enabled: true,
              logging_level: 'info',
              alerts: {
                failure_rate_threshold: 5.0,
                response_time_threshold: 30000
              }
            },
            networking: {
              timeout_seconds: 30,
              retry_attempts: 3,
              circuit_breaker_enabled: true
            }
          }
        }
      end
    end

    trait :with_integration_config do
      customizations do
        {
          integrations: {
            slack: {
              webhook_url: 'https://hooks.slack.com/services/TEST/WEBHOOK',
              channel: '#ai-workflows',
              notification_types: [ 'completion', 'failure' ]
            },
            email: {
              smtp_server: 'smtp.example.com',
              from_address: 'workflows@example.com',
              recipients: [ 'admin@example.com' ]
            },
            database: {
              connection_string: 'postgresql://user:pass@localhost/db',
              pool_size: 10,
              timeout: 5000
            },
            external_apis: {
              rate_limiting: {
                requests_per_minute: 60,
                burst_allowance: 10
              },
              authentication: {
                type: 'api_key',
                key_rotation_days: 30
              }
            }
          }
        }
      end
    end

    trait :multi_tenant do
      customizations do
        {
          multi_tenancy: {
            tenant_isolation: 'strict',
            resource_quotas: {
              max_workflows_per_tenant: 100,
              max_executions_per_hour: 1000,
              max_storage_mb: 10240
            },
            tenant_specific_config: {
              branding: {
                logo_url: 'https://example.com/logo.png',
                primary_color: '#1a73e8',
                company_name: 'Example Corp'
              },
              features: {
                advanced_analytics: true,
                custom_integrations: true,
                priority_support: true
              }
            }
          }
        }
      end
    end

    trait :with_permissions_check do
      after(:build) do |installation|
        installation.metadata = installation.metadata.merge(
          required_permissions: [
            'ai_workflows.create',
            'ai_workflows.execute',
            'ai_providers.read',
            'webhooks.create'
          ],
          permission_check_status: 'validated',
          missing_permissions: []
        )
      end
    end

    trait :insufficient_permissions do
      metadata do
        {
          error_type: 'insufficient_permissions',
          error_message: 'Missing required permissions',
          status: 'failed',
          missing_permissions: [
            'ai_workflows.execute',
            'webhooks.create'
          ],
          required_permissions: [
            'ai_workflows.create',
            'ai_workflows.read',
            'ai_workflows.execute',
            'ai_providers.read',
            'webhooks.create'
          ]
        }
      end
    end

    trait :with_rollback_plan do
      metadata do
        {
          rollback_plan: {
            enabled: true,
            backup_created: true,
            backup_id: SecureRandom.uuid,
            rollback_steps: [
              'remove_created_workflow',
              'cleanup_generated_resources',
              'restore_previous_configuration',
              'update_installation_status'
            ]
          },
          installation_checkpoints: [
            {
              step: 'permission_validation',
              status: 'completed',
              timestamp: 5.minutes.ago.iso8601
            },
            {
              step: 'resource_creation',
              status: 'completed',
              timestamp: 3.minutes.ago.iso8601
            },
            {
              step: 'configuration_apply',
              status: 'in_progress',
              timestamp: 1.minute.ago.iso8601
            }
          ]
        }
      end
    end

    # Factory for testing batch installations
    trait :batch_installation do
      metadata do
        {
          batch_installation: true,
          batch_id: SecureRandom.uuid,
          batch_size: 5,
          batch_position: 1,
          parallel_installation: true,
          batch_coordinator: 'system'
        }
      end
    end
  end
end
