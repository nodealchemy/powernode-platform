# frozen_string_literal: true

puts "  Seeding AI mission templates..."

templates = [
  {
    name: "Standard Development",
    description: "Full development lifecycle with code analysis, PRD generation, implementation, testing, code review, and deployment preview.",
    template_type: "system",
    mission_type: "development",
    is_default: true,
    phases: [
      { "key" => "analyzing", "label" => "Analysis", "description" => "Analyze repository and generate feature suggestions", "order" => 0, "requires_approval" => false, "job_class" => "AiMissionAnalyzeJob" },
      { "key" => "awaiting_feature_approval", "label" => "Feature Approval", "description" => "Review and approve suggested features", "order" => 1, "requires_approval" => true, "gate_name" => "feature_selection" },
      { "key" => "planning", "label" => "Planning", "description" => "Generate PRD and implementation plan", "order" => 2, "requires_approval" => false, "job_class" => "AiMissionPlanJob" },
      { "key" => "awaiting_prd_approval", "label" => "PRD Approval", "description" => "Review and approve the PRD", "order" => 3, "requires_approval" => true, "gate_name" => "prd_review" },
      { "key" => "executing", "label" => "Execution", "description" => "Implement the feature", "order" => 4, "requires_approval" => false, "job_class" => "AiMissionExecuteJob" },
      { "key" => "testing", "label" => "Testing", "description" => "Run automated tests", "order" => 5, "requires_approval" => false, "job_class" => "AiMissionTestJob" },
      { "key" => "reviewing", "label" => "Review", "description" => "Automated code review", "order" => 6, "requires_approval" => false, "job_class" => "AiMissionReviewJob" },
      { "key" => "awaiting_code_approval", "label" => "Code Approval", "description" => "Review and approve the code changes", "order" => 7, "requires_approval" => true, "gate_name" => "code_review" },
      { "key" => "deploying", "label" => "Deployment", "description" => "Deploy preview environment", "order" => 8, "requires_approval" => false, "job_class" => "AiMissionDeployJob" },
      { "key" => "previewing", "label" => "Preview", "description" => "Review deployed preview and approve merge", "order" => 9, "requires_approval" => true, "gate_name" => "merge_approval" },
      { "key" => "merging", "label" => "Merge", "description" => "Merge branch and clean up", "order" => 10, "requires_approval" => false, "job_class" => "AiMissionMergeJob" },
      { "key" => "completed", "label" => "Completed", "description" => "Mission complete", "order" => 11 }
    ],
    approval_gates: %w[awaiting_feature_approval awaiting_prd_approval awaiting_code_approval previewing],
    rejection_mappings: {
      "awaiting_feature_approval" => "analyzing",
      "awaiting_prd_approval" => "planning",
      "awaiting_code_approval" => "executing",
      "previewing" => "deploying"
    }
  },
  {
    name: "Standard Research",
    description: "Research workflow with information gathering, analysis, and report generation.",
    template_type: "system",
    mission_type: "research",
    is_default: true,
    phases: [
      { "key" => "researching", "label" => "Research", "description" => "Gather information and data", "order" => 0, "requires_approval" => false },
      { "key" => "analyzing", "label" => "Analysis", "description" => "Analyze gathered information", "order" => 1, "requires_approval" => false },
      { "key" => "reporting", "label" => "Reporting", "description" => "Generate final report", "order" => 2, "requires_approval" => false },
      { "key" => "completed", "label" => "Completed", "description" => "Research complete", "order" => 3 }
    ],
    approval_gates: [],
    rejection_mappings: {}
  },
  {
    name: "Standard Operations",
    description: "Operations workflow for system configuration, execution, and verification.",
    template_type: "system",
    mission_type: "operations",
    is_default: true,
    phases: [
      { "key" => "configuring", "label" => "Configuration", "description" => "Configure operation parameters", "order" => 0, "requires_approval" => false },
      { "key" => "executing", "label" => "Execution", "description" => "Execute the operation", "order" => 1, "requires_approval" => false },
      { "key" => "verifying", "label" => "Verification", "description" => "Verify operation success", "order" => 2, "requires_approval" => false },
      { "key" => "completed", "label" => "Completed", "description" => "Operation complete", "order" => 3 }
    ],
    approval_gates: [],
    rejection_mappings: {}
  }
]

templates.each do |attrs|
  template = Ai::MissionTemplate.find_or_initialize_by(
    name: attrs[:name],
    template_type: attrs[:template_type]
  )
  template.assign_attributes(attrs)
  template.save!
  puts "    #{attrs[:template_type]}/#{attrs[:name]} (#{attrs[:mission_type]}, #{attrs[:phases].length} phases)"
end

puts "  Created #{Ai::MissionTemplate.count} mission templates"
