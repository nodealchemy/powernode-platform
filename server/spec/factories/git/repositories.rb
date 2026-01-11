# frozen_string_literal: true

FactoryBot.define do
  factory :git_repository, class: 'Devops::GitRepository' do
    association :credential, factory: :git_provider_credential
    association :account

    sequence(:external_id) { |n| "repo#{n}" }
    sequence(:name) { |n| "test-repo-#{n}" }
    sequence(:full_name) { |n| "testuser/test-repo-#{n}" }
    owner { 'testuser' }
    description { 'A test repository' }
    default_branch { 'main' }
    clone_url { "https://github.com/#{owner}/#{name}.git" }
    ssh_url { "git@github.com:#{owner}/#{name}.git" }
    web_url { "https://github.com/#{owner}/#{name}" }
    is_private { false }
    is_fork { false }
    is_archived { false }
    webhook_configured { false }
    webhook_id { nil }
    webhook_secret { nil }
    languages { { 'Ruby' => 70, 'JavaScript' => 30 } }
    topics { %w[rails api] }
    stars_count { 10 }
    forks_count { 2 }
    open_issues_count { 5 }
    open_prs_count { 1 }
    last_synced_at { nil }
    last_commit_at { nil }

    trait :private do
      is_private { true }
    end

    trait :fork do
      is_fork { true }
    end

    trait :archived do
      is_archived { true }
    end

    trait :with_webhook do
      webhook_configured { true }
      webhook_id { 'webhook_123' }
      webhook_secret { SecureRandom.hex(20) }
    end

    trait :synced do
      last_synced_at { 1.hour.ago }
      last_commit_at { 2.hours.ago }
    end

    trait :popular do
      stars_count { 1000 }
      forks_count { 100 }
    end
  end
end
