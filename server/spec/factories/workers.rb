# frozen_string_literal: true

FactoryBot.define do
  factory :worker do
    sequence(:name) { |n| "Worker #{n}" }
    description { "A test worker" }
    status { 'active' }
    association :account
    # Workers-as-NodeInstances (Stage 8b): every Worker is backed by a
    # NodeInstance that carries its mTLS identity. For tests we just need
    # a unique UUID — the actual NodeInstance row isn't required because
    # InternalBaseController does `Worker.find_by(node_instance_id: cn)`
    # rather than traversing the association. Specs that DO need a real
    # NodeInstance row should set node_instance_id: explicitly.
    node_instance_id { UUID7.generate }

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
      association :account
      is_system { true }

      after(:create) do |worker|
        # Create system worker role if it doesn't exist
        Role.find_or_create_by(
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
