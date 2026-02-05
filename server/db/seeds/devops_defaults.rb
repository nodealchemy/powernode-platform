# frozen_string_literal: true

# DevOps Pipeline System - Default Seed Data
# Creates default prompt templates for common AI-powered DevOps operations

puts "Seeding DevOps default data..."

# Get system account for default templates
system_account = Account.find_by(name: "System") || Account.first
unless system_account
  puts "  ⏭️  No account found — skipping DevOps defaults"
  return
end

# Create default prompt templates
default_templates = [
  {
    name: "Code Review",
    slug: "code-review",
    description: "AI-powered code review for pull requests",
    category: "review",
    content: <<~PROMPT,
      You are reviewing a pull request. Session ID: {{ session_id }}

      {% if previous_context %}
      Previous review context:
      {{ previous_context }}
      {% endif %}

      Analyze the following diff and provide:

      1. **Summary**: Brief overview of changes
      2. **Quality Assessment**: Code quality, patterns, best practices
      3. **Security Review**: Potential vulnerabilities or concerns
      4. **Suggestions**: Specific improvements with code examples
      5. **Risk Level**: LOW/MEDIUM/HIGH with justification

      Be constructive and specific. Reference line numbers.

      DIFF:
      {{ diff }}
    PROMPT
    variables: {
      session_id: "pr-{{ pr_number }}-review",
      previous_context: "",
      diff: ""
    },
    is_active: true
  },
  {
    name: "Issue Implementation",
    slug: "issue-implementation",
    description: "AI-powered issue implementation from GitHub/Gitea issues",
    category: "implement",
    content: <<~PROMPT,
      Implement a solution for this issue:

      Title: {{ issue_title }}

      Description:
      {{ issue_body }}

      Instructions:
      1. Analyze the codebase to understand the context
      2. Implement the minimal solution that addresses the issue
      3. Add appropriate tests
      4. Follow existing code patterns and conventions
      5. Output a summary of changes made

      Use the available file tools to make changes.
    PROMPT
    variables: {
      issue_title: "",
      issue_body: ""
    },
    is_active: true
  },
  {
    name: "Security Scan",
    slug: "security-scan",
    description: "Comprehensive AI security analysis of codebase",
    category: "security",
    content: <<~PROMPT,
      Perform a comprehensive security analysis of this codebase:

      1. **Dependency Vulnerabilities**: Check for known CVEs
      2. **Code Vulnerabilities**: SQL injection, XSS, CSRF, etc.
      3. **Authentication/Authorization**: JWT handling, session management
      4. **Secrets Exposure**: Hardcoded credentials, API keys
      5. **Configuration Issues**: Insecure defaults, debug modes
      6. **OWASP Top 10**: Check against current OWASP guidelines

      For each finding:
      - Severity: CRITICAL/HIGH/MEDIUM/LOW
      - Location: File path and line number
      - Description: What the issue is
      - Recommendation: How to fix it
      - Code Example: Fixed code if applicable

      Output as structured JSON with format:
      {
        "findings": [
          {
            "severity": "HIGH",
            "category": "injection",
            "location": { "file": "path/to/file.rb", "line": 42 },
            "title": "SQL Injection vulnerability",
            "description": "...",
            "recommendation": "...",
            "cwe_id": "CWE-89"
          }
        ],
        "summary": {
          "critical": 0,
          "high": 1,
          "medium": 3,
          "low": 5
        }
      }
    PROMPT
    variables: {},
    is_active: true
  },
  {
    name: "Deployment Review",
    slug: "deployment-review",
    description: "AI pre-deployment review and risk assessment",
    category: "deploy",
    content: <<~PROMPT,
      Review this deployment for the {{ environment }} environment:

      Changes:
      {{ changes }}

      Evaluate:
      1. Breaking changes that could cause downtime
      2. Database migrations required
      3. Configuration changes needed
      4. Rollback complexity
      5. Performance impact

      Output JSON:
      {
        "approved": true/false,
        "risk_level": "LOW/MEDIUM/HIGH/CRITICAL",
        "summary": "brief summary",
        "warnings": ["list of concerns"],
        "recommended_actions": ["pre-deploy steps"]
      }
    PROMPT
    variables: {
      environment: "staging",
      changes: ""
    },
    is_active: true
  },
  {
    name: "Post-Deploy Validation",
    slug: "post-deploy-validation",
    description: "AI post-deployment validation and health check",
    category: "deploy",
    content: <<~PROMPT,
      Validate the deployment at {{ deploy_url }}:

      1. Check critical endpoints are responding
      2. Verify authentication flows
      3. Test core functionality
      4. Check for error patterns in responses
      5. Validate API response times

      Output JSON:
      {
        "healthy": true/false,
        "issues": ["list of issues found"],
        "performance": {
          "response_time_avg_ms": 123,
          "endpoints_tested": 5
        }
      }
    PROMPT
    variables: {
      deploy_url: ""
    },
    is_active: true
  },
  {
    name: "Documentation Generator",
    slug: "documentation-generator",
    description: "AI documentation generation for code changes",
    category: "docs",
    content: <<~PROMPT,
      Generate documentation for the following code changes:

      {{ changes }}

      Create:
      1. **Change Summary**: What was changed and why
      2. **API Documentation**: If APIs were added/modified
      3. **Usage Examples**: How to use the new/changed functionality
      4. **Migration Notes**: Any breaking changes or migration steps

      Format as Markdown suitable for a CHANGELOG or documentation file.
    PROMPT
    variables: {
      changes: ""
    },
    is_active: true
  },
  {
    name: "Test Generator",
    slug: "test-generator",
    description: "AI-powered test generation for code",
    category: "implement",
    content: <<~PROMPT,
      Generate tests for the following code:

      {{ code }}

      Requirements:
      1. Generate comprehensive unit tests
      2. Cover edge cases and error conditions
      3. Follow {{ test_framework }} conventions
      4. Include setup/teardown as needed
      5. Add descriptive test names

      Output the test code that can be saved directly to a file.
    PROMPT
    variables: {
      code: "",
      test_framework: "RSpec"
    },
    is_active: true
  },
  {
    name: "Bug Fix",
    slug: "bug-fix",
    description: "AI-powered bug analysis and fix suggestion",
    category: "implement",
    content: <<~PROMPT,
      Analyze and fix the following bug:

      Bug Description:
      {{ bug_description }}

      Error Message/Stack Trace (if available):
      {{ error_details }}

      Related Code:
      {{ related_code }}

      Instructions:
      1. Analyze the root cause of the bug
      2. Propose a minimal fix
      3. Explain why this fix works
      4. Suggest any additional improvements
      5. Write tests to prevent regression
    PROMPT
    variables: {
      bug_description: "",
      error_details: "",
      related_code: ""
    },
    is_active: true
  }
]

default_templates.each do |template_attrs|
  existing = Shared::PromptTemplate.find_by(account: system_account, slug: template_attrs[:slug])
  if existing
    puts "  ⏭️  Prompt template already exists: #{existing.name} - preserving customizations"
  else
    Shared::PromptTemplate.create!(
      template_attrs.except(:slug).merge(
        account: system_account,
        slug: template_attrs[:slug],
        domain: "devops"
      )
    )
    puts "  Created prompt template: #{template_attrs[:name]}"
  end
end

puts "DevOps seed data complete!"
puts "  - Created #{default_templates.count} prompt templates"
