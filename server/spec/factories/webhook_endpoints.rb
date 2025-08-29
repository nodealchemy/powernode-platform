FactoryBot.define do
  factory :webhook_endpoint do
    sequence(:url) { |n| "https://api.example#{n}.com/webhook" }
    status { 'active' }
    content_type { 'application/json' }
    timeout_seconds { 30 }
    retry_limit { 3 }
    event_types { ['*'] }
    association :created_by, factory: :user

    trait :active do
      status { 'active' }
    end

    trait :inactive do
      status { 'inactive' }
    end

    trait :with_specific_events do
      event_types { ['user.created', 'payment.succeeded'] }
    end
  end
end