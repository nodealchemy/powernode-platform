# frozen_string_literal: true

FactoryBot.define do
  factory :marketplace_listing do
    sequence(:title) { |n| "Listing #{n}" }
    short_description { 'A short description of the listing' }
    long_description { 'A longer detailed description of the listing with more information about features and benefits.' }
    category { 'productivity' }
    review_status { 'pending' }
    tags { %w[productivity tools automation] }
    screenshots { [] }
    featured { false }
    documentation_url { nil }
    support_url { nil }
    homepage_url { nil }

    trait :pending do
      review_status { 'pending' }
    end

    trait :approved do
      review_status { 'approved' }
    end

    trait :rejected do
      review_status { 'rejected' }
      review_notes { 'Does not meet quality standards' }
    end

    trait :published do
      review_status { 'approved' }
      published_at { Time.current }
    end

    trait :featured do
      featured { true }
      review_status { 'approved' }
      published_at { Time.current }
    end

    trait :with_screenshots do
      screenshots do
        [
          { 'url' => 'https://example.com/screenshot1.png', 'caption' => 'Main dashboard', 'order' => 0 },
          { 'url' => 'https://example.com/screenshot2.png', 'caption' => 'Settings page', 'order' => 1 }
        ]
      end
    end

    trait :with_urls do
      documentation_url { 'https://docs.example.com' }
      support_url { 'https://support.example.com' }
      homepage_url { 'https://example.com' }
    end

    trait :with_tags do
      tags { %w[productivity collaboration business] }
    end
  end
end
