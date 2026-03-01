# frozen_string_literal: true

FactoryBot.define do
  factory :report_request do
    association :account
    association :user, factory: :user, strategy: :create

    report_type { 'revenue_analytics' }
    status { 'pending' }
    parameters { {} }
    requested_at { Time.current }

    # Set the proper foreign key
    after(:build) do |report_request|
      report_request.requested_by_id = report_request.user&.id if report_request.user
    end

    trait :completed do
      status { 'completed' }
      completed_at { Time.current }
      file_path { Rails.root.join('tmp', 'reports', 'test_report.pdf').to_s }
      file_size_bytes { 1024 }
    end

    trait :failed do
      status { 'failed' }
      error_message { 'Report generation failed' }
    end

    trait :processing do
      status { 'processing' }
    end

    trait :cancelled do
      status { 'cancelled' }
    end

    # Report type variations
    trait :revenue_analytics do
      report_type { 'revenue_analytics' }
    end

    trait :customer_analytics do
      report_type { 'customer_analytics' }
    end

    trait :churn_analysis do
      report_type { 'churn_analysis' }
    end

    trait :growth_analytics do
      report_type { 'growth_analytics' }
    end

    trait :cohort_analysis do
      report_type { 'cohort_analysis' }
    end

    trait :comprehensive_report do
      report_type { 'comprehensive_report' }
    end
  end
end
