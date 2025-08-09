FactoryBot.define do
  factory :blacklisted_token do
    token { SecureRandom.hex(32) }
    expires_at { 1.hour.from_now }
    reason { "logout" }
    association :user
  end
end
