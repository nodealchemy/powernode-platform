# frozen_string_literal: true

FactoryBot.define do
  factory :impersonation_session do
    session_token { SecureRandom.hex(32) }
    reason { 'Testing purposes' }
    started_at { Time.current }
    ended_at { nil }
    ip_address { '127.0.0.1' }
    user_agent { 'Mozilla/5.0 (Test Browser)' }
    active { true }

    # Create users in same account
    after(:build) do |session|
      if session.account.nil?
        session.account = create(:account)
      end
      
      if session.impersonator.nil?
        session.impersonator = create(:user, account: session.account)
      else
        session.impersonator.update!(account: session.account)
      end
      
      if session.impersonated_user.nil?
        session.impersonated_user = create(:user, account: session.account)
      else
        session.impersonated_user.update!(account: session.account)
      end
    end

    trait :ended do
      active { false }
      ended_at { 1.hour.ago }
    end

    trait :expired do
      started_at { ImpersonationSession::MAX_SESSION_DURATION.ago - 1.hour }
      active { true }
    end

    trait :with_reason do
      reason { 'Customer support request' }
    end

    trait :without_reason do
      reason { nil }
    end
  end
end