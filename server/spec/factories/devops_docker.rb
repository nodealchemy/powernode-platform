# frozen_string_literal: true

FactoryBot.define do
  factory :devops_docker_host, class: 'Devops::DockerHost' do
    association :account
    sequence(:name) { |n| "Docker Host #{n}" }
    sequence(:api_endpoint) { |n| "https://docker-host-#{n}.example.com:2376" }
    sequence(:slug) { |n| "docker-host-#{n}" }
    environment { 'development' }
    status { 'pending' }
    auto_sync { true }
    sync_interval_seconds { 60 }

    trait :connected do
      status { 'connected' }
    end

    trait :disconnected do
      status { 'disconnected' }
    end

    trait :error do
      status { 'error' }
      consecutive_failures { 5 }
    end

    trait :with_tls do
      encrypted_tls_credentials { SecureRandom.hex(64) }
      encryption_key_id { SecureRandom.uuid }
    end
  end

  factory :devops_docker_container, class: 'Devops::DockerContainer' do
    association :docker_host, factory: :devops_docker_host
    docker_container_id { SecureRandom.hex(32) }
    sequence(:name) { |n| "container-#{n}" }
    image { 'nginx:latest' }
    state { 'created' }

    trait :running do
      state { 'running' }
      started_at { 1.hour.ago }
    end

    trait :stopped do
      state { 'exited' }
      finished_at { 30.minutes.ago }
    end

    trait :exited do
      state { 'exited' }
      finished_at { 30.minutes.ago }
    end

    trait :paused do
      state { 'paused' }
    end
  end

  factory :devops_docker_image, class: 'Devops::DockerImage' do
    association :docker_host, factory: :devops_docker_host
    docker_image_id { "sha256:#{SecureRandom.hex(32)}" }
    repo_tags { ['nginx:latest'] }
    size_bytes { 187_000_000 }

    trait :with_tags do
      repo_tags { ['nginx:latest', 'nginx:1.25'] }
    end

    trait :dangling do
      repo_tags { [] }
    end
  end

  factory :devops_docker_event, class: 'Devops::DockerEvent' do
    association :docker_host, factory: :devops_docker_host
    event_type { 'health_check' }
    severity { 'info' }
    source_type { 'host' }
    sequence(:message) { |n| "Docker event message #{n}" }

    trait :warning do
      severity { 'warning' }
    end

    trait :critical do
      severity { 'critical' }
    end

    trait :acknowledged do
      acknowledged { true }
      association :acknowledged_by, factory: :user
      acknowledged_at { Time.current }
    end
  end

  factory :devops_docker_activity, class: 'Devops::DockerActivity' do
    association :docker_host, factory: :devops_docker_host
    activity_type { 'create' }
    status { 'pending' }

    trait :running do
      status { 'running' }
      started_at { 1.minute.ago }
    end

    trait :completed do
      status { 'completed' }
      started_at { 2.minutes.ago }
      completed_at { 1.minute.ago }
      duration_ms { 60_000 }
    end

    trait :failed do
      status { 'failed' }
      started_at { 2.minutes.ago }
      completed_at { 1.minute.ago }
      result { { 'error' => 'Something went wrong' } }
    end
  end
end
