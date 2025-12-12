# frozen_string_literal: true

FactoryBot.define do
  factory :ai_workflow_variable do
    ai_workflow
    sequence(:name) { |n| "variable_#{n}" }
    variable_type { 'string' }
    scope { 'workflow' }
    default_value { 'default_test_value' }
    is_required { false }
    is_input { true }
    is_output { false }
    is_secret { false }
    description { "Test variable for #{name}" }
    validation_rules { {} }
    metadata do
      {
        created_by: 'system',
        category: 'input',
        usage_context: 'workflow_execution'
      }
    end

    trait :required do
      is_required { true }
      default_value { nil }
    end

    trait :sensitive do
      is_secret { true }
      is_output { false }
      default_value { nil }
      metadata do
        {
          encryption_required: true,
          masked_in_logs: true,
          access_level: 'restricted'
        }
      end
    end

    trait :string_type do
      variable_type { 'string' }
      default_value { 'sample_string_value' }
      validation_rules do
        {
          min_length: 1,
          max_length: 255,
          pattern: '^[a-zA-Z0-9_\\-\\s]+$'
        }
      end
    end

    trait :number_type do
      variable_type { 'number' }
      default_value { 42 }
      validation_rules do
        {
          min_value: 0,
          max_value: 1000
        }
      end
    end

    # Note: 'integer' is not a supported type, use 'number' instead
    trait :integer_type do
      variable_type { 'number' }
      default_value { 10 }
      validation_rules do
        {
          min_value: 1,
          max_value: 100
        }
      end
    end

    trait :boolean_type do
      variable_type { 'boolean' }
      default_value { false }
      validation_rules { {} }
    end

    trait :array_type do
      variable_type { 'array' }
      default_value { [ 'item1', 'item2', 'item3' ] }
      validation_rules do
        {
          min_items: 1,
          max_items: 10,
          unique_items: true,
          item_type: 'string'
        }
      end
    end

    trait :object_type do
      variable_type { 'object' }
      default_value do
        {
          name: 'Test Object',
          value: 123,
          active: true
        }
      end
      validation_rules do
        {
          required_properties: [ 'name' ],
          properties: {
            name: { type: 'string', min_length: 1 },
            value: { type: 'number', min: 0 },
            active: { type: 'boolean' }
          }
        }
      end
    end

    trait :json_type do
      variable_type { 'json' }
      default_value do
        {
          config: {
            timeout: 30,
            retries: 3,
            endpoints: [ 'https://api1.example.com', 'https://api2.example.com' ]
          },
          metadata: {
            version: '1.0',
            created_at: Time.current.iso8601
          }
        }
      end
      validation_rules do
        {
          json_schema: {
            type: 'object',
            properties: {
              config: {
                type: 'object',
                required: [ 'timeout' ]
              }
            }
          }
        }
      end
    end

    # Note: 'text' is not a supported type, use 'string' instead
    trait :text_type do
      variable_type { 'string' }
      default_value { 'This is a longer text value that can contain multiple lines and paragraphs.' }
      validation_rules do
        {
          min_length: 10,
          max_length: 10000
        }
      end
    end

    # Note: 'url' is not a supported type, use 'string' with format validation
    trait :url_type do
      variable_type { 'string' }
      default_value { 'https://example.com/api/endpoint' }
      validation_rules do
        {
          format: 'url'
        }
      end
    end

    # Note: 'email' is not a supported type, use 'string' with format validation
    trait :email_type do
      variable_type { 'string' }
      default_value { 'test@example.com' }
      validation_rules do
        {
          format: 'email'
        }
      end
    end

    # Note: 'password' is not a supported type, use 'string' with is_secret flag
    trait :password_type do
      variable_type { 'string' }
      is_secret { true }
      is_output { false }
      default_value { nil }
      validation_rules do
        {
          min_length: 8,
          max_length: 128
        }
      end
    end

    trait :date_type do
      variable_type { 'date' }
      default_value { Date.current.iso8601 }
      validation_rules do
        {
          min_date: '2020-01-01',
          max_date: '2030-12-31',
          format: 'iso8601'
        }
      end
    end

    trait :datetime_type do
      variable_type { 'datetime' }
      default_value { Time.current.iso8601 }
      validation_rules do
        {
          timezone: 'UTC',
          format: 'iso8601',
          min_datetime: '2020-01-01T00:00:00Z'
        }
      end
    end

    trait :file_type do
      variable_type { 'file' }
      default_value { nil }
      validation_rules do
        {
          allowed_extensions: [ '.txt', '.csv', '.json', '.xml' ],
          max_size_mb: 10,
          required_mime_types: [ 'text/plain', 'text/csv', 'application/json' ]
        }
      end
    end

    # Note: 'enum' is not a supported type, use 'string' with allowed_values
    trait :enum_type do
      variable_type { 'string' }
      default_value { 'option1' }
      validation_rules do
        {
          allowed_values: [ 'option1', 'option2', 'option3' ]
        }
      end
    end

    trait :regex_pattern do
      variable_type { 'string' }
      validation_rules do
        {
          pattern: '^[A-Z]{2,3}-\\d{4,6}$',
          pattern_description: 'Format: ABC-123456 (2-3 letters, dash, 4-6 digits)'
        }
      end
    end

    # Specific workflow variable types
    trait :ai_model_config do
      name { 'ai_model_config' }
      variable_type { 'object' }
      default_value do
        {
          model: 'gpt-3.5-turbo',
          temperature: 0.7,
          max_tokens: 1000,
          top_p: 1.0,
          frequency_penalty: 0.0,
          presence_penalty: 0.0
        }
      end
      validation_rules do
        {
          properties: {
            model: {
              type: 'string',
              enum: [ 'gpt-3.5-turbo', 'gpt-4', 'claude-3-sonnet', 'claude-3-haiku' ]
            },
            temperature: { type: 'number', min: 0, max: 2 },
            max_tokens: { type: 'integer', min: 1, max: 4000 }
          },
          required_properties: [ 'model' ]
        }
      end
    end

    trait :webhook_config do
      name { 'webhook_config' }
      variable_type { 'object' }
      default_value do
        {
          url: 'https://webhook.example.com/notify',
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer {{auth_token}}'
          },
          timeout: 30
        }
      end
      validation_rules do
        {
          properties: {
            url: { type: 'string', format: 'url' },
            method: { type: 'string', enum: [ 'GET', 'POST', 'PUT', 'PATCH' ] },
            timeout: { type: 'integer', min: 1, max: 300 }
          },
          required_properties: [ 'url', 'method' ]
        }
      end
    end

    trait :api_credentials do
      name { 'api_credentials' }
      variable_type { 'object' }
      is_secret { true }
      default_value { nil }
      validation_rules do
        {
          properties: {
            api_key: { type: 'string', min_length: 20 },
            api_secret: { type: 'string', min_length: 40 },
            base_url: { type: 'string', format: 'url' }
          },
          required_properties: [ 'api_key' ],
          sensitive_fields: [ 'api_key', 'api_secret' ]
        }
      end
    end

    trait :data_source_config do
      name { 'data_source_config' }
      variable_type { 'object' }
      default_value do
        {
          type: 'database',
          connection_string: 'postgresql://user:pass@localhost/db',
          query: 'SELECT * FROM users WHERE active = true',
          batch_size: 1000
        }
      end
      validation_rules do
        {
          properties: {
            type: { type: 'string', enum: [ 'database', 'api', 'file', 'stream' ] },
            connection_string: { type: 'string', min_length: 10 },
            batch_size: { type: 'integer', min: 1, max: 10000 }
          }
        }
      end
    end

    trait :notification_settings do
      name { 'notification_settings' }
      variable_type { 'object' }
      default_value do
        {
          channels: [ 'email' ],
          on_success: false,
          on_failure: true,
          on_timeout: true,
          recipients: [ 'admin@example.com' ]
        }
      end
      validation_rules do
        {
          properties: {
            channels: {
              type: 'array',
              items: { enum: [ 'email', 'slack', 'webhook', 'sms' ] }
            },
            recipients: {
              type: 'array',
              items: { type: 'string', format: 'email' }
            }
          }
        }
      end
    end

    trait :processing_options do
      name { 'processing_options' }
      variable_type { 'object' }
      default_value do
        {
          parallel_processing: true,
          max_concurrency: 5,
          timeout_seconds: 300,
          retry_attempts: 3,
          retry_delay: 5
        }
      end
    end

    trait :output_format_config do
      name { 'output_format' }
      variable_type { 'enum' }
      default_value { 'json' }
      validation_rules do
        {
          allowed_values: [ 'json', 'xml', 'csv', 'yaml', 'plain_text' ],
          case_sensitive: false
        }
      end
    end

    # Blog generation specific variables
    trait :blog_topic do
      name { 'blog_topic' }
      variable_type { 'string' }
      is_required { true }
      default_value { nil }
      description { 'The main topic for the blog post' }
      validation_rules do
        {
          min_length: 5,
          max_length: 200,
          pattern: '^[a-zA-Z0-9\\s\\-_:,\\.\\?\\!]+$'
        }
      end
    end

    trait :target_audience do
      name { 'target_audience' }
      variable_type { 'enum' }
      default_value { 'general' }
      description { 'Target audience for the content' }
      validation_rules do
        {
          allowed_values: [
            'general',
            'beginner',
            'intermediate',
            'expert',
            'technical',
            'business',
            'academic'
          ]
        }
      end
    end

    trait :word_count_target do
      name { 'word_count_target' }
      variable_type { 'integer' }
      default_value { 800 }
      description { 'Target word count for the content' }
      validation_rules do
        {
          min: 200,
          max: 5000
        }
      end
    end

    trait :writing_style do
      name { 'writing_style' }
      variable_type { 'object' }
      default_value do
        {
          tone: 'professional',
          formality: 'medium',
          include_examples: true,
          include_statistics: false,
          call_to_action: true
        }
      end
    end

    trait :seo_keywords do
      name { 'seo_keywords' }
      variable_type { 'array' }
      default_value { [] }
      description { 'SEO keywords to include in the content' }
      validation_rules do
        {
          max_items: 10,
          item_type: 'string',
          item_rules: {
            min_length: 2,
            max_length: 50
          }
        }
      end
    end

    # Data processing variables
    trait :batch_size do
      name { 'batch_size' }
      variable_type { 'integer' }
      default_value { 100 }
      description { 'Number of records to process in each batch' }
      validation_rules do
        {
          min: 1,
          max: 10000
        }
      end
    end

    trait :data_validation_rules do
      name { 'validation_rules' }
      variable_type { 'object' }
      default_value do
        {
          required_fields: [],
          data_types: {},
          custom_validators: [],
          error_tolerance: 0.05
        }
      end
    end

    trait :with_complex_validation do
      validation_rules do
        {
          conditional_validation: {
            if: { field: 'type', equals: 'premium' },
            then: {
              required: [ 'api_key', 'secret' ],
              properties: {
                api_key: { min_length: 32 }
              }
            }
          },
          cross_field_validation: {
            start_date_before_end_date: {
              fields: [ 'start_date', 'end_date' ],
              rule: 'start_date < end_date'
            }
          },
          async_validation: {
            url_accessibility: {
              field: 'webhook_url',
              validator: 'http_head_request',
              timeout: 5
            }
          }
        }
      end
    end

    trait :environment_specific do
      metadata do
        {
          environment_overrides: {
            development: { default_value: 'dev_value' },
            staging: { default_value: 'staging_value' },
            production: { default_value: 'prod_value' }
          },
          override_strategy: 'environment_first'
        }
      end
    end
  end
end
