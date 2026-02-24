# frozen_string_literal: true

FactoryBot.define do
  factory :marketing_email_list, class: "Marketing::EmailList" do
    account
    sequence(:name) { |n| "Email List #{n}" }
    list_type { "standard" }
    subscriber_count { 0 }
    double_opt_in { false }
    dynamic_filter { {} }

    trait :dynamic do
      list_type { "dynamic" }
      dynamic_filter { { status: "active", tags: ["vip"] } }
    end

    trait :segment do
      list_type { "segment" }
      dynamic_filter { { purchase_count: { gte: 5 } } }
    end

    trait :with_double_opt_in do
      double_opt_in { true }
    end

    trait :with_welcome_email do
      welcome_email_subject { "Welcome to our newsletter!" }
      welcome_email_body { "Thank you for subscribing. Stay tuned for updates." }
    end

    trait :with_subscribers do
      after(:create) do |list|
        create_list(:marketing_email_subscriber, 3, :subscribed, email_list: list)
        list.update_subscriber_count!
      end
    end
  end
end
