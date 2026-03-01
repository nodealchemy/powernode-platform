# frozen_string_literal: true

FactoryBot.define do
  factory :ai_code_factory_risk_contract, class: "Ai::CodeFactory::RiskContract" do
    account
    sequence(:name) { |n| "Risk Contract #{n}" }
    status { "draft" }
    version { 1 }
    risk_tiers do
      [
        {
          "tier" => "low",
          "patterns" => ["docs/**", "*.md"],
          "required_checks" => ["lint"],
          "evidence_required" => false,
          "min_reviewers" => 0
        },
        {
          "tier" => "standard",
          "patterns" => ["app/**", "lib/**"],
          "required_checks" => ["lint", "tests"],
          "evidence_required" => false,
          "min_reviewers" => 1
        },
        {
          "tier" => "high",
          "patterns" => ["app/models/**", "db/migrate/**"],
          "required_checks" => ["lint", "tests", "security_scan"],
          "evidence_required" => true,
          "min_reviewers" => 2
        },
        {
          "tier" => "critical",
          "patterns" => ["config/credentials/**", "app/services/payments/**"],
          "required_checks" => ["lint", "tests", "security_scan", "manual_review"],
          "evidence_required" => true,
          "min_reviewers" => 3
        }
      ]
    end

    trait :active do
      status { "active" }
      activated_at { Time.current }
    end

    trait :archived do
      status { "archived" }
    end

    trait :with_repository do
      association :repository, factory: :devops_git_repository
    end
  end

  factory :ai_code_factory_review_state, class: "Ai::CodeFactory::ReviewState" do
    account
    association :risk_contract, factory: :ai_code_factory_risk_contract
    pr_number { rand(1..999) }
    head_sha { SecureRandom.hex(20) }
    status { "pending" }

    trait :reviewing do
      status { "reviewing" }
    end

    trait :clean do
      status { "clean" }
      all_checks_passed { true }
      reviewed_at { Time.current }
    end

    trait :dirty do
      status { "dirty" }
      all_checks_passed { false }
      review_findings_count { 3 }
      critical_findings_count { 1 }
      reviewed_at { Time.current }
    end

    trait :stale do
      status { "stale" }
      stale_reason { "New push detected" }
    end

    trait :with_repository do
      association :repository, factory: :devops_git_repository
    end
  end

  factory :ai_code_factory_evidence_manifest, class: "Ai::CodeFactory::EvidenceManifest" do
    account
    association :review_state, factory: :ai_code_factory_review_state
    manifest_type { "browser_test" }
    status { "pending" }

    trait :captured do
      status { "captured" }
      captured_at { Time.current }
      artifacts do
        [{ "type" => "screenshot", "url" => "https://example.com/screenshot.png", "sha256" => SecureRandom.hex(32), "size_bytes" => 1024 }]
      end
      assertions do
        [{ "type" => "element_exists", "selector" => "#main", "expected" => true, "actual" => true, "passed" => true }]
      end
    end

    trait :verified do
      status { "verified" }
      captured_at { 1.hour.ago }
      verified_at { Time.current }
      verification_result { { "passed" => true, "checks" => 3, "failures" => 0 } }
    end

    trait :failed do
      status { "failed" }
      captured_at { 1.hour.ago }
      verified_at { Time.current }
      verification_result { { "passed" => false, "checks" => 3, "failures" => 1 } }
    end
  end

  factory :ai_code_factory_harness_gap, class: "Ai::CodeFactory::HarnessGap" do
    account
    incident_source { "review_finding" }
    sequence(:incident_id) { |n| "INC-#{n}" }
    description { "Missing test coverage for authentication edge case" }
    status { "open" }
    severity { "medium" }

    trait :with_sla do
      sla_deadline { 72.hours.from_now }
    end

    trait :past_sla do
      sla_deadline { 24.hours.ago }
    end

    trait :with_test_case do
      status { "case_added" }
      test_case_added { true }
      test_case_reference { "spec/models/user_spec.rb:42" }
    end

    trait :closed do
      status { "closed" }
      resolved_at { Time.current }
      resolution_notes { "Test case added and verified" }
    end

    trait :critical do
      severity { "critical" }
    end
  end
end
