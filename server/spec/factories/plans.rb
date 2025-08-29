FactoryBot.define do
  factory :plan do
    sequence(:name) { |n| "Plan #{n}" }
    description { "A great subscription plan" }
    price_cents { 2999 }
    currency { "USD" }
    billing_cycle { "monthly" }
    features { {} }
    limits { {} }
    status { "active" }
    default_roles { [] }
    trial_days { 14 }
    is_public { true }

    # Usage limits traits
    trait :with_limits do
      limits do
        {
          'max_users' => 10,
          'max_api_keys' => 5,
          'max_webhooks' => 5,
          'max_workers' => 3
        }
      end
    end

    trait :unlimited_users do
      limits do
        {
          'max_users' => 9999,
          'max_api_keys' => 5,
          'max_webhooks' => 5,
          'max_workers' => 3
        }
      end
    end

    trait :basic_plan do
      name { 'Basic Plan' }
      price_cents { 1500 }
      limits do
        {
          'max_users' => 5,
          'max_api_keys' => 3,
          'max_webhooks' => 3,
          'max_workers' => 2
        }
      end
    end

    trait :pro_plan do
      name { 'Professional Plan' }
      price_cents { 4900 }
      limits do
        {
          'max_users' => 25,
          'max_api_keys' => 15,
          'max_webhooks' => 15,
          'max_workers' => 10
        }
      end
    end

    trait :enterprise_plan do
      name { 'Enterprise Plan' }
      price_cents { 15000 }
      limits do
        {
          'max_users' => 9999,
          'max_api_keys' => 100,
          'max_webhooks' => 100,
          'max_workers' => 50
        }
      end
    end
  end
end
