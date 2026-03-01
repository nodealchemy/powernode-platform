# frozen_string_literal: true

FactoryBot.define do
  factory :ai_deployment_risk, class: "Ai::DeploymentRisk" do
    association :account

    assessment_id { SecureRandom.uuid }
    deployment_type { "application" }
    target_environment { "production" }
    risk_level { "low" }
    status { "pending" }
    requires_approval { false }
    risk_factors { [] }
    change_analysis { {} }
    impact_analysis { {} }
    recommendations { [] }
    mitigations { [] }

    trait :pending do
      status { "pending" }
    end

    trait :assessed do
      status { "assessed" }
      assessed_at { Time.current }
      risk_score { 25 }
      risk_factors do
        [
          { "name" => "code_complexity", "score" => 0.3, "description" => "Low complexity changes" },
          { "name" => "test_coverage", "score" => 0.2, "description" => "Good test coverage" }
        ]
      end
      change_analysis do
        {
          "files_changed" => 5,
          "lines_added" => 120,
          "lines_removed" => 30,
          "breaking_changes" => false
        }
      end
      impact_analysis do
        {
          "affected_services" => [ "api", "worker" ],
          "estimated_users_impacted" => 1000,
          "rollback_time_estimate" => "5 minutes"
        }
      end
      recommendations { [ "Run additional integration tests", "Monitor error rates closely" ] }
      mitigations { [ "Feature flag available", "Automatic rollback configured" ] }
    end

    trait :approved do
      status { "approved" }
      assessed_at { 10.minutes.ago }
      decision { "proceed" }
      decision_at { Time.current }
      association :assessed_by, factory: :user
    end

    trait :rejected do
      status { "rejected" }
      assessed_at { 10.minutes.ago }
      decision { "abort" }
      decision_at { Time.current }
      decision_rationale { "Too many high-severity issues identified" }
      association :assessed_by, factory: :user
    end

    trait :overridden do
      status { "overridden" }
      assessed_at { 15.minutes.ago }
      decision { "proceed_with_caution" }
      decision_at { Time.current }
      decision_rationale { "Business critical release, risks acknowledged" }
      requires_approval { true }
      association :assessed_by, factory: :user
    end

    trait :low_risk do
      risk_level { "low" }
      risk_score { 20 }
      requires_approval { false }
    end

    trait :medium_risk do
      risk_level { "medium" }
      risk_score { 40 }
      requires_approval { false }
    end

    trait :high_risk do
      risk_level { "high" }
      risk_score { 65 }
      requires_approval { true }
      risk_factors do
        [
          { "name" => "code_complexity", "score" => 0.7, "description" => "High complexity changes" },
          { "name" => "test_coverage", "score" => 0.6, "description" => "Test coverage decreased" },
          { "name" => "dependencies_changed", "score" => 0.8, "description" => "Major dependency updates" }
        ]
      end
    end

    trait :critical_risk do
      risk_level { "critical" }
      risk_score { 85 }
      requires_approval { true }
      risk_factors do
        [
          { "name" => "security_vulnerabilities", "score" => 0.9, "description" => "Critical vulnerabilities detected" },
          { "name" => "code_complexity", "score" => 0.8, "description" => "Very high complexity" },
          { "name" => "rollback_capability", "score" => 0.7, "description" => "Limited rollback options" }
        ]
      end
      recommendations do
        [
          "Address security vulnerabilities before deployment",
          "Implement additional monitoring",
          "Prepare manual rollback procedure"
        ]
      end
    end

    trait :production do
      target_environment { "production" }
    end

    trait :staging do
      target_environment { "staging" }
      requires_approval { false }
    end

    trait :development do
      target_environment { "development" }
      requires_approval { false }
      risk_level { "low" }
    end

    trait :database_migration do
      deployment_type { "database_migration" }
      risk_factors do
        [
          { "name" => "data_migration_size", "score" => 0.5, "description" => "Medium data volume" },
          { "name" => "schema_changes", "score" => 0.6, "description" => "Table structure changes" }
        ]
      end
    end

    trait :infrastructure do
      deployment_type { "infrastructure" }
      risk_factors do
        [
          { "name" => "resource_changes", "score" => 0.4, "description" => "Scaling configuration changes" },
          { "name" => "network_changes", "score" => 0.3, "description" => "Minor network adjustments" }
        ]
      end
    end

    trait :with_pipeline_execution do
      association :pipeline_execution, factory: :ai_pipeline_execution
    end

    trait :with_summary do
      summary { "Deployment risk assessment completed. Overall risk level is acceptable with recommended mitigations in place." }
    end
  end
end
