# frozen_string_literal: true

FactoryBot.define do
  factory :ai_data_classification, class: "Ai::DataClassification" do
    account
    association :classified_by, factory: :user
    sequence(:name) { |n| "Data Classification #{n}" }
    description { Faker::Lorem.paragraph }
    classification_level { "internal" }
    is_system { false }
    requires_encryption { false }
    requires_masking { false }
    requires_audit { true }
    detection_count { 0 }
    detection_patterns { [] }
    handling_requirements { {} }
    retention_policy { {} }

    trait :public do
      classification_level { "public" }
      requires_encryption { false }
      requires_masking { false }
      requires_audit { false }
    end

    trait :internal do
      classification_level { "internal" }
      requires_encryption { false }
      requires_masking { false }
      requires_audit { true }
    end

    trait :confidential do
      classification_level { "confidential" }
      requires_encryption { true }
      requires_masking { false }
      requires_audit { true }
    end

    trait :restricted do
      classification_level { "restricted" }
      requires_encryption { true }
      requires_masking { true }
      requires_audit { true }
    end

    trait :pii do
      name { "Personally Identifiable Information" }
      classification_level { "pii" }
      requires_encryption { true }
      requires_masking { true }
      requires_audit { true }
      detection_patterns do
        [
          { "name" => "Email", "pattern" => "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}" },
          { "name" => "SSN", "pattern" => "\\d{3}-\\d{2}-\\d{4}" },
          { "name" => "Phone", "pattern" => "\\(?\\d{3}\\)?[-.\\s]?\\d{3}[-.\\s]?\\d{4}" }
        ]
      end
      retention_policy do
        {
          "days" => 365,
          "action" => "anonymize"
        }
      end
    end

    trait :phi do
      name { "Protected Health Information" }
      classification_level { "phi" }
      requires_encryption { true }
      requires_masking { true }
      requires_audit { true }
      handling_requirements do
        {
          "hipaa_compliant" => true,
          "access_logging" => true,
          "encryption_at_rest" => true
        }
      end
      retention_policy do
        {
          "days" => 2190,
          "action" => "archive"
        }
      end
    end

    trait :pci do
      name { "Payment Card Information" }
      classification_level { "pci" }
      requires_encryption { true }
      requires_masking { true }
      requires_audit { true }
      detection_patterns do
        [
          { "name" => "Credit Card", "pattern" => "\\d{4}[- ]?\\d{4}[- ]?\\d{4}[- ]?\\d{4}" },
          { "name" => "CVV", "pattern" => "\\b\\d{3,4}\\b" }
        ]
      end
      handling_requirements do
        {
          "pci_compliant" => true,
          "tokenization_required" => true,
          "never_store_cvv" => true
        }
      end
    end

    trait :system do
      is_system { true }
    end

    trait :with_detections do
      after(:create) do |classification|
        # This would require ai_data_detection factory if needed
        classification.update!(detection_count: 5)
      end
    end

    trait :with_retention do
      retention_policy do
        {
          "days" => 90,
          "action" => "delete"
        }
      end
    end
  end
end
