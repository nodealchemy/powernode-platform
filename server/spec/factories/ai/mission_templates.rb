# frozen_string_literal: true

FactoryBot.define do
  factory :ai_mission_template, class: "Ai::MissionTemplate" do
    sequence(:name) { |n| "Template #{n}" }
    template_type { "system" }
    mission_type { "development" }
    status { "active" }
    is_default { true }
    version { 1 }

    phases do
      [
        { "key" => "analyzing", "label" => "Analysis", "order" => 0, "requires_approval" => false, "job_class" => "AiMissionAnalyzeJob" },
        { "key" => "awaiting_feature_approval", "label" => "Feature Approval", "order" => 1, "requires_approval" => true, "gate_name" => "feature_selection" },
        { "key" => "planning", "label" => "Planning", "order" => 2, "requires_approval" => false, "job_class" => "AiMissionPlanJob" },
        { "key" => "awaiting_prd_approval", "label" => "PRD Approval", "order" => 3, "requires_approval" => true, "gate_name" => "prd_review" },
        { "key" => "executing", "label" => "Execution", "order" => 4, "requires_approval" => false, "job_class" => "AiMissionExecuteJob" },
        { "key" => "testing", "label" => "Testing", "order" => 5, "requires_approval" => false, "job_class" => "AiMissionTestJob" },
        { "key" => "reviewing", "label" => "Review", "order" => 6, "requires_approval" => false, "job_class" => "AiMissionReviewJob" },
        { "key" => "awaiting_code_approval", "label" => "Code Approval", "order" => 7, "requires_approval" => true, "gate_name" => "code_review" },
        { "key" => "deploying", "label" => "Deployment", "order" => 8, "requires_approval" => false, "job_class" => "AiMissionDeployJob" },
        { "key" => "previewing", "label" => "Preview", "order" => 9, "requires_approval" => true, "gate_name" => "merge_approval" },
        { "key" => "merging", "label" => "Merge", "order" => 10, "requires_approval" => false, "job_class" => "AiMissionMergeJob" },
        { "key" => "completed", "label" => "Completed", "order" => 11 }
      ]
    end

    approval_gates { %w[awaiting_feature_approval awaiting_prd_approval awaiting_code_approval previewing] }

    rejection_mappings do
      {
        "awaiting_feature_approval" => "analyzing",
        "awaiting_prd_approval" => "planning",
        "awaiting_code_approval" => "executing",
        "previewing" => "deploying"
      }
    end

    trait :research do
      mission_type { "research" }
      phases do
        [
          { "key" => "researching", "label" => "Research", "order" => 0, "requires_approval" => false },
          { "key" => "analyzing", "label" => "Analysis", "order" => 1, "requires_approval" => false },
          { "key" => "reporting", "label" => "Reporting", "order" => 2, "requires_approval" => false },
          { "key" => "completed", "label" => "Completed", "order" => 3 }
        ]
      end
      approval_gates { [] }
      rejection_mappings { {} }
    end

    trait :operations do
      mission_type { "operations" }
      phases do
        [
          { "key" => "configuring", "label" => "Configuration", "order" => 0, "requires_approval" => false },
          { "key" => "executing", "label" => "Execution", "order" => 1, "requires_approval" => false },
          { "key" => "verifying", "label" => "Verification", "order" => 2, "requires_approval" => false },
          { "key" => "completed", "label" => "Completed", "order" => 3 }
        ]
      end
      approval_gates { [] }
      rejection_mappings { {} }
    end

    trait :account_template do
      template_type { "account" }
      account
      is_default { false }
    end
  end
end
