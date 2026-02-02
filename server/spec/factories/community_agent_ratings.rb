# frozen_string_literal: true

FactoryBot.define do
  factory :community_agent_rating do
    association :community_agent
    association :user
    association :account
    rating { rand(1..5) }
    review { Faker::Lorem.paragraph(sentence_count: 2) }
    verified_usage { false }
    hidden { false }

    trait :five_star do
      rating { 5 }
      review { 'Excellent agent! Works perfectly for my use case.' }
    end

    trait :four_star do
      rating { 4 }
      review { 'Good agent, minor issues but overall useful.' }
    end

    trait :three_star do
      rating { 3 }
      review { 'Average performance, could be improved.' }
    end

    trait :two_star do
      rating { 2 }
      review { 'Below expectations, several issues encountered.' }
    end

    trait :one_star do
      rating { 1 }
      review { 'Did not work as expected.' }
    end

    trait :verified do
      verified_usage { true }
    end

    trait :hidden do
      hidden { true }
    end

    trait :with_dimensions do
      rating_dimensions do
        {
          'reliability' => rand(1..5),
          'speed' => rand(1..5),
          'accuracy' => rand(1..5),
          'ease_of_use' => rand(1..5)
        }
      end
    end
  end
end
