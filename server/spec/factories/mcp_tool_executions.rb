# frozen_string_literal: true

FactoryBot.define do
  factory :mcp_tool_execution do
    mcp_tool
    user
    status { 'pending' }
    parameters do
      {
        param1: 'test_value',
        param2: 42
      }
    end
    result { {} }
    error_message { nil }
    execution_time_ms { nil }

    trait :pending do
      status { 'pending' }
      result { {} }
      execution_time_ms { nil }
    end

    trait :running do
      status { 'running' }
      result { {} }
      execution_time_ms { nil }
    end

    trait :completed do
      status { 'completed' }
      result do
        {
          success: true,
          data: 'Execution completed successfully',
          timestamp: Time.current.iso8601
        }
      end
      execution_time_ms { rand(100..5000) }
    end

    # Alias for completed (commonly used in tests)
    trait :success do
      status { 'completed' }
      result do
        {
          success: true,
          data: 'Execution completed successfully',
          timestamp: Time.current.iso8601
        }
      end
      execution_time_ms { rand(100..5000) }
    end

    trait :failed do
      status { 'failed' }
      error_message { "Tool execution failed: unexpected error occurred" }
      result do
        {
          success: false,
          error: error_message
        }
      end
      execution_time_ms { rand(100..3000) }
    end

    trait :cancelled do
      status { 'cancelled' }
      error_message { 'Execution cancelled by user' }
      result { {} }
      execution_time_ms { rand(50..1000) }
    end

    trait :read_file_execution do
      parameters do
        {
          path: '/workspace/documents/report.pdf',
          encoding: 'utf-8'
        }
      end

      trait :completed do
        status { 'completed' }
        result do
          {
            success: true,
            content: 'File contents here...',
            size: 15_420,
            mime_type: 'text/plain'
          }
        end
        execution_time_ms { rand(100..500) }
      end
    end

    trait :write_file_execution do
      parameters do
        {
          path: '/workspace/output/result.txt',
          content: 'Generated content',
          mode: 'overwrite'
        }
      end

      trait :completed do
        status { 'completed' }
        result do
          {
            success: true,
            bytes_written: 256,
            path: '/workspace/output/result.txt'
          }
        end
        execution_time_ms { rand(50..300) }
      end
    end

    trait :query_execution do
      parameters do
        {
          query: 'SELECT * FROM users WHERE active = true',
          database: 'production',
          readonly: true
        }
      end

      trait :completed do
        status { 'completed' }
        result do
          {
            success: true,
            rows: [
              { id: 1, name: 'John Doe', active: true },
              { id: 2, name: 'Jane Smith', active: true }
            ],
            row_count: 2,
            execution_time_ms: 45
          }
        end
        execution_time_ms { 145 }
      end
    end

    trait :search_execution do
      parameters do
        {
          query: 'Ruby on Rails best practices',
          max_results: 10,
          safe_search: true
        }
      end

      trait :completed do
        status { 'completed' }
        result do
          {
            success: true,
            results: [
              {
                title: 'Rails Guides',
                url: 'https://guides.rubyonrails.org',
                snippet: 'Official Rails documentation...'
              },
              {
                title: 'Rails Best Practices',
                url: 'https://rails-bestpractices.com',
                snippet: 'Collection of best practices...'
              }
            ],
            result_count: 10,
            search_time_ms: 250
          }
        end
        execution_time_ms { 450 }
      end
    end

    trait :fast_execution do
      execution_time_ms { rand(10..100) }
    end

    trait :slow_execution do
      execution_time_ms { rand(5000..15000) }
    end

    trait :timeout_error do
      status { 'failed' }
      error_message { 'Execution timeout after 30 seconds' }
      execution_time_ms { 30_000 }
    end

    trait :permission_error do
      status { 'failed' }
      error_message { 'Permission denied: insufficient privileges' }
      execution_time_ms { rand(50..200) }
    end

    trait :invalid_parameters do
      status { 'failed' }
      error_message { 'Invalid parameters: required field missing' }
      execution_time_ms { rand(10..50) }
    end
  end
end
