# frozen_string_literal: true

FactoryBot.define do
  factory :marketplace_category do
    sequence(:name) { |n| "Category #{n}" }
    sequence(:slug) { |n| "category-#{n}-#{SecureRandom.hex(4)}" }
    description { 'A test category description' }
    icon { 'fa-folder' }
    is_active { true }
    sort_order { 0 }

    trait :active do
      is_active { true }
    end

    trait :inactive do
      is_active { false }
    end

    trait :with_custom_icon do
      icon { 'fa-star' }
    end

    trait :high_priority do
      sort_order { 1 }
    end

    trait :low_priority do
      sort_order { 100 }
    end
  end
end
