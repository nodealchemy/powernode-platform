# frozen_string_literal: true

FactoryBot.define do
  factory :kb_workflow, class: "KnowledgeBase::Workflow" do
    association :article, factory: :kb_article
    association :user
    action { "create" }
    from_status { nil }
    to_status { "draft" }
    comment { "Workflow action performed" }
    metadata { {} }

    trait :create_action do
      action { "create" }
      from_status { nil }
      to_status { "draft" }
    end

    trait :edit_action do
      action { "edit" }
      from_status { "draft" }
      to_status { "draft" }
    end

    trait :publish_action do
      action { "publish" }
      from_status { "draft" }
      to_status { "published" }
    end

    trait :unpublish_action do
      action { "unpublish" }
      from_status { "published" }
      to_status { "draft" }
    end

    trait :archive_action do
      action { "archive" }
      from_status { "published" }
      to_status { "archived" }
    end

    trait :review_action do
      action { "review" }
      from_status { "draft" }
      to_status { "review" }
    end

    trait :delete_action do
      action { "delete" }
    end
  end
end
