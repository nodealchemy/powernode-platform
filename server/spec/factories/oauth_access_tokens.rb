# frozen_string_literal: true

FactoryBot.define do
  factory :oauth_access_token, class: "Doorkeeper::AccessToken" do
    # Use application_id directly to avoid ActiveRecord::AssociationTypeMismatch
    # between OauthApplication and Doorkeeper::Application
    transient do
      oauth_app { nil }
    end

    token { SecureRandom.hex(32) }
    refresh_token { SecureRandom.hex(32) }
    expires_in { 7200 }
    scopes { "read write" }
    revoked_at { nil }

    after(:build) do |access_token, evaluator|
      if evaluator.oauth_app
        access_token.application_id = evaluator.oauth_app.id
      elsif access_token.application_id.blank?
        app = create(:oauth_application)
        access_token.application_id = app.id
      end
    end

    trait :revoked do
      revoked_at { 1.day.ago }
    end

    trait :expired do
      expires_in { 0 }
    end
  end
end
