# frozen_string_literal: true

FactoryBot.define do
  factory :marketing_social_media_account, class: "Marketing::SocialMediaAccount" do
    account
    platform { "twitter" }
    sequence(:platform_account_id) { |n| "account_#{n}" }
    platform_username { "powernode_official" }
    status { "connected" }
    post_count { 0 }
    scopes { "read,write" }
    token_expires_at { 30.days.from_now }

    trait :twitter do
      platform { "twitter" }
    end

    trait :linkedin do
      platform { "linkedin" }
      platform_username { "Powernode Inc" }
    end

    trait :facebook do
      platform { "facebook" }
      platform_username { "Powernode Page" }
    end

    trait :instagram do
      platform { "instagram" }
      platform_username { "powernode_ig" }
    end

    trait :disconnected do
      status { "disconnected" }
    end

    trait :expired do
      status { "expired" }
      token_expires_at { 1.day.ago }
    end

    trait :error do
      status { "error" }
    end

    trait :expiring_soon do
      token_expires_at { 3.days.from_now }
    end

    trait :with_user do
      association :connected_by, factory: :user
    end
  end
end
