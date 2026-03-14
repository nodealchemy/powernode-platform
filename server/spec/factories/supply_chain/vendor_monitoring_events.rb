# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_vendor_monitoring_event, class: "SupplyChain::VendorMonitoringEvent" do
    association :vendor, factory: :supply_chain_vendor
    association :account
    event_type { "security_incident" }
    severity { "high" }
    source { "external" }
    title { "Security Event: #{Faker::Hacker.adjective.capitalize} Activity Detected" }
    description { Faker::Lorem.paragraph }
    detected_at { Time.current }
    is_acknowledged { false }
    recommended_actions { [] }
    affected_services { [] }
    metadata { {} }

    trait :security_incident do
      event_type { "security_incident" }
    end

    trait :breach do
      event_type { "breach" }
      title { "Security Breach Detected" }
      severity { "critical" }
    end

    trait :certification_expiry do
      event_type { "certification_expiry" }
      title { "Certification Expiring: ISO27001" }
      severity { "high" }
      source { "automated" }
    end

    trait :contract_renewal do
      event_type { "contract_renewal" }
      title { "Contract Renewal Due" }
      severity { "medium" }
      source { "automated" }
    end

    trait :service_degradation do
      event_type { "service_degradation" }
      title { "Service Degradation Detected" }
      severity { "medium" }
    end

    trait :compliance_update do
      event_type { "compliance_update" }
      title { "Compliance Status Updated" }
      severity { "low" }
    end

    trait :news_alert do
      event_type { "news_alert" }
      title { "News Alert: Vendor in the News" }
      severity { "medium" }
      source { "external" }
    end

    trait :critical do
      severity { "critical" }
    end

    trait :high_severity_event do
      severity { "high" }
    end

    trait :acknowledged do
      is_acknowledged { true }
      acknowledged_at { 2.hours.ago }
      association :acknowledged_by, factory: :user
    end

    trait :resolved do
      resolved_at { 1.day.ago }
    end

    trait :active do
      is_acknowledged { false }
      resolved_at { nil }
    end

    trait :with_actions do
      recommended_actions do
        [
          {
            id: SecureRandom.uuid,
            action: "Review security incident details",
            priority: "high",
            due_date: 2.days.from_now.iso8601,
            status: "pending",
            added_at: Time.current.iso8601
          },
          {
            id: SecureRandom.uuid,
            action: "Implement remediation plan",
            priority: "high",
            due_date: 5.days.from_now.iso8601,
            status: "pending",
            added_at: Time.current.iso8601
          }
        ]
      end
    end

    trait :with_affected_services do
      affected_services { [ "Authentication Service", "Data Processing", "Storage System" ] }
    end

    trait :old do
      detected_at { 30.days.ago }
    end

    trait :recent do
      detected_at { 1.hour.ago }
    end

    trait :internal_source do
      source { "internal" }
    end

    trait :automated_source do
      source { "automated" }
    end
  end
end
