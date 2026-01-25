# frozen_string_literal: true

FactoryBot.define do
  factory :marketplace_definition, class: 'Marketplace::Definition' do
    association :account
    sequence(:name) { |n| "Test App #{n}" }
    sequence(:slug) { |n| "test-app-#{n}-#{SecureRandom.hex(4)}" }
    version { '1.0.0' }
    status { 'draft' }
    category { 'productivity' }
    description { 'A test application description' }
    short_description { 'A short description' }
    long_description { 'A longer detailed description of the application features and capabilities.' }

    trait :draft do
      status { 'draft' }
    end

    trait :under_review do
      status { 'review' }
    end

    trait :published do
      status { 'published' }
      published_at { Time.current }
    end

    trait :inactive do
      status { 'inactive' }
    end

    trait :with_plans do
      after(:create) do |app|
        create(:marketplace_plan, app: app, is_active: true)
      end
    end

    trait :with_features do
      after(:create) do |app|
        create(:marketplace_feature, app: app)
      end
    end

    # Alias for backward compatibility
    factory :app, class: 'Marketplace::Definition'
  end
end
