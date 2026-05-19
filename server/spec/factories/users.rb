# frozen_string_literal: true

# Make this factory self-sufficient in both rspec and rails-runner contexts.
# RSpec autoloads spec/support/ + the test gems via rails_helper.rb; bare
# rails-runner code paths (smoke seeds calling FactoryBot.create(:user))
# don't. Explicit requires let `FactoryBot.create(:user)` work everywhere.
# Reference: audit discovery 2026-05-18 — sdwan_factories.rb smoke surfaced.
require_relative "../support/test_users"
require "faker"

FactoryBot.define do
  factory :user do
    association :account
    sequence(:email) { |n| "user#{n}@#{TestUsers::DOMAIN}" }
    name { Faker::Name.name }
    password { TestUsers::PASSWORD }
    status { 'active' }
    email_verified_at { 1.day.ago }

    # Transient attribute for permissions
    transient do
      permissions { nil }  # nil means use default role, [] means no permissions
    end

    # Set permissions before creation using the virtual attribute
    before(:create) do |user, evaluator|
      # Only set permissions if explicitly provided (even if empty array)
      unless evaluator.permissions.nil?
        user.permissions = evaluator.permissions
      end
    end

    # Default role assignment happens in after_create callback
    after(:create) do |user, evaluator|
      # User gets 'member' role by default via model callback if no custom permissions
    end

    trait :owner do
      after(:create) do |user|
        user.roles = []
        user.add_role('owner')
      end
    end

    trait :admin do
      after(:create) do |user|
        user.roles = []
        user.add_role('admin')
      end
    end

    trait :super_admin do
      after(:create) do |user|
        user.roles = []
        user.add_role('super_admin')
      end
    end

    trait :manager do
      after(:create) do |user|
        user.roles = []
        user.add_role('manager')
      end
    end

    trait :member do
      after(:create) do |user|
        user.roles = []
        user.add_role('member')
      end
    end

    trait :billing_admin do
      after(:create) do |user|
        user.roles = []
        user.add_role('billing_admin')
      end
    end

    trait :system_admin do
      after(:create) do |user|
        user.roles = []
        user.add_role('system_admin')
      end
    end

    trait :inactive do
      status { 'inactive' }
    end

    trait :suspended do
      status { 'suspended' }
    end

    trait :unverified do
      email_verified_at { nil }
    end
  end
end
