# frozen_string_literal: true

FactoryBot.define do
  factory :chat_session, class: 'Chat::Session' do
    association :channel, factory: :chat_channel
    sequence(:platform_user_id) { |n| "user_#{n}_#{SecureRandom.hex(4)}" }
    status { 'active' }
    message_count { 0 }
    last_activity_at { Time.current }
    context_window { {} }
    user_metadata do
      {
        'user_name' => Faker::Name.name,
        'language' => 'en'
      }
    end

    trait :active do
      status { 'active' }
      last_activity_at { 5.minutes.ago }
    end

    trait :idle do
      status { 'idle' }
      last_activity_at { 2.hours.ago }
    end

    trait :closed do
      status { 'closed' }
      last_activity_at { 1.day.ago }
    end

    trait :blocked do
      status { 'blocked' }
    end

    trait :with_messages do
      after(:create) do |session|
        create_list(:chat_message, 5, session: session)
        session.update!(message_count: 5)
      end
    end

    trait :with_agent do
      association :assigned_agent, factory: :ai_agent
    end

    trait :with_conversation do
      association :ai_conversation, factory: :ai_conversation
    end

    trait :with_context do
      context_window do
        [
          { 'role' => 'user', 'content' => 'Hello', 'timestamp' => 1.minute.ago.iso8601 },
          { 'role' => 'assistant', 'content' => 'Hi there!', 'timestamp' => 30.seconds.ago.iso8601 }
        ]
      end
    end
  end
end
