# frozen_string_literal: true

FactoryBot.define do
  factory :data_management_deletion_request, class: "DataManagement::DeletionRequest" do
    association :account
    association :user
    status { "pending" }
    deletion_type { "full" }
    reason { Faker::Lorem.sentence }
    data_types_to_delete { DataManagement::DeletionRequest::DELETABLE_DATA_TYPES }
    data_types_to_retain { DataManagement::DeletionRequest::LEGALLY_RETAINED_DATA_TYPES }
    metadata { {} }

    # ============================================
    # Association Traits
    # ============================================
    trait :with_requested_by do
      association :requested_by, factory: :user
    end

    trait :with_processed_by do
      association :processed_by, factory: :user
    end

    # ============================================
    # Status Traits
    # ============================================
    trait :pending do
      status { "pending" }
      approved_at { nil }
      completed_at { nil }
      grace_period_ends_at { nil }
    end

    trait :approved do
      status { "approved" }
      approved_at { Time.current }
      grace_period_ends_at { 30.days.from_now }

      after(:build) do |request|
        request.processed_by ||= create(:user, account: request.account)
      end
    end

    trait :processing do
      status { "processing" }
      approved_at { 1.day.ago }
      grace_period_ends_at { 1.hour.ago }
      processing_started_at { Time.current }

      after(:build) do |request|
        request.processed_by ||= create(:user, account: request.account)
      end
    end

    trait :completed do
      status { "completed" }
      approved_at { 31.days.ago }
      grace_period_ends_at { 1.day.ago }
      processing_started_at { 1.hour.ago }
      completed_at { Time.current }
      deletion_log do
        [
          { type: "profile", deleted_at: Time.current.iso8601, records_deleted: 1 },
          { type: "activity", deleted_at: Time.current.iso8601, records_deleted: 50 }
        ]
      end
      retention_log do
        [
          { type: "financial_records", reason: "Legal retention requirement", records_retained: 5 }
        ]
      end

      after(:build) do |request|
        request.processed_by ||= create(:user, account: request.account)
      end
    end

    trait :rejected do
      status { "rejected" }
      completed_at { Time.current }
      rejection_reason { "Request cannot be fulfilled due to ongoing legal proceedings" }

      after(:build) do |request|
        request.processed_by ||= create(:user, account: request.account)
      end
    end

    trait :cancelled do
      status { "cancelled" }
      completed_at { Time.current }

      after(:build) do |request|
        request.processed_by ||= create(:user, account: request.account)
      end
    end

    # ============================================
    # Deletion Type Traits
    # ============================================
    trait :full_deletion do
      deletion_type { "full" }
      data_types_to_delete { DataManagement::DeletionRequest::DELETABLE_DATA_TYPES }
    end

    trait :partial_deletion do
      deletion_type { "partial" }
      data_types_to_delete { %w[profile activity audit_logs] }
    end

    trait :anonymize do
      deletion_type { "anonymize" }
      data_types_to_delete { %w[profile activity] }
    end

    # ============================================
    # Grace Period Traits
    # ============================================
    trait :in_grace_period do
      status { "approved" }
      approved_at { 15.days.ago }
      grace_period_ends_at { 15.days.from_now }

      after(:build) do |request|
        request.processed_by ||= create(:user, account: request.account)
      end
    end

    trait :grace_period_expired do
      status { "approved" }
      approved_at { 31.days.ago }
      grace_period_ends_at { 1.day.ago }

      after(:build) do |request|
        request.processed_by ||= create(:user, account: request.account)
      end
    end

    trait :grace_period_extended do
      status { "approved" }
      approved_at { 40.days.ago }
      grace_period_ends_at { 4.days.from_now }
      grace_period_extended { true }

      after(:build) do |request|
        request.processed_by ||= create(:user, account: request.account)
      end
    end

    # ============================================
    # Error Traits
    # ============================================
    trait :with_error do
      error_message { "Failed to delete data: database connection error" }
    end

    # ============================================
    # Ready for Processing Trait
    # ============================================
    trait :ready_for_processing do
      status { "approved" }
      approved_at { 31.days.ago }
      grace_period_ends_at { 1.day.ago }

      after(:build) do |request|
        request.processed_by ||= create(:user, account: request.account)
      end
    end
  end
end
