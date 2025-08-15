FactoryBot.define do
  factory :password_history do
    user
    password_digest { BCrypt::Password.create('old_password123!', cost: BCrypt::Engine::MIN_COST) }
    created_at { 1.week.ago }

    trait :recent do
      created_at { 1.day.ago }
    end

    trait :old do
      created_at { 6.months.ago }
    end
  end
end
