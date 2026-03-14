# frozen_string_literal: true

FactoryBot.define do
  factory :devops_resource_quota, class: 'Devops::ResourceQuota' do
    account
    max_concurrent_containers { 5 }
    max_containers_per_hour { 50 }
    max_containers_per_day { 500 }
    max_memory_mb { 512 }
    max_cpu_millicores { 500 }
    max_storage_bytes { 1.gigabyte }
    max_execution_time_seconds { 3600 }
    allow_network_access { true }
    allowed_egress_domains { [] }
    current_running_containers { 0 }
    containers_used_this_hour { 0 }
    containers_used_today { 0 }
    usage_reset_at { Time.current.beginning_of_hour }
    overage_rate_per_container { nil }
    allow_overage { false }

    trait :default do
      max_concurrent_containers { 5 }
      max_containers_per_hour { 50 }
      max_containers_per_day { 500 }
    end

    trait :business do
      max_concurrent_containers { 50 }
      max_containers_per_hour { 500 }
      max_containers_per_day { 5000 }
      max_memory_mb { 4096 }
      max_cpu_millicores { 4000 }
    end

    trait :restricted do
      max_concurrent_containers { 1 }
      max_containers_per_hour { 10 }
      max_containers_per_day { 50 }
      allow_network_access { false }
    end

    trait :with_domain_whitelist do
      allow_network_access { true }
      allowed_egress_domains { [ 'api.openai.com', 'api.anthropic.com', '*.github.com' ] }
    end

    trait :near_limit do
      max_concurrent_containers { 5 }
      current_running_containers { 4 }
      max_containers_per_hour { 50 }
      containers_used_this_hour { 48 }
    end

    trait :at_limit do
      max_concurrent_containers { 5 }
      current_running_containers { 5 }
      max_containers_per_hour { 50 }
      containers_used_this_hour { 50 }
    end

    trait :with_overage do
      allow_overage { true }
      overage_rate_per_container { 0.10 }
    end
  end
end
