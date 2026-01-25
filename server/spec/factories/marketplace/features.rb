# frozen_string_literal: true

FactoryBot.define do
  factory :marketplace_feature, class: 'Marketplace::Feature' do
    association :app, factory: :marketplace_definition
    sequence(:name) { |n| "Feature #{n}" }
    sequence(:slug) { |n| "feature_#{n}_#{SecureRandom.hex(4)}" }
    feature_type { 'toggle' }
    description { 'A test feature description' }
    default_enabled { false }
    dependencies { [] }
    configuration { {} }

    trait :enabled_by_default do
      default_enabled { true }
    end

    trait :toggle do
      feature_type { 'toggle' }
    end

    trait :quota do
      feature_type { 'quota' }
      configuration { { 'limit' => 100, 'period' => 'monthly' } }
    end

    trait :permission do
      feature_type { 'permission' }
      configuration { { 'permission' => 'advanced_access' } }
    end

    trait :integration do
      feature_type { 'integration' }
      configuration { { 'provider' => 'external_service' } }
    end

    trait :api_access do
      feature_type { 'api_access' }
      configuration { { 'endpoints' => ['/api/v1/data'], 'methods' => %w[GET POST] } }
    end

    trait :ui_component do
      feature_type { 'ui_component' }
      configuration { { 'component' => 'AdvancedDashboard' } }
    end

    # Alias for backward compatibility
    factory :app_feature, class: 'Marketplace::Feature'
  end
end
