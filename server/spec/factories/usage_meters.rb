# frozen_string_literal: true

FactoryBot.define do
  factory :usage_meter do
    sequence(:name) { |n| "Usage Meter #{n}" }
    sequence(:slug) { |n| "usage-meter-#{n}" }
    description { "A test usage meter" }
    unit_name { "units" }
    aggregation_type { "sum" }
    billing_model { "tiered" }
    reset_period { "monthly" }
    is_active { true }
    is_billable { true }
    pricing_tiers do
      [
        { "from" => 0, "to" => 100, "price_per_unit" => 0.10 },
        { "from" => 100, "to" => 1000, "price_per_unit" => 0.05 },
        { "from" => 1000, "price_per_unit" => 0.02 }
      ]
    end

    trait :api_calls do
      name { "API Calls" }
      slug { "api-calls" }
      unit_name { "requests" }
      aggregation_type { "count" }
    end

    trait :storage do
      name { "Storage" }
      slug { "storage" }
      unit_name { "GB" }
      aggregation_type { "max" }
    end

    trait :compute do
      name { "Compute Time" }
      slug { "compute-time" }
      unit_name { "minutes" }
      aggregation_type { "sum" }
    end

    trait :flat_rate do
      billing_model { "flat" }
      pricing_tiers { [ { "price" => 99.00 } ] }
    end

    trait :per_unit do
      billing_model { "per_unit" }
      pricing_tiers { [ { "price_per_unit" => 0.01 } ] }
    end

    trait :volume do
      billing_model { "volume" }
      pricing_tiers do
        [
          { "from" => 0, "price_per_unit" => 0.10 },
          { "from" => 100, "price_per_unit" => 0.08 },
          { "from" => 1000, "price_per_unit" => 0.05 }
        ]
      end
    end

    trait :package do
      billing_model { "package" }
      pricing_tiers { [ { "package_size" => 100, "price" => 10.00 } ] }
    end

    trait :daily_reset do
      reset_period { "daily" }
    end

    trait :weekly_reset do
      reset_period { "weekly" }
    end

    trait :never_reset do
      reset_period { "never" }
    end

    trait :inactive do
      is_active { false }
    end

    trait :non_billable do
      is_billable { false }
    end
  end
end
