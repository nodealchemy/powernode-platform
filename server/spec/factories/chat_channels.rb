# frozen_string_literal: true

FactoryBot.define do
  factory :chat_channel, class: 'Chat::Channel' do
    account
    sequence(:name) { |n| "Channel #{n}" }
    platform { 'telegram' }
    status { 'disconnected' }
    webhook_token { SecureRandom.urlsafe_base64(32) }
    rate_limit_per_minute { 60 }
    configuration do
      {
        'auto_respond' => true,
        'welcome_message' => 'Hello! How can I help you today?'
      }
    end

    trait :telegram do
      platform { 'telegram' }
      configuration do
        {
          'auto_respond' => true,
          'parse_mode' => 'HTML'
        }
      end
    end

    trait :whatsapp do
      platform { 'whatsapp' }
      configuration do
        {
          'auto_respond' => true,
          'phone_number_id' => '123456789'
        }
      end
    end

    trait :discord do
      platform { 'discord' }
      configuration do
        {
          'auto_respond' => true,
          'guild_id' => '123456789012345678'
        }
      end
    end

    trait :slack do
      platform { 'slack' }
      configuration do
        {
          'auto_respond' => true,
          'team_id' => 'T01234567'
        }
      end
    end

    trait :mattermost do
      platform { 'mattermost' }
      configuration do
        {
          'auto_respond' => true,
          'server_url' => 'https://mattermost.example.com'
        }
      end
    end

    trait :connected do
      status { 'connected' }
      connected_at { 1.hour.ago }
    end

    trait :disconnected do
      status { 'disconnected' }
      connected_at { nil }
    end

    trait :connecting do
      status { 'connecting' }
    end

    trait :error do
      status { 'error' }
    end

    trait :with_default_agent do
      association :default_agent, factory: :ai_agent
    end

    trait :with_sessions do
      after(:create) do |channel|
        create_list(:chat_session, 3, channel: channel)
      end
    end
  end
end
