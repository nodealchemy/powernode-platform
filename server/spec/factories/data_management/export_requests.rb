# frozen_string_literal: true

FactoryBot.define do
  factory :data_management_export_request, class: "DataManagement::ExportRequest" do
    association :account
    association :user
    status { "pending" }
    format { "json" }
    export_type { "full" }
    include_data_types { DataManagement::ExportRequest::EXPORTABLE_DATA_TYPES }
    exclude_data_types { [] }
    metadata { {} }

    # ============================================
    # Association Traits
    # ============================================
    trait :with_requested_by do
      association :requested_by, factory: :user
    end

    # ============================================
    # Status Traits
    # ============================================
    trait :pending do
      status { "pending" }
      processing_started_at { nil }
      completed_at { nil }
      file_path { nil }
    end

    trait :processing do
      status { "processing" }
      processing_started_at { Time.current }
      completed_at { nil }
      file_path { nil }
    end

    trait :completed do
      status { "completed" }
      processing_started_at { 30.minutes.ago }
      completed_at { Time.current }
      file_path { "/tmp/exports/export_#{SecureRandom.hex(8)}.json" }
      file_size_bytes { rand(1_000..10_000_000) }
      download_token { SecureRandom.urlsafe_base64(32) }
      download_token_expires_at { 7.days.from_now }
      expires_at { 30.days.from_now }
    end

    trait :failed do
      status { "failed" }
      processing_started_at { 30.minutes.ago }
      completed_at { Time.current }
      error_message { "Export failed: unable to generate file" }
    end

    trait :expired do
      status { "expired" }
      processing_started_at { 32.days.ago }
      completed_at { 31.days.ago }
      expires_at { 1.day.ago }
    end

    # ============================================
    # Format Traits
    # ============================================
    trait :json_format do
      format { "json" }
    end

    trait :csv_format do
      format { "csv" }
    end

    trait :zip_format do
      format { "zip" }
    end

    # ============================================
    # Export Type Traits
    # ============================================
    trait :full_export do
      export_type { "full" }
      include_data_types { DataManagement::ExportRequest::EXPORTABLE_DATA_TYPES }
    end

    trait :partial_export do
      export_type { "partial" }
      include_data_types { %w[profile activity settings] }
    end

    # ============================================
    # Download Traits
    # ============================================
    trait :downloadable do
      status { "completed" }
      processing_started_at { 30.minutes.ago }
      completed_at { Time.current }
      file_path { "/tmp/exports/export_#{SecureRandom.hex(8)}.json" }
      file_size_bytes { rand(1_000..10_000_000) }
      download_token { SecureRandom.urlsafe_base64(32) }
      download_token_expires_at { 7.days.from_now }
      expires_at { 30.days.from_now }
    end

    trait :download_expired do
      status { "completed" }
      processing_started_at { 10.days.ago }
      completed_at { 9.days.ago }
      file_path { "/tmp/exports/export_#{SecureRandom.hex(8)}.json" }
      file_size_bytes { rand(1_000..10_000_000) }
      download_token { SecureRandom.urlsafe_base64(32) }
      download_token_expires_at { 2.days.ago }
      expires_at { 21.days.from_now }
    end

    trait :downloaded do
      status { "completed" }
      processing_started_at { 1.day.ago }
      completed_at { 23.hours.ago }
      downloaded_at { 1.hour.ago }
      file_path { "/tmp/exports/export_#{SecureRandom.hex(8)}.json" }
      file_size_bytes { rand(1_000..10_000_000) }
      download_token { SecureRandom.urlsafe_base64(32) }
      download_token_expires_at { 6.days.from_now }
      expires_at { 29.days.from_now }
    end

    # ============================================
    # Size Traits
    # ============================================
    trait :small_export do
      file_size_bytes { rand(1_000..100_000) }
    end

    trait :large_export do
      file_size_bytes { rand(50_000_000..500_000_000) }
    end
  end
end
