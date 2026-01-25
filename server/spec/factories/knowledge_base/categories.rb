# frozen_string_literal: true

FactoryBot.define do
  factory :kb_category, class: "KnowledgeBase::Category" do
    sequence(:name) { |n| "Category #{n}" }
    sequence(:slug) { |n| "category-#{n}" }
    description { "A test category" }
    is_public { true }
    sort_order { 0 }

    trait :private do
      is_public { false }
    end

    trait :with_parent do
      association :parent, factory: :kb_category
    end

    trait :root do
      parent { nil }
    end
  end
end
