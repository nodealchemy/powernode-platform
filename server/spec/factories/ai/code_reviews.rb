# frozen_string_literal: true

FactoryBot.define do
  factory :ai_code_review, class: "Ai::CodeReview" do
    association :account

    review_id { SecureRandom.uuid }
    status { "pending" }
    repository_id { SecureRandom.uuid }
    pull_request_number { "123" }
    commit_sha { SecureRandom.hex(20) }
    base_branch { "main" }
    head_branch { "feature/new-feature" }
    files_reviewed { 0 }
    lines_added { 120 }
    lines_removed { 30 }
    issues_found { 0 }
    critical_issues { 0 }
    suggestions_count { 0 }
    file_analyses { [] }
    issues { [] }
    suggestions { [] }
    security_findings { [] }
    quality_metrics { {} }
    tokens_used { 0 }
    cost_usd { 0 }

    trait :pending do
      status { "pending" }
    end

    trait :analyzing do
      status { "analyzing" }
      started_at { 1.minute.ago }
    end

    trait :completed do
      status { "completed" }
      started_at { 5.minutes.ago }
      completed_at { 1.minute.ago }
      files_reviewed { 8 }
      issues_found { 5 }
      critical_issues { 1 }
      suggestions_count { 10 }
      tokens_used { 2500 }
      cost_usd { 0.0375 }
      overall_rating { "B" }
      summary { "Code review completed. Found 5 issues including 1 critical. 10 improvement suggestions provided." }
      file_analyses do
        [
          {
            "file" => "src/services/payment.rb",
            "issues" => 2,
            "suggestions" => 3,
            "quality_score" => 75
          },
          {
            "file" => "src/controllers/orders_controller.rb",
            "issues" => 3,
            "suggestions" => 7,
            "quality_score" => 68
          }
        ]
      end
      issues do
        [
          {
            "file" => "src/services/payment.rb",
            "line" => 45,
            "severity" => "critical",
            "type" => "security",
            "message" => "Potential SQL injection vulnerability",
            "suggestion" => "Use parameterized queries"
          },
          {
            "file" => "src/services/payment.rb",
            "line" => 78,
            "severity" => "warning",
            "type" => "performance",
            "message" => "N+1 query detected",
            "suggestion" => "Use eager loading"
          }
        ]
      end
      suggestions do
        [
          {
            "file" => "src/services/payment.rb",
            "line" => 12,
            "type" => "refactor",
            "message" => "Consider extracting this logic into a separate method"
          }
        ]
      end
      quality_metrics do
        {
          "maintainability" => 72,
          "reliability" => 85,
          "security" => 65,
          "complexity" => 45,
          "duplication" => 8.5
        }
      end
    end

    trait :failed do
      status { "failed" }
      started_at { 2.minutes.ago }
      completed_at { 1.minute.ago }
      summary { "Code review failed: Unable to analyze repository" }
    end

    trait :partial do
      status { "partial" }
      started_at { 3.minutes.ago }
      completed_at { 1.minute.ago }
      files_reviewed { 3 }
      summary { "Partial review completed. Some files could not be analyzed." }
    end

    trait :clean do
      status { "completed" }
      started_at { 2.minutes.ago }
      completed_at { 1.minute.ago }
      files_reviewed { 5 }
      issues_found { 0 }
      critical_issues { 0 }
      suggestions_count { 2 }
      overall_rating { "A" }
      summary { "Excellent code quality. No issues found." }
      quality_metrics do
        {
          "maintainability" => 95,
          "reliability" => 98,
          "security" => 100,
          "complexity" => 15,
          "duplication" => 0
        }
      end
    end

    trait :with_critical_issues do
      status { "completed" }
      issues_found { 8 }
      critical_issues { 3 }
      overall_rating { "D" }
      issues do
        [
          { "severity" => "critical", "type" => "security", "message" => "Hardcoded credentials" },
          { "severity" => "critical", "type" => "security", "message" => "Unsafe deserialization" },
          { "severity" => "critical", "type" => "bug", "message" => "Null pointer exception" }
        ]
      end
    end

    trait :with_security_findings do
      status { "completed" }
      security_findings do
        [
          {
            "severity" => "high",
            "type" => "sql_injection",
            "file" => "src/models/user.rb",
            "line" => 34,
            "description" => "SQL injection vulnerability in user search",
            "cwe" => "CWE-89",
            "remediation" => "Use parameterized queries"
          },
          {
            "severity" => "medium",
            "type" => "xss",
            "file" => "src/views/comments/show.html.erb",
            "line" => 12,
            "description" => "Potential XSS vulnerability",
            "cwe" => "CWE-79",
            "remediation" => "Sanitize user input"
          }
        ]
      end
    end

    trait :large_pr do
      files_reviewed { 45 }
      lines_added { 2500 }
      lines_removed { 800 }
      issues_found { 25 }
      suggestions_count { 40 }
      tokens_used { 15000 }
      cost_usd { 0.225 }
    end

    trait :small_pr do
      files_reviewed { 2 }
      lines_added { 25 }
      lines_removed { 10 }
      issues_found { 1 }
      suggestions_count { 2 }
      tokens_used { 500 }
      cost_usd { 0.0075 }
    end

    trait :with_pipeline_execution do
      association :pipeline_execution, factory: :ai_pipeline_execution
    end
  end
end
