# frozen_string_literal: true

FactoryBot.define do
  factory :chat_blacklist, class: 'Chat::Blacklist' do
    account
    sequence(:platform_user_id) { |n| "blocked_user_#{n}_#{SecureRandom.hex(4)}" }
    block_type { 'permanent' }
    reason { 'Spam or abuse' }
    expires_at { nil }
    association :blocked_by, factory: :user

    trait :permanent do
      block_type { 'permanent' }
      expires_at { nil }
    end

    trait :temporary do
      block_type { 'temporary' }
      expires_at { 7.days.from_now }
    end

    trait :expired do
      block_type { 'temporary' }
      expires_at { 1.day.ago }
    end

    trait :channel_specific do
      association :channel, factory: :chat_channel
    end

    trait :account_wide do
      channel { nil }
    end

    trait :spam do
      reason { 'Sending spam messages' }
    end

    trait :abuse do
      reason { 'Abusive behavior' }
    end

    trait :harassment do
      reason { 'Harassment' }
    end
  end
end
