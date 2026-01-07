# frozen_string_literal: true

FactoryBot.define do
  factory :ai_workflow_approval_token do
    association :ai_workflow_node_execution
    recipient_email { Faker::Internet.email }
    token_digest { Digest::SHA256.hexdigest(SecureRandom.urlsafe_base64(32)) }
    status { 'pending' }
    expires_at { 24.hours.from_now }

    trait :approved do
      status { 'approved' }
      responded_at { Time.current }
      response_comment { 'Approved' }
    end

    trait :rejected do
      status { 'rejected' }
      responded_at { Time.current }
      response_comment { 'Rejected' }
    end

    trait :expired do
      status { 'expired' }
      expires_at { 1.hour.ago }
    end

    trait :with_user do
      association :recipient_user, factory: :user
    end
  end
end
