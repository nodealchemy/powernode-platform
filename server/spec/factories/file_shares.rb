# frozen_string_literal: true

FactoryBot.define do
  factory :file_share, class: "FileManagement::Share" do
    association :object, factory: :file_object
    account
    association :created_by, factory: :user

    share_token { SecureRandom.urlsafe_base64(32) }
    share_type { 'public_link' }
    access_level { 'view' }

    status { 'active' }
    download_count { 0 }

    recipients { [] }
    access_log { [] }
    metadata { {} }

    trait :with_password do
      password_digest { BCrypt::Password.create('secret123') }
    end

    trait :with_expiration do
      expires_at { 7.days.from_now }
    end

    trait :with_download_limit do
      max_downloads { 10 }
    end

    trait :email_share do
      share_type { 'email' }
      recipients { [ 'test@example.com' ] }
    end

    trait :user_share do
      share_type { 'user' }
    end

    trait :downloadable do
      access_level { 'download' }
    end

    trait :expired do
      status { 'expired' }
      expires_at { 1.day.ago }
    end

    trait :revoked do
      status { 'revoked' }
    end
  end
end
