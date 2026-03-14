# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_vendor, class: "SupplyChain::Vendor" do
    association :account
    sequence(:name) { |n| "Test Vendor #{n} #{SecureRandom.hex(4)}" }
    sequence(:slug) { |n| "vendor-#{n}-#{SecureRandom.hex(4)}" }
    vendor_type { "saas" }
    risk_tier { "medium" }
    risk_score { 50 }
    status { "active" }
    description { Faker::Company.catch_phrase }
    website { Faker::Internet.url }
    contact_email { Faker::Internet.email }
    handles_pii { false }
    handles_phi { false }
    handles_pci { false }
    has_baa { false }
    has_dpa { false }
    certifications { [] }
    security_contacts { [] }
    metadata { {} }

    # ============================================
    # Vendor Type Traits
    # ============================================
    trait :saas do
      vendor_type { "saas" }
      description { "Software as a Service provider" }
    end

    trait :api do
      vendor_type { "api" }
      description { "API service provider" }
    end

    trait :library do
      vendor_type { "library" }
      description { "Open source library vendor" }
    end

    trait :infrastructure do
      vendor_type { "infrastructure" }
      description { "Infrastructure provider" }
    end

    trait :hardware do
      vendor_type { "hardware" }
      description { "Hardware vendor" }
    end

    trait :consulting do
      vendor_type { "consulting" }
      description { "Consulting services vendor" }
    end

    trait :other do
      vendor_type { "other" }
    end

    # ============================================
    # Risk Tier Traits
    # ============================================
    trait :critical_risk do
      risk_tier { "critical" }
      risk_score { rand(80..100) }
      handles_phi { true }
      handles_pii { true }
      has_baa { true }
    end

    trait :high_risk do
      risk_tier { "high" }
      risk_score { rand(60..79) }
      handles_pii { true }
    end

    trait :medium_risk do
      risk_tier { "medium" }
      risk_score { rand(30..59) }
    end

    trait :low_risk do
      risk_tier { "low" }
      risk_score { rand(0..29) }
      handles_pii { false }
      handles_phi { false }
      handles_pci { false }
    end

    # ============================================
    # Status Traits
    # ============================================
    trait :active do
      status { "active" }
    end

    trait :inactive do
      status { "inactive" }
    end

    trait :under_review do
      status { "under_review" }
    end

    trait :terminated do
      status { "terminated" }
    end

    # ============================================
    # Data Handling Traits
    # ============================================
    trait :handles_pii do
      handles_pii { true }
      has_dpa { true }
    end

    trait :handles_phi do
      handles_phi { true }
      has_baa { true }
    end

    trait :handles_pci do
      handles_pci { true }
    end

    trait :handles_sensitive_data do
      handles_pii { true }
      handles_phi { true }
      handles_pci { true }
      has_baa { true }
      has_dpa { true }
    end

    trait :no_sensitive_data do
      handles_pii { false }
      handles_phi { false }
      handles_pci { false }
    end

    # ============================================
    # Certification Traits
    # ============================================
    trait :soc2_certified do
      certifications do
        [
          {
            "name" => "SOC 2 Type II",
            "expires_at" => 1.year.from_now.iso8601,
            "verified" => true,
            "added_at" => 6.months.ago.iso8601
          }
        ]
      end
    end

    trait :iso27001_certified do
      certifications do
        [
          {
            "name" => "ISO 27001",
            "expires_at" => 2.years.from_now.iso8601,
            "verified" => true,
            "added_at" => 1.year.ago.iso8601
          }
        ]
      end
    end

    trait :hipaa_compliant do
      certifications do
        [
          {
            "name" => "HIPAA Compliant",
            "expires_at" => nil,
            "verified" => true,
            "added_at" => 1.year.ago.iso8601
          }
        ]
      end
      handles_phi { true }
      has_baa { true }
    end

    trait :pci_dss_compliant do
      certifications do
        [
          {
            "name" => "PCI DSS",
            "expires_at" => 1.year.from_now.iso8601,
            "verified" => true,
            "added_at" => 3.months.ago.iso8601
          }
        ]
      end
      handles_pci { true }
    end

    trait :fully_certified do
      certifications do
        [
          {
            "name" => "SOC 2 Type II",
            "expires_at" => 1.year.from_now.iso8601,
            "verified" => true,
            "added_at" => 6.months.ago.iso8601
          },
          {
            "name" => "ISO 27001",
            "expires_at" => 2.years.from_now.iso8601,
            "verified" => true,
            "added_at" => 1.year.ago.iso8601
          },
          {
            "name" => "GDPR Compliant",
            "expires_at" => nil,
            "verified" => true,
            "added_at" => 1.year.ago.iso8601
          }
        ]
      end
    end

    # ============================================
    # Contract Traits
    # ============================================
    trait :with_active_contract do
      contract_start_date { 1.year.ago }
      contract_end_date { 1.year.from_now }
    end

    trait :with_expiring_contract do
      contract_start_date { 11.months.ago }
      contract_end_date { 1.month.from_now }
    end

    trait :with_expired_contract do
      contract_start_date { 2.years.ago }
      contract_end_date { 1.month.ago }
    end

    # ============================================
    # Assessment Traits
    # ============================================
    trait :needs_assessment do
      next_assessment_due { 1.week.ago }
    end

    trait :assessment_current do
      last_assessment_at { 1.month.ago }
      next_assessment_due { 5.months.from_now }
    end

    trait :never_assessed do
      last_assessment_at { nil }
      next_assessment_due { nil }
    end

    # ============================================
    # Security Contact Traits
    # ============================================
    trait :with_security_contacts do
      security_contacts do
        [
          {
            "name" => Faker::Name.name,
            "email" => Faker::Internet.email,
            "phone" => Faker::PhoneNumber.phone_number,
            "role" => "Security Lead"
          },
          {
            "name" => Faker::Name.name,
            "email" => Faker::Internet.email,
            "role" => "Incident Response"
          }
        ]
      end
    end

    # ============================================
    # Association Traits
    # ============================================
    trait :with_created_by do
      association :created_by, factory: :user
    end

    trait :with_assessments do
      transient do
        assessments_count { 2 }
      end

      after(:create) do |vendor, evaluator|
        create_list(:supply_chain_risk_assessment, evaluator.assessments_count,
                    vendor: vendor,
                    account: vendor.account)
      end
    end

    trait :with_monitoring_events do
      transient do
        events_count { 3 }
      end

      after(:create) do |vendor, evaluator|
        create_list(:supply_chain_vendor_monitoring_event, evaluator.events_count,
                    vendor: vendor,
                    account: vendor.account)
      end
    end

    # ============================================
    # Complete Vendor Trait
    # ============================================
    trait :complete do
      active
      with_active_contract
      assessment_current
      soc2_certified
      with_security_contacts
      with_created_by
    end
  end
end
