# frozen_string_literal: true

FactoryBot.define do
  factory :ai_conversation do
    account
    ai_agent
    title { Faker::Lorem.sentence }
    status { 'active' }
    metadata do
      {
        created_by: SecureRandom.uuid,
        total_messages: 0,
        total_tokens: 0,
        total_cost: 0.0,
        last_activity: Time.current.iso8601
      }
    end
    
    trait :with_messages do
      after(:create) do |conversation|
        # Create initial user message
        create(:ai_message, :user_message, 
               ai_conversation: conversation, 
               account: conversation.account)
        
        # Create AI response
        create(:ai_message, :ai_response, 
               ai_conversation: conversation, 
               account: conversation.account,
               ai_agent: conversation.ai_agent)
        
        # Update conversation metadata
        conversation.update!(
          metadata: conversation.metadata.merge(
            total_messages: 2,
            total_tokens: 150,
            total_cost: 0.003
          )
        )
      end
    end
    
    trait :long_conversation do
      after(:create) do |conversation|
        # Create alternating user and AI messages
        10.times do |i|
          if i.even?
            create(:ai_message, :user_message, 
                   ai_conversation: conversation, 
                   account: conversation.account,
                   content: "User message #{i + 1}")
          else
            create(:ai_message, :ai_response, 
                   ai_conversation: conversation, 
                   account: conversation.account,
                   ai_agent: conversation.ai_agent,
                   content: "AI response to message #{i}")
          end
        end
        
        conversation.update!(
          metadata: conversation.metadata.merge(
            total_messages: 10,
            total_tokens: 1500,
            total_cost: 0.030
          )
        )
      end
    end
    
    trait :completed do
      status { 'completed' }
      metadata do
        {
          created_by: SecureRandom.uuid,
          total_messages: 6,
          total_tokens: 450,
          total_cost: 0.009,
          completed_at: Time.current.iso8601,
          completion_reason: 'user_ended'
        }
      end
    end
    
    trait :archived do
      status { 'archived' }
      metadata do
        {
          created_by: SecureRandom.uuid,
          total_messages: 12,
          total_tokens: 800,
          total_cost: 0.016,
          archived_at: Time.current.iso8601,
          archive_reason: 'auto_archive'
        }
      end
    end
    
    trait :error_state do
      status { 'error' }
      metadata do
        {
          created_by: SecureRandom.uuid,
          total_messages: 3,
          total_tokens: 75,
          total_cost: 0.0015,
          error: 'provider_unavailable',
          error_message: 'AI provider is currently unavailable',
          error_at: Time.current.iso8601
        }
      end
    end
  end
end