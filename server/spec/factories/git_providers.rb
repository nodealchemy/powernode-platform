# frozen_string_literal: true

FactoryBot.define do
  factory :git_provider do
    sequence(:name) { |n| "Git Provider #{n}" }
    sequence(:slug) { |n| "git-provider-#{n}" }
    provider_type { 'github' }
    description { 'A test Git provider' }
    api_base_url { nil }
    web_base_url { nil }
    capabilities { %w[repos branches commits pull_requests issues webhooks] }
    oauth_config { {} }
    webhook_config { { events: %w[push pull_request] } }
    ci_cd_config { {} }
    is_active { true }
    supports_oauth { true }
    supports_pat { true }
    supports_webhooks { true }
    supports_ci_cd { false }
    sequence(:priority_order) { |n| n }

    trait :github do
      name { 'GitHub' }
      slug { 'github' }
      provider_type { 'github' }
      api_base_url { 'https://api.github.com' }
      web_base_url { 'https://github.com' }
      capabilities { %w[repos branches commits pull_requests issues webhooks actions] }
      supports_ci_cd { true }
      ci_cd_config do
        {
          runner_type: 'github_actions',
          supports_workflow_dispatch: true,
          supports_job_logs: true
        }
      end
    end

    trait :gitlab do
      name { 'GitLab' }
      slug { 'gitlab' }
      provider_type { 'gitlab' }
      api_base_url { 'https://gitlab.com/api/v4' }
      web_base_url { 'https://gitlab.com' }
      capabilities { %w[repos branches commits merge_requests issues webhooks pipelines] }
      supports_ci_cd { true }
      ci_cd_config do
        {
          runner_type: 'gitlab_ci',
          supports_job_logs: true
        }
      end
    end

    trait :gitea do
      name { 'Gitea' }
      sequence(:slug) { |n| n == 1 ? 'gitea' : "gitea-#{n}" }
      provider_type { 'gitea' }
      api_base_url { 'https://gitea.example.com/api/v1' }
      web_base_url { 'https://gitea.example.com' }
      capabilities { %w[repos branches commits pull_requests issues webhooks ci_cd act_runner] }
      supports_oauth { true }
      supports_pat { true }
      supports_webhooks { true }
      supports_ci_cd { true }
      ci_cd_config do
        {
          runner_type: 'act_runner',
          supports_workflow_dispatch: true,
          supports_job_logs: true
        }
      end
    end

    trait :inactive do
      is_active { false }
    end

    trait :with_ci_cd do
      supports_ci_cd { true }
      ci_cd_config do
        {
          runner_type: 'github_actions',
          supports_workflow_dispatch: true,
          supports_job_logs: true
        }
      end
    end
  end
end
