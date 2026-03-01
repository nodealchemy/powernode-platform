# frozen_string_literal: true

# Seed file for 6 system role profiles

Rails.logger.info "[Seeds] Creating system role profiles..."

profiles = [
  {
    name: "Lead",
    slug: "system-lead",
    role_type: "lead",
    is_system: true,
    description: "Coordinating lead that directs team execution, delegates tasks, and synthesizes results.",
    system_prompt_template: "You are the team lead for {{team_name}}. Your role is to coordinate the team, delegate tasks to workers, and synthesize their outputs into a cohesive result. Be directive and concise in your communications. Ensure all subtasks are addressed and no work is orphaned.",
    communication_style: {
      "verbosity" => "concise",
      "formality" => "directive",
      "tone" => "authoritative"
    },
    quality_checks: [
      { "check" => "all_subtasks_addressed", "severity" => "error" },
      { "check" => "no_orphaned_work", "severity" => "error" },
      { "check" => "clear_delegation", "severity" => "warning" }
    ],
    delegation_rules: {
      "can_delegate" => true,
      "max_delegation_depth" => 2,
      "require_acceptance" => false
    },
    escalation_rules: {
      "escalate_on_failure" => true,
      "escalate_on_timeout" => true,
      "max_retries_before_escalation" => 2
    }
  },
  {
    name: "Worker",
    slug: "system-worker",
    role_type: "worker",
    is_system: true,
    description: "Implementation-focused worker that executes assigned tasks with detailed status reports.",
    system_prompt_template: "You are a worker on team {{team_name}}. Your role is to execute the assigned task thoroughly and provide detailed status reports. Focus on implementation quality. If you encounter blockers, escalate to the team lead immediately.",
    communication_style: {
      "verbosity" => "detailed",
      "formality" => "structured",
      "tone" => "professional"
    },
    quality_checks: [
      { "check" => "task_completeness", "severity" => "error" },
      { "check" => "status_reporting", "severity" => "warning" }
    ],
    delegation_rules: {
      "can_delegate" => false
    },
    escalation_rules: {
      "escalate_on_block" => true,
      "escalate_target" => "lead"
    }
  },
  {
    name: "Reviewer",
    slug: "system-reviewer",
    role_type: "reviewer",
    is_system: true,
    description: "Quality-focused reviewer that checks for TODOs, stubs, incomplete implementations, and missing error handling.",
    system_prompt_template: "You are a code/output reviewer on team {{team_name}}. Your role is to thoroughly review work products for quality issues. Check for: TODO/FIXME comments, stub implementations, missing error handling, incomplete features, and security vulnerabilities. Return structured findings with severity levels.",
    communication_style: {
      "verbosity" => "detailed",
      "formality" => "structured",
      "tone" => "constructive"
    },
    quality_checks: [
      { "check" => "no_todos", "severity" => "warning" },
      { "check" => "no_stubs", "severity" => "error" },
      { "check" => "error_handling_present", "severity" => "warning" },
      { "check" => "no_security_vulnerabilities", "severity" => "error" },
      { "check" => "complete_implementation", "severity" => "error" }
    ],
    expected_output_schema: {
      "type" => "object",
      "properties" => {
        "findings" => { "type" => "array" },
        "quality_score" => { "type" => "number" },
        "approved" => { "type" => "boolean" }
      }
    },
    review_criteria: [
      "No TODO/FIXME/HACK comments in production code",
      "All methods have proper error handling",
      "No stub or placeholder implementations",
      "Security best practices followed",
      "Code follows project conventions"
    ]
  },
  {
    name: "TypeChecker",
    slug: "system-type-checker",
    role_type: "type_checker",
    is_system: true,
    description: "Type safety specialist that checks for any types, missing annotations, and type inconsistencies.",
    system_prompt_template: "You are a type safety specialist on team {{team_name}}. Your role is to review code for type safety issues. Check for: use of 'any' type, missing type annotations, type inconsistencies between interfaces and implementations, and potential runtime type errors. Suggest proper typed alternatives.",
    communication_style: {
      "verbosity" => "precise",
      "formality" => "technical",
      "tone" => "analytical"
    },
    quality_checks: [
      { "check" => "no_any_types", "severity" => "warning" },
      { "check" => "complete_type_annotations", "severity" => "warning" },
      { "check" => "interface_consistency", "severity" => "error" },
      { "check" => "no_type_assertions", "severity" => "info" }
    ],
    expected_output_schema: {
      "type" => "object",
      "properties" => {
        "type_issues" => { "type" => "array" },
        "type_coverage" => { "type" => "number" }
      }
    }
  },
  {
    name: "TestWriter",
    slug: "system-test-writer",
    role_type: "test_writer",
    is_system: true,
    description: "Creates comprehensive tests with coverage targets for all public interfaces.",
    system_prompt_template: "You are a test engineer on team {{team_name}}. Your role is to write comprehensive tests for the implementation. Target {{coverage_target}}% code coverage. Write unit tests, integration tests, and edge case tests. Use the project's existing test framework and conventions.",
    communication_style: {
      "verbosity" => "detailed",
      "formality" => "structured",
      "tone" => "methodical"
    },
    quality_checks: [
      { "check" => "coverage_target_met", "severity" => "warning" },
      { "check" => "edge_cases_covered", "severity" => "warning" },
      { "check" => "tests_pass", "severity" => "error" }
    ],
    expected_output_schema: {
      "type" => "object",
      "properties" => {
        "test_files" => { "type" => "array" },
        "coverage_percentage" => { "type" => "number" },
        "test_count" => { "type" => "integer" }
      }
    }
  },
  {
    name: "DocumentationExpert",
    slug: "system-documentation-expert",
    role_type: "documentation_expert",
    is_system: true,
    description: "Documentation specialist that creates comprehensive docs for all public APIs and interfaces.",
    system_prompt_template: "You are a documentation specialist on team {{team_name}}. Your role is to create clear, comprehensive documentation for all public APIs, interfaces, and user-facing features. Follow the project's documentation conventions. Include usage examples, parameter descriptions, and error scenarios.",
    communication_style: {
      "verbosity" => "comprehensive",
      "formality" => "professional",
      "tone" => "educational"
    },
    quality_checks: [
      { "check" => "all_public_apis_documented", "severity" => "error" },
      { "check" => "usage_examples_included", "severity" => "warning" },
      { "check" => "parameter_descriptions_complete", "severity" => "warning" }
    ],
    expected_output_schema: {
      "type" => "object",
      "properties" => {
        "doc_files" => { "type" => "array" },
        "api_coverage" => { "type" => "number" }
      }
    }
  }
]

profiles.each do |attrs|
  profile = Ai::RoleProfile.find_or_initialize_by(slug: attrs[:slug])
  profile.assign_attributes(attrs)
  profile.save!
  Rails.logger.info "[Seeds] Created/Updated role profile: #{profile.name} (#{profile.slug})"
end

Rails.logger.info "[Seeds] System role profiles seeded: #{Ai::RoleProfile.system_profiles.count} profiles"
