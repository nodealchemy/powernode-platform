# frozen_string_literal: true

FactoryBot.define do
  factory :plugin do
    association :account
    association :creator, factory: :user
    sequence(:plugin_id) { |n| "test-plugin-#{n}" }
    sequence(:name) { |n| "Test Plugin #{n}" }
    sequence(:slug) { |n| "test-plugin-#{n}-#{SecureRandom.hex(4)}" }
    version { '1.0.0' }
    description { 'A test plugin description' }
    plugin_types { ['workflow_node'] }
    status { 'available' }
    source_type { 'local' }
    source_url { nil }
    is_verified { false }
    is_official { false }
    manifest do
      {
        'manifest_version' => '1.0',
        'plugin' => {
          'id' => plugin_id,
          'name' => name,
          'version' => version
        },
        'plugin_types' => plugin_types
      }
    end
    capabilities { [] }
    configuration { {} }
    metadata { {} }

    trait :installed do
      status { 'installed' }
    end

    trait :verified do
      is_verified { true }
    end

    trait :official do
      is_official { true }
    end

    trait :deprecated do
      status { 'deprecated' }
    end

    trait :error do
      status { 'error' }
    end

    trait :ai_provider do
      plugin_types { ['ai_provider'] }
    end

    trait :workflow_node do
      plugin_types { ['workflow_node'] }
    end

    trait :integration do
      plugin_types { ['integration'] }
    end

    trait :from_git do
      source_type { 'git' }
      source_url { 'https://github.com/example/plugin.git' }
    end

    trait :from_npm do
      source_type { 'npm' }
      source_url { 'https://www.npmjs.com/package/example-plugin' }
    end
  end
end
