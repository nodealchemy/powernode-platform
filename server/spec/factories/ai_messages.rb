# frozen_string_literal: true

FactoryBot.define do
  factory :ai_message do
    ai_conversation
    ai_agent
    sequence(:message_id) { |n| "msg_#{n}" }
    role { 'user' }
    content { Faker::Lorem.paragraph }
    message_type { 'text' }
    token_count { 10 }
    cost_usd { 0.001 }
    status { 'sent' }
    sequence_number { 1 }
    processing_metadata do
      {
        timestamp: Time.current.iso8601,
        channel: 'api',
        processing_time_ms: 0
      }
    end

    trait :user_message do
      role { 'user' }
      content { Faker::Lorem.question }
      processing_metadata do
        {
          timestamp: Time.current.iso8601,
          channel: 'websocket',
          user_agent: 'Mozilla/5.0...',
          ip_address: '127.0.0.1'
        }
      end
    end

    trait :ai_response do
      role { 'assistant' }
      content { Faker::Lorem.paragraph }
      token_count { 125 }
      cost_usd { 0.0025 }
      processing_metadata do
        {
          timestamp: Time.current.iso8601,
          provider_id: SecureRandom.uuid,
          model_used: 'gpt-3.5-turbo',
          tokens_used: 125,
          response_time_ms: 1500,
          cost_estimate: 0.0025,
          processing_complete: true
        }
      end
    end

    trait :system_message do
      sender_type { 'system' }
      sender_id { nil }
      content { 'System: Conversation started' }
      metadata do
        {
          timestamp: Time.current.iso8601,
          message_type: 'system_notification',
          automated: true
        }
      end
    end

    trait :processing do
      sender_type { 'ai' }
      content { '' }
      metadata do
        {
          timestamp: Time.current.iso8601,
          processing: true,
          started_at: Time.current.iso8601,
          provider_id: SecureRandom.uuid
        }
      end
    end

    trait :error_message do
      sender_type { 'ai' }
      content { 'I apologize, but I encountered an error processing your request.' }
      metadata do
        {
          timestamp: Time.current.iso8601,
          error: true,
          error_message: 'Provider timeout',
          error_code: 'TIMEOUT',
          failed_at: Time.current.iso8601,
          processing_complete: true
        }
      end
    end

    trait :with_attachments do
      content { 'Please see the attached files for the analysis results.' }
      metadata do
        {
          timestamp: Time.current.iso8601,
          attachments: [
            {
              name: 'analysis.pdf',
              type: 'application/pdf',
              size: 245760,
              url: 'https://example.com/files/analysis.pdf'
            },
            {
              name: 'data.csv',
              type: 'text/csv',
              size: 51200,
              url: 'https://example.com/files/data.csv'
            }
          ],
          has_attachments: true
        }
      end
    end

    trait :code_response do
      sender_type { 'ai' }
      content do
        "Here's the Python code you requested:\n\n```python\ndef fibonacci(n):\n    if n <= 1:\n        return n\n    return fibonacci(n-1) + fibonacci(n-2)\n\nprint(fibonacci(10))\n```"
      end
      metadata do
        {
          timestamp: Time.current.iso8601,
          provider_id: SecureRandom.uuid,
          model_used: 'claude-3-sonnet',
          tokens_used: 89,
          response_time_ms: 2100,
          cost_estimate: 0.0045,
          processing_complete: true,
          contains_code: true,
          programming_language: 'python'
        }
      end
    end

    trait :long_response do
      sender_type { 'ai' }
      content { Faker::Lorem.paragraphs(10).join("\n\n") }
      metadata do
        {
          timestamp: Time.current.iso8601,
          provider_id: SecureRandom.uuid,
          model_used: 'gpt-4',
          tokens_used: 856,
          response_time_ms: 8500,
          cost_estimate: 0.0342,
          processing_complete: true,
          response_length: 'long'
        }
      end
    end
  end
end
