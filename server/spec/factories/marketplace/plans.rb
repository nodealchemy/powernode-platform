# frozen_string_literal: true

FactoryBot.define do
  factory :marketplace_plan, class: 'Marketplace::Plan' do
    association :app, factory: :marketplace_definition
    sequence(:name) { |n| "Plan #{n}" }
    sequence(:slug) { |n| "plan-#{n}-#{SecureRandom.hex(4)}" }
    price_cents { 1000 }
    billing_interval { 'monthly' }
    description { 'A test plan description' }
    features { [] }
    permissions { [] }
    limits { {} }
    metadata { {} }
    is_active { true }
    is_public { true }

    trait :free do
      price_cents { 0 }
    end

    trait :monthly do
      billing_interval { 'monthly' }
    end

    trait :yearly do
      billing_interval { 'yearly' }
    end

    trait :one_time do
      billing_interval { 'one_time' }
    end

    trait :inactive do
      is_active { false }
    end

    trait :private do
      is_public { false }
    end

    trait :with_features do
      features { %w[feature_one feature_two] }
    end

    trait :with_permissions do
      permissions { %w[read write admin] }
    end

    trait :with_limits do
      limits { { 'api_calls' => 1000, 'storage_mb' => 500 } }
    end

    # Alias for backward compatibility
    factory :app_plan, class: 'Marketplace::Plan'
  end
end
