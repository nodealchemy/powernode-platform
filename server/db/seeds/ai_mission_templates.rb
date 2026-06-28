# frozen_string_literal: true

puts "  Seeding AI mission templates..."

templates = [
  {
    name: "Standard Development",
    description: "Full dev lifecycle: code analysis, PRD, implementation, testing, code review, deployment preview.",
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
  },
  {
    name: "Content Production",
    description: "Multi-modal content generation: brief, script, asset generation, composition, render, and delivery as a shared download link.",
    template_type: "system",
    mission_type: "content_production",
    is_default: true,
    phases: [
      { "key" => "brief", "label" => "Brief", "description" => "Capture the content brief: goal, format, audience, constraints", "order" => 0, "requires_approval" => false },
      { "key" => "script", "label" => "Script", "description" => "Generate the script / shot list / document outline", "order" => 1, "requires_approval" => false },
      { "key" => "asset_generation", "label" => "Asset Generation", "description" => "Generate the individual assets (images, audio, document sections)", "order" => 2, "requires_approval" => false },
      { "key" => "composition", "label" => "Composition", "description" => "Arrange generated assets into the composition (scene order, layout)", "order" => 3, "requires_approval" => false },
      { "key" => "render", "label" => "Render", "description" => "Render the final artifact (stitch scenes into video / build the document)", "order" => 4, "requires_approval" => false },
      { "key" => "deliver", "label" => "Deliver", "description" => "Package the artifact and produce a shared, expiring download link", "order" => 5, "requires_approval" => false },
      { "key" => "completed", "label" => "Completed", "description" => "Production complete", "order" => 6 }
    ],
    approval_gates: [],
    rejection_mappings: {}
  }
]

# GLOBAL baseline content: account_id nil, upserted by source_key so future
# seeds update in place. No account needed (seeds in core/prod too).
return unless Powernode::Seeds.baseline?

templates.each do |attrs|
  source_key = attrs[:name].parameterize
  template = Ai::MissionTemplate.find_or_initialize_by(source_key: source_key, account_id: nil)
  template.assign_attributes(attrs)
  if template.new_record?
    template.version = 1
  elsif template.changed?
    template.version = template.version.to_i + 1
  end
  template.save!
  puts "    #{attrs[:template_type]}/#{attrs[:name]} (#{attrs[:mission_type]}, #{attrs[:phases].length} phases)"
end

puts "  Created #{Ai::MissionTemplate.global.count} global mission templates"
