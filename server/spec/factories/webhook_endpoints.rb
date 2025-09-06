FactoryBot.define do
  factory :webhook_endpoint do
    association :account
    sequence(:url) { |n| "https://api.example#{n}.com/webhook" }
    status { 'active' }
    is_active { true }
    event_types { ['*'] }
    timeout_seconds { 30 }
    max_retries { 3 }

    trait :active do
      status { 'active' }
      is_active { true }
    end

    trait :inactive do
      status { 'inactive' }
      is_active { false }
    end


    trait :with_specific_events do
      event_types { ['user.created', 'payment.succeeded'] }
    end
  end
end