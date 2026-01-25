# frozen_string_literal: true

FactoryBot.define do
  factory :ai_compliance_report, class: "Ai::ComplianceReport" do
    account
    association :generated_by, factory: :user
    report_id { SecureRandom.uuid }
    report_type { "audit_summary" }
    status { "generating" }
    format { "pdf" }
    report_config { {} }
    summary_data { {} }
    period_start { 30.days.ago }
    period_end { Time.current }

    trait :generating do
      status { "generating" }
    end

    trait :completed do
      status { "completed" }
      generated_at { Time.current }
      file_path { "/reports/compliance/#{SecureRandom.uuid}.pdf" }
      file_size_bytes { rand(10_000..1_000_000) }
      expires_at { 30.days.from_now }
      summary_data do
        {
          total_policies: rand(5..20),
          violations_found: rand(0..10),
          compliance_score: rand(70..100)
        }
      end
    end

    trait :failed do
      status { "failed" }
      summary_data { { error: "Report generation failed" } }
    end

    trait :expired do
      status { "expired" }
      expires_at { 1.day.ago }
    end

    trait :soc2 do
      report_type { "soc2" }
    end

    trait :hipaa do
      report_type { "hipaa" }
    end

    trait :gdpr do
      report_type { "gdpr" }
    end

    trait :pci_dss do
      report_type { "pci_dss" }
    end

    trait :iso27001 do
      report_type { "iso27001" }
    end

    trait :violation_summary do
      report_type { "violation_summary" }
    end

    trait :data_inventory do
      report_type { "data_inventory" }
    end

    trait :pdf do
      format { "pdf" }
    end

    trait :html do
      format { "html" }
    end

    trait :json do
      format { "json" }
    end

    trait :csv do
      format { "csv" }
    end
  end
end
