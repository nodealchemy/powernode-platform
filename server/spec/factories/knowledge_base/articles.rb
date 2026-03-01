# frozen_string_literal: true

FactoryBot.define do
  factory :kb_article, class: "KnowledgeBase::Article" do
    association :category, factory: :kb_category
    association :author, factory: :user
    sequence(:title) { |n| "Article #{n}" }
    sequence(:slug) { |n| "article-#{n}" }
    content { "This is the content of the test article." }
    excerpt { "This is the excerpt." }
    status { "draft" }
    is_public { false }
    is_featured { false }
    sort_order { 0 }
    views_count { 0 }
    likes_count { 0 }

    trait :published do
      status { "published" }
      is_public { true }
      published_at { Time.current }
    end

    trait :draft do
      status { "draft" }
      is_public { false }
    end

    trait :under_review do
      status { "review" }
    end

    trait :archived do
      status { "archived" }
    end

    trait :featured do
      is_featured { true }
    end

    trait :private do
      is_public { false }
    end

    trait :popular do
      views_count { 1000 }
      likes_count { 100 }
    end
  end
end
