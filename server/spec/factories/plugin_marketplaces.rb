# frozen_string_literal: true

FactoryBot.define do
  factory :plugin_marketplace do
    association :account
    association :creator, factory: :user
    sequence(:name) { |n| "Plugin Marketplace #{n}" }
    sequence(:slug) { |n| "plugin-marketplace-#{n}-#{SecureRandom.hex(4)}" }
    owner { 'Test Owner' }
    description { 'A test plugin marketplace' }
    marketplace_type { 'public' }
    source_type { 'git' }
    source_url { 'https://github.com/example/plugins' }
    visibility { 'public' }
    plugin_count { 0 }
    average_rating { nil }
    configuration { {} }
    metadata { {} }

    trait :public do
      visibility { 'public' }
      marketplace_type { 'public' }
    end

    trait :private do
      visibility { 'private' }
      marketplace_type { 'private' }
    end

    trait :team do
      visibility { 'team' }
      marketplace_type { 'team' }
    end

    trait :from_npm do
      source_type { 'npm' }
      source_url { 'https://www.npmjs.com/org/example' }
    end

    trait :from_git do
      source_type { 'git' }
      source_url { 'https://github.com/example/plugins' }
    end
  end
end
