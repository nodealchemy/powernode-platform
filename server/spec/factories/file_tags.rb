# frozen_string_literal: true

FactoryBot.define do
  factory :file_tag, class: "FileManagement::Tag" do
    account
    sequence(:name) { |n| "Tag #{n}" }
    color { '#3B82F6' }
    description { 'Test tag for organizing files' }
    files_count { 0 }

    trait :important do
      name { 'Important' }
      color { '#EF4444' }
    end

    trait :archive do
      name { 'Archive' }
      color { '#6B7280' }
    end

    trait :ai_generated do
      name { 'AI Generated' }
      color { '#8B5CF6' }
    end
  end
end
