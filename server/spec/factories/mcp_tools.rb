# frozen_string_literal: true

FactoryBot.define do
  factory :mcp_tool do
    mcp_server
    sequence(:name) { |n| "mcp_tool_#{n}_#{SecureRandom.hex(3)}" }
    description { "MCP tool for testing" }
    input_schema do
      {
        'type' => 'object',
        'properties' => {
          'param1' => {
            'type' => 'string',
            'description' => 'First parameter'
          },
          'param2' => {
            'type' => 'number',
            'description' => 'Second parameter'
          }
        },
        'required' => ['param1']
      }
    end

    # Enabled/disabled traits for tool state
    trait :enabled do
      enabled { true }
    end

    trait :disabled do
      enabled { false }
    end

    trait :read_file do
      name { 'read_file' }
      description { 'Read contents of a file' }
      input_schema do
        {
          'type' => 'object',
          'properties' => {
            'path' => {
              'type' => 'string',
              'description' => 'Path to the file'
            },
            'encoding' => {
              'type' => 'string',
              'description' => 'File encoding',
              'default' => 'utf-8'
            }
          },
          'required' => ['path']
        }
      end
    end

    trait :write_file do
      name { 'write_file' }
      description { 'Write content to a file' }
      input_schema do
        {
          'type' => 'object',
          'properties' => {
            'path' => {
              'type' => 'string',
              'description' => 'Path to the file'
            },
            'content' => {
              'type' => 'string',
              'description' => 'Content to write'
            },
            'mode' => {
              'type' => 'string',
              'description' => 'Write mode (overwrite or append)',
              'enum' => ['overwrite', 'append'],
              'default' => 'overwrite'
            }
          },
          'required' => ['path', 'content']
        }
      end
    end

    trait :list_directory do
      name { 'list_directory' }
      description { 'List files and directories' }
      input_schema do
        {
          'type' => 'object',
          'properties' => {
            'path' => {
              'type' => 'string',
              'description' => 'Directory path'
            },
            'recursive' => {
              'type' => 'boolean',
              'description' => 'List recursively',
              'default' => false
            },
            'pattern' => {
              'type' => 'string',
              'description' => 'File pattern to match'
            }
          },
          'required' => ['path']
        }
      end
    end

    trait :execute_query do
      name { 'execute_query' }
      description { 'Execute a database query' }
      input_schema do
        {
          'type' => 'object',
          'properties' => {
            'query' => {
              'type' => 'string',
              'description' => 'SQL query to execute'
            },
            'database' => {
              'type' => 'string',
              'description' => 'Database name'
            },
            'readonly' => {
              'type' => 'boolean',
              'description' => 'Execute in readonly mode',
              'default' => true
            }
          },
          'required' => ['query', 'database']
        }
      end
    end

    trait :search_web do
      name { 'search_web' }
      description { 'Search the web for information' }
      input_schema do
        {
          'type' => 'object',
          'properties' => {
            'query' => {
              'type' => 'string',
              'description' => 'Search query'
            },
            'max_results' => {
              'type' => 'number',
              'description' => 'Maximum number of results',
              'default' => 10
            },
            'safe_search' => {
              'type' => 'boolean',
              'description' => 'Enable safe search',
              'default' => true
            }
          },
          'required' => ['query']
        }
      end
    end

    trait :send_email do
      name { 'send_email' }
      description { 'Send an email message' }
      input_schema do
        {
          'type' => 'object',
          'properties' => {
            'to' => {
              'type' => 'string',
              'description' => 'Recipient email address'
            },
            'subject' => {
              'type' => 'string',
              'description' => 'Email subject'
            },
            'body' => {
              'type' => 'string',
              'description' => 'Email body'
            },
            'html' => {
              'type' => 'boolean',
              'description' => 'Send as HTML',
              'default' => false
            }
          },
          'required' => ['to', 'subject', 'body']
        }
      end
    end

    trait :with_executions do
      after(:create) do |tool|
        create_list(:mcp_tool_execution, 5, mcp_tool: tool)
      end
    end

    trait :recently_used do
      after(:create) do |tool|
        create_list(:mcp_tool_execution, 3, :completed, mcp_tool: tool, created_at: 1.hour.ago)
      end
    end
  end
end
