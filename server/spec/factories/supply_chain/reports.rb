# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_report, class: "SupplyChain::Report" do
    association :account
    association :created_by, factory: :user
    name { "#{Faker::Hacker.adjective.capitalize} Report" }
    report_type { "sbom_export" }
    format { "pdf" }
    status { "pending" }
    description { Faker::Lorem.sentence }
    parameters { {} }
    summary { {} }
    metadata { {} }

    trait :pending do
      status { "pending" }
    end

    trait :generating do
      status { "generating" }
    end

    trait :completed do
      status { "completed" }
      generated_at { Time.current }
      file_path { "/tmp/reports/report_#{SecureRandom.hex(8)}.pdf" }
      file_url { "https://example.com/reports/report.pdf" }
      file_size_bytes { rand(1024..10_485_760) }
      expires_at { 30.days.from_now }
    end

    trait :failed do
      status { "failed" }
      metadata { { "error" => "Generation failed" } }
    end

    trait :expired do
      status { "expired" }
      expires_at { 1.day.ago }
    end

    trait :with_sbom do
      association :sbom, factory: :supply_chain_sbom
    end

    trait :sbom_export do
      report_type { "sbom_export" }
      format { "cyclonedx" }
    end

    trait :vulnerability_report do
      report_type { "vulnerability_report" }
      format { "pdf" }
    end

    trait :license_report do
      report_type { "license_report" }
      format { "pdf" }
    end

    trait :attribution do
      report_type { "attribution" }
      format { "html" }
    end

    trait :compliance_summary do
      report_type { "compliance_summary" }
      format { "pdf" }
    end

    trait :vendor_assessment do
      report_type { "vendor_assessment" }
      format { "pdf" }
    end

    trait :custom do
      report_type { "custom" }
    end

    trait :json_format do
      format { "json" }
    end

    trait :csv_format do
      format { "csv" }
    end

    trait :html_format do
      format { "html" }
    end

    trait :xml_format do
      format { "xml" }
    end

    trait :spdx_format do
      format { "spdx" }
    end

    trait :cyclonedx_format do
      format { "cyclonedx" }
    end

    trait :expiring_soon do
      status { "completed" }
      expires_at { 3.days.from_now }
    end

    trait :downloadable do
      status { "completed" }
      file_path { "/tmp/reports/report_#{SecureRandom.hex(8)}.pdf" }
      file_url { "https://example.com/reports/report.pdf" }
      expires_at { 30.days.from_now }
    end

    trait :with_parameters do
      parameters do
        {
          "include_vulnerabilities" => true,
          "include_licenses" => true,
          "min_severity" => "medium"
        }
      end
    end

    trait :with_summary do
      summary do
        {
          "total_components" => rand(50..500),
          "total_vulnerabilities" => rand(0..50),
          "critical_count" => rand(0..5),
          "high_count" => rand(0..15)
        }
      end
    end
  end
end
