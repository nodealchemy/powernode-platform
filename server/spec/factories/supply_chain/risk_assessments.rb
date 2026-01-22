# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_risk_assessment, class: "SupplyChain::RiskAssessment" do
    association :vendor, factory: :supply_chain_vendor
    association :account

    assessment_type { "initial" }
    status { "draft" }
    assessment_date { nil }
    completed_at { nil }
    valid_until { nil }
    security_score { 75.0 }
    compliance_score { 80.0 }
    operational_score { 70.0 }
    overall_score { ((security_score * 0.4) + (compliance_score * 0.35) + (operational_score * 0.25)).round(2) }
    findings { [] }
    recommendations { [] }
    evidence { [] }
    metadata { {} }

    # ============================================
    # Assessment Type Traits
    # ============================================
    trait :initial do
      assessment_type { "initial" }
    end

    trait :periodic do
      assessment_type { "periodic" }
    end

    trait :incident do
      assessment_type { "incident" }
    end

    trait :renewal do
      assessment_type { "renewal" }
    end

    # ============================================
    # Status Traits
    # ============================================
    trait :draft do
      status { "draft" }
      assessment_date { nil }
      completed_at { nil }
    end

    trait :in_progress do
      status { "in_progress" }
      assessment_date { Time.current }
    end

    trait :pending_review do
      status { "pending_review" }
      assessment_date { 3.days.ago }
    end

    trait :completed do
      status { "completed" }
      assessment_date { 7.days.ago }
      completed_at { Time.current }
      valid_until { 12.months.from_now }
    end

    trait :expired do
      status { "expired" }
      assessment_date { 13.months.ago }
      completed_at { 13.months.ago }
      valid_until { 1.month.ago }
    end

    # ============================================
    # Score-based Risk Level Traits
    # ============================================
    trait :low_risk do
      security_score { rand(85..100).to_f }
      compliance_score { rand(85..100).to_f }
      operational_score { rand(85..100).to_f }
      overall_score { ((security_score * 0.4) + (compliance_score * 0.35) + (operational_score * 0.25)).round(2) }
    end

    trait :medium_risk do
      security_score { rand(50..70).to_f }
      compliance_score { rand(50..70).to_f }
      operational_score { rand(50..70).to_f }
      overall_score { ((security_score * 0.4) + (compliance_score * 0.35) + (operational_score * 0.25)).round(2) }
    end

    trait :high_risk do
      security_score { rand(30..59).to_f }
      compliance_score { rand(30..59).to_f }
      operational_score { rand(30..59).to_f }
      overall_score { ((security_score * 0.4) + (compliance_score * 0.35) + (operational_score * 0.25)).round(2) }
    end

    trait :critical_risk do
      security_score { rand(0..29).to_f }
      compliance_score { rand(0..29).to_f }
      operational_score { rand(0..29).to_f }
      overall_score { ((security_score * 0.4) + (compliance_score * 0.35) + (operational_score * 0.25)).round(2) }
    end

    # ============================================
    # Findings Traits
    # ============================================
    trait :with_findings do
      findings do
        [
          {
            id: SecureRandom.uuid,
            title: "Insufficient access controls",
            severity: "high",
            description: "Access control mechanisms do not meet security requirements",
            category: "security",
            remediation: "Implement role-based access control",
            status: "open",
            created_at: Time.current.iso8601
          },
          {
            id: SecureRandom.uuid,
            title: "Missing encryption at rest",
            severity: "medium",
            description: "Data at rest is not encrypted",
            category: "security",
            remediation: "Enable encryption for all data stores",
            status: "open",
            created_at: Time.current.iso8601
          }
        ]
      end
    end

    trait :with_critical_findings do
      findings do
        [
          {
            id: SecureRandom.uuid,
            title: "Critical security vulnerability",
            severity: "critical",
            description: "Unpatched critical CVE affecting core systems",
            category: "security",
            remediation: "Apply emergency patch immediately",
            status: "open",
            created_at: Time.current.iso8601
          }
        ]
      end
    end

    trait :with_resolved_findings do
      findings do
        [
          {
            id: SecureRandom.uuid,
            title: "Outdated TLS version",
            severity: "medium",
            description: "TLS 1.0 is still enabled",
            category: "security",
            remediation: "Disable TLS 1.0 and 1.1",
            status: "resolved",
            resolution: "TLS 1.0 and 1.1 disabled, TLS 1.2+ enforced",
            resolved_at: 1.week.ago.iso8601,
            created_at: 2.weeks.ago.iso8601
          }
        ]
      end
    end

    # ============================================
    # Recommendations Traits
    # ============================================
    trait :with_recommendations do
      recommendations do
        [
          {
            id: SecureRandom.uuid,
            title: "Implement MFA",
            priority: "high",
            description: "Multi-factor authentication should be enabled for all users",
            due_date: 30.days.from_now.iso8601,
            status: "pending",
            created_at: Time.current.iso8601
          },
          {
            id: SecureRandom.uuid,
            title: "Regular security training",
            priority: "medium",
            description: "Conduct quarterly security awareness training",
            due_date: 90.days.from_now.iso8601,
            status: "pending",
            created_at: Time.current.iso8601
          }
        ]
      end
    end

    # ============================================
    # Evidence Traits
    # ============================================
    trait :with_evidence do
      evidence do
        [
          {
            id: SecureRandom.uuid,
            name: "SOC 2 Type II Report",
            type: "certification",
            url: "https://example.com/docs/soc2-report.pdf",
            notes: "Valid until December 2025",
            added_at: Time.current.iso8601
          },
          {
            id: SecureRandom.uuid,
            name: "Penetration Test Results",
            type: "assessment",
            url: "https://example.com/docs/pentest-2024.pdf",
            notes: "Annual penetration test conducted by third party",
            added_at: Time.current.iso8601
          }
        ]
      end
    end

    # ============================================
    # Validity Traits
    # ============================================
    trait :valid do
      completed
      valid_until { 6.months.from_now }
    end

    trait :expiring_soon do
      completed
      valid_until { 15.days.from_now }
    end

    trait :recently_expired do
      status { "expired" }
      completed_at { 13.months.ago }
      valid_until { 1.week.ago }
    end

    # ============================================
    # Association Traits
    # ============================================
    trait :with_assessor do
      association :assessor, factory: :user
    end

    trait :with_questionnaire_responses do
      after(:create) do |assessment|
        create_list(:supply_chain_questionnaire_response, 2, :submitted,
                    vendor: assessment.vendor,
                    account: assessment.account,
                    risk_assessment: assessment)
      end
    end

    # ============================================
    # Compound Traits
    # ============================================
    trait :complete_assessment do
      completed
      with_assessor
      with_findings
      with_recommendations
      with_evidence
      low_risk
    end

    trait :needs_attention do
      pending_review
      high_risk
      with_critical_findings
      with_assessor
    end

    trait :overdue_review do
      completed
      valid_until { 1.day.ago }
      high_risk
      with_findings
    end
  end
end
