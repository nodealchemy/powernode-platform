# frozen_string_literal: true

FactoryBot.define do
  factory :supply_chain_license_detection, class: "SupplyChain::LicenseDetection" do
    association :account
    association :sbom_component, factory: :supply_chain_sbom_component
    association :license, factory: :supply_chain_license
    detected_license_id { "MIT" }
    detected_license_name { "MIT License" }
    detection_source { %w[manifest file api ai manual].sample }
    confidence_score { rand(0.5..1.0).round(2) }
    is_primary { false }
    requires_review { false }
    file_path { nil }
    ai_interpretation { {} }
    metadata { {} }

    # Detection source traits
    trait :manifest do
      detection_source { "manifest" }
      confidence_score { rand(0.85..0.99).round(2) }
    end

    trait :file do
      detection_source { "file" }
      file_path { "LICENSE" }
      confidence_score { rand(0.80..0.95).round(2) }
    end

    trait :api do
      detection_source { "api" }
      confidence_score { rand(0.90..0.99).round(2) }
    end

    trait :ai do
      detection_source { "ai" }
      confidence_score { rand(0.60..0.85).round(2) }
      ai_interpretation do
        {
          model: "gpt-4",
          analysis_date: Time.current.iso8601,
          reasoning: "License identified based on text analysis",
          alternative_matches: [ "Apache-2.0", "BSD-3-Clause" ]
        }
      end
    end

    trait :manual do
      detection_source { "manual" }
      confidence_score { 1.0 }
    end

    # Primary/Review traits
    trait :primary do
      is_primary { true }
      confidence_score { rand(0.90..1.0).round(2) }
    end

    trait :secondary do
      is_primary { false }
    end

    trait :needs_review do
      requires_review { true }
      confidence_score { rand(0.3..0.7).round(2) }
      metadata do
        {
          review_reason: "Low confidence detection",
          flagged_at: Time.current.iso8601
        }
      end
    end

    trait :reviewed do
      requires_review { false }
      metadata do
        {
          reviewed_at: Time.current.iso8601,
          reviewed_by: "security-team"
        }
      end
    end

    # Confidence traits
    trait :high_confidence do
      confidence_score { rand(0.9..1.0).round(2) }
      requires_review { false }
    end

    trait :medium_confidence do
      confidence_score { rand(0.5..0.89).round(2) }
    end

    trait :low_confidence do
      confidence_score { rand(0.1..0.49).round(2) }
      requires_review { true }
    end

    # License type traits
    trait :mit do
      detected_license_id { "MIT" }
      detected_license_name { "MIT License" }
    end

    trait :apache do
      detected_license_id { "Apache-2.0" }
      detected_license_name { "Apache License 2.0" }
    end

    trait :gpl do
      detected_license_id { "GPL-3.0-only" }
      detected_license_name { "GNU General Public License v3.0" }
    end

    trait :unknown do
      detected_license_id { nil }
      detected_license_name { "Unknown License" }
      requires_review { true }
      confidence_score { 0.0 }
    end

    # File path traits for file-based detections
    trait :from_license_file do
      detection_source { "file" }
      file_path { "LICENSE" }
    end

    trait :from_readme do
      detection_source { "file" }
      file_path { "README.md" }
      confidence_score { rand(0.5..0.7).round(2) }
    end

    trait :from_package_json do
      detection_source { "manifest" }
      file_path { "package.json" }
    end

    trait :from_gemspec do
      detection_source { "manifest" }
      file_path { "*.gemspec" }
    end

    # Metadata traits
    trait :with_metadata do
      metadata do
        {
          detection_time_ms: rand(10..500),
          matched_text: "Permission is hereby granted, free of charge...",
          match_type: "exact"
        }
      end
    end

    trait :with_ai_interpretation do
      ai_interpretation do
        {
          model: "gpt-4",
          analysis_date: Time.current.iso8601,
          reasoning: "License identified based on header text pattern matching",
          confidence_factors: {
            text_match: 0.85,
            structure_match: 0.90,
            keyword_presence: 0.95
          },
          alternative_matches: []
        }
      end
    end
  end
end
