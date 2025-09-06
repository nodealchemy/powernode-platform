# frozen_string_literal: true

FactoryBot.define do
  factory :impersonation_session do
    sequence(:session_token) { |n| "test_token_#{n}_#{SecureRandom.hex(16)}" }
    reason { 'Testing purposes' }
    started_at { Time.current }
    ended_at { nil }  # nil means session is active
    ip_address { '127.0.0.1' }
    user_agent { 'Mozilla/5.0 (Test Browser)' }

    # Create users in same account
    after(:build) do |session|
      # Create a shared account for both users if not set
      shared_account = nil
      
      if session.impersonator.nil? && session.impersonated_user.nil?
        shared_account = create(:account)
        session.impersonator = create(:user, account: shared_account)
        session.impersonated_user = create(:user, account: shared_account)
      elsif session.impersonator.nil?
        # Use impersonated_user's account
        session.impersonator = create(:user, account: session.impersonated_user.account)
      elsif session.impersonated_user.nil?
        # Use impersonator's account
        session.impersonated_user = create(:user, account: session.impersonator.account)
      end
      # If both are set, assume they're already in the correct accounts
    end

    trait :ended do
      ended_at { 1.hour.ago }  # Having ended_at means session is inactive
    end

    trait :expired do
      started_at { ImpersonationSession::MAX_SESSION_DURATION.ago - 1.hour }
      ended_at { nil }  # Still technically active but should be expired based on duration
    end

    trait :with_reason do
      reason { 'Customer support request' }
    end

    trait :without_reason do
      reason { nil }
    end
  end
end