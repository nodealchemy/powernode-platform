FactoryBot.define do
  factory :worker do
    sequence(:name) { |n| "Worker #{n}" }
    description { "A test worker" }
    status { 'active' }
    association :account
    
    # Create worker with assigned roles after creation
    after(:create) do |worker|
      # Create a basic worker role if it doesn't exist
      worker_role = Role.find_or_create_by(
        name: 'worker',
        role_type: 'user',
        description: 'Basic worker role for testing'
      )
      
      # Assign the role to the worker
      worker.assign_role('worker')
    end

    trait :active do
      status { 'active' }
    end

    trait :suspended do
      status { 'suspended' }
    end

    trait :system_worker do
      account { nil }
      
      after(:create) do |worker|
        # Create system worker role if it doesn't exist
        system_role = Role.find_or_create_by(
          name: 'system_worker',
          role_type: 'system',
          description: 'System worker role for testing'
        )
        
        # Assign the system role
        worker.assign_role('system_worker')
      end
    end
  end
end