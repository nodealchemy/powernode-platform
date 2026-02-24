# frozen_string_literal: true

FactoryBot.define do
  factory :marketing_email_subscriber, class: "Marketing::EmailSubscriber" do
    association :email_list, factory: :marketing_email_list
    sequence(:email) { |n| "subscriber#{n}@example.com" }
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    status { "pending" }
    source { "manual" }
    custom_fields { {} }
    tags { [] }
    preferences { {} }
    bounce_count { 0 }

    trait :subscribed do
      status { "subscribed" }
      subscribed_at { Time.current }
      confirmed_at { Time.current }
    end

    trait :pending do
      status { "pending" }
    end

    trait :unsubscribed do
      status { "unsubscribed" }
      unsubscribed_at { Time.current }
    end

    trait :bounced do
      status { "bounced" }
      bounce_count { 3 }
    end

    trait :complained do
      status { "complained" }
    end

    trait :imported do
      source { "import" }
    end

    trait :api do
      source { "api" }
    end

    trait :with_tags do
      tags { %w[vip early_adopter] }
    end

    trait :with_custom_fields do
      custom_fields { { company: "Acme Corp", role: "Manager" } }
    end
  end
end
