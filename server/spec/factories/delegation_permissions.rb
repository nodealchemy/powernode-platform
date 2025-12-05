# frozen_string_literal: true

FactoryBot.define do
  factory :delegation_permission do
    association :account_delegation
    association :permission
  end
end
