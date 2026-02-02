# frozen_string_literal: true

FactoryBot.define do
  factory :federation_partner do
    account
    sequence(:name) { |n| "Federation Partner #{n}" }
    description { 'A trusted federation partner for agent sharing' }
    endpoint_url { 'https://partner.example.com/a2a' }
    status { 'pending' }
    trust_level { 3 }
    max_requests_per_hour { 1000 }
    federation_token_digest { BCrypt::Password.create('test_token') }
    agent_count { 0 }
    capabilities do
      {
        'supported_protocols' => ['a2a-v0.3'],
        'max_concurrent_tasks' => 10
      }
    end

    trait :pending do
      status { 'pending' }
    end

    trait :active do
      status { 'active' }
      approved_at { 1.day.ago }
    end

    trait :suspended do
      status { 'suspended' }
      suspended_at { 1.hour.ago }
    end

    trait :revoked do
      status { 'revoked' }
      revoked_at { 1.day.ago }
    end

    trait :high_trust do
      trust_level { 5 }
      max_requests_per_hour { 5000 }
    end

    trait :low_trust do
      trust_level { 1 }
      max_requests_per_hour { 100 }
    end

    trait :with_agents do
      agent_count { 10 }
    end

    trait :rate_limited do
      max_requests_per_hour { 10 }
    end
  end
end
