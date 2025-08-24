FactoryBot.define do
  factory :permission do
    sequence(:resource) { |n| "test_resource_#{n}" }
    sequence(:action) { |n| "test_action_#{n}" }
    category { 'resource' }
    description { Faker::Lorem.sentence }
    
    # Name will be auto-generated from resource and action
    
    # Trait for creating specific permissions that might already exist
    trait :users_create do
      resource { 'users' }
      action { 'create' }
    end
    
    trait :users_read do
      resource { 'users' }
      action { 'read' }
    end
  end
end
