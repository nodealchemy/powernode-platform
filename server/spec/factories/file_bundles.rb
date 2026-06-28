# frozen_string_literal: true

FactoryBot.define do
  factory :file_bundle, class: "FileManagement::Bundle" do
    account
    association :created_by, factory: :user
    sequence(:name) { |n| "Content Bundle #{n}" }
    bundle_type { "video_project" }
    status { "draft" }
    metadata { {} }

    trait :document do
      bundle_type { "document" }
    end

    trait :ready do
      status { "ready" }
    end
  end
end
