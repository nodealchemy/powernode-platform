# frozen_string_literal: true

FactoryBot.define do
  factory :marketing_content_calendar, class: "Marketing::ContentCalendar" do
    account
    title { "Blog Post: Monthly Update" }
    entry_type { "post" }
    scheduled_date { 1.week.from_now.to_date }
    scheduled_time { "09:00" }
    status { "planned" }
    all_day { false }
    color { "#4A90D9" }
    metadata { {} }

    trait :email do
      entry_type { "email" }
      title { "Newsletter Send" }
    end

    trait :social do
      entry_type { "social" }
      title { "Social Media Post" }
    end

    trait :event do
      entry_type { "event" }
      title { "Product Launch Event" }
      all_day { true }
    end

    trait :reminder do
      entry_type { "reminder" }
      title { "Content Review Deadline" }
    end

    trait :scheduled do
      status { "scheduled" }
    end

    trait :published do
      status { "published" }
    end

    trait :cancelled do
      status { "cancelled" }
    end

    trait :with_campaign do
      association :campaign, factory: :marketing_campaign
    end

    trait :today do
      scheduled_date { Date.current }
    end

    trait :past do
      scheduled_date { 1.week.ago.to_date }
    end
  end
end
