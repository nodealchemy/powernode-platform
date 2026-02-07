# frozen_string_literal: true

module Ai
  class DevopsService
    attr_reader :account

    def initialize(account)
      @account = account
    end

    # Template Management
    def create_template(name:, category:, template_type:, workflow_definition:, user: nil, description: nil, trigger_config: {}, variables: [], secrets_required: [])
      Ai::DevopsTemplate.create!(
        account: account,
        created_by: user,
        name: name,
        category: category,
        template_type: template_type,
        workflow_definition: workflow_definition,
        description: description,
        trigger_config: trigger_config,
        variables: variables,
        secrets_required: secrets_required,
        status: "draft",
        visibility: "private"
      )
    end

    def search_templates(query: nil, category: nil, template_type: nil, page: 1, per_page: 20)
      templates = Ai::DevopsTemplate.published
                                    .where("visibility IN (?) OR account_id = ?", %w[public marketplace], account.id)

      if query.present?
        sanitized = ActiveRecord::Base.sanitize_sql_like(query)
        templates = templates.where("name ILIKE ? OR description ILIKE ?", "%#{sanitized}%", "%#{sanitized}%")
      end
      templates = templates.by_category(category) if category.present?
      templates = templates.by_type(template_type) if template_type.present?

      templates.order(installation_count: :desc).page(page).per(per_page)
    end

    # Installation Management
    def install_template(template:, user:, variable_values: {}, custom_config: {})
      return { success: false, error: "Template not available" } unless template.published?

      existing = Ai::DevopsTemplateInstallation.find_by(account: account, devops_template: template)
      return { success: false, error: "Already installed" } if existing&.active?

      installation = Ai::DevopsTemplateInstallation.create!(
        account: account,
        devops_template: template,
        installed_by: user,
        status: "active",
        installed_version: template.version,
        variable_values: variable_values,
        custom_config: custom_config
      )

      # Create workflow from template
      workflow = create_workflow_from_template(template, installation, variable_values)
      installation.update!(created_workflow: workflow) if workflow

      template.increment_installations!

      { success: true, installation: installation, workflow: workflow }
    end

    # Pipeline Execution
    def execute_pipeline(installation: nil, pipeline_type:, user: nil, input_data: {}, trigger_source: nil, trigger_event: nil, repository_id: nil, branch: nil, commit_sha: nil, pull_request_number: nil)
      execution = Ai::PipelineExecution.create!(
        account: account,
        devops_installation: installation,
        triggered_by: user,
        pipeline_type: pipeline_type,
        status: "pending",
        trigger_source: trigger_source,
        trigger_event: trigger_event,
        repository_id: repository_id,
        branch: branch,
        commit_sha: commit_sha,
        pull_request_number: pull_request_number,
        input_data: input_data
      )

      # Start async execution
      execution.start!
      # Ai::ExecutePipelineJob.perform_async(execution.id)

      { success: true, execution: execution }
    end

    def get_pipeline_status(execution)
      {
        id: execution.id,
        execution_id: execution.execution_id,
        status: execution.status,
        pipeline_type: execution.pipeline_type,
        started_at: execution.started_at,
        completed_at: execution.completed_at,
        duration_ms: execution.duration_ms,
        output_data: execution.output_data,
        ai_analysis: execution.ai_analysis
      }
    end

    # Deployment Risk Assessment
    def assess_deployment_risk(execution: nil, deployment_type:, target_environment:, change_data: {}, user: nil)
      assessment = Ai::DeploymentRisk.create!(
        account: account,
        pipeline_execution: execution,
        assessed_by: user,
        deployment_type: deployment_type,
        target_environment: target_environment,
        risk_level: "pending",
        status: "pending"
      )

      # Analyze risk factors
      risk_factors = analyze_risk_factors(change_data, target_environment)
      change_analysis = analyze_changes(change_data)
      impact_analysis = analyze_impact(change_data, target_environment)
      recommendations = generate_recommendations(risk_factors)
      mitigations = suggest_mitigations(risk_factors)

      assessment.assess!(
        risk_factors: risk_factors,
        change_analysis: change_analysis,
        impact_analysis: impact_analysis,
        recommendations: recommendations,
        mitigations: mitigations
      )

      { success: true, assessment: assessment.reload }
    end

    # Code Review
    def create_code_review(execution: nil, repository_id: nil, pull_request_number: nil, commit_sha: nil, base_branch: nil, head_branch: nil)
      review = Ai::CodeReview.create!(
        account: account,
        pipeline_execution: execution,
        status: "pending",
        repository_id: repository_id,
        pull_request_number: pull_request_number,
        commit_sha: commit_sha,
        base_branch: base_branch,
        head_branch: head_branch
      )

      # Start async analysis
      review.start_analysis!
      # Ai::AnalyzeCodeReviewJob.perform_async(review.id)

      { success: true, review: review }
    end

    def complete_code_review(review:, file_analyses:, issues:, suggestions:, security_findings: [], quality_metrics: {}, summary: nil, overall_rating: nil, tokens_used: 0, cost: 0)
      review.complete!(
        file_analyses: file_analyses,
        issues: issues,
        suggestions: suggestions,
        security_findings: security_findings,
        quality_metrics: quality_metrics,
        summary: summary,
        overall_rating: overall_rating,
        tokens_used: tokens_used,
        cost: cost
      )

      { success: true, review: review.reload }
    end

    # Analytics
    def get_pipeline_analytics(start_date: 30.days.ago, end_date: Time.current)
      executions = account.ai_pipeline_executions.where(created_at: start_date..end_date)

      {
        total_executions: executions.count,
        by_status: executions.group(:status).count,
        by_type: executions.group(:pipeline_type).count,
        success_rate: calculate_success_rate(executions),
        average_duration_ms: executions.completed.average(:duration_ms)&.to_i,
        deployments: {
          total: account.ai_deployment_risks.where(created_at: start_date..end_date).count,
          by_risk_level: account.ai_deployment_risks.where(created_at: start_date..end_date).group(:risk_level).count,
          by_decision: account.ai_deployment_risks.where(created_at: start_date..end_date).where.not(decision: nil).group(:decision).count
        },
        code_reviews: {
          total: account.ai_code_reviews.where(created_at: start_date..end_date).count,
          issues_found: account.ai_code_reviews.where(created_at: start_date..end_date).sum(:issues_found),
          critical_issues: account.ai_code_reviews.where(created_at: start_date..end_date).sum(:critical_issues)
        }
      }
    end

    private

    def create_workflow_from_template(template, installation, variable_values)
      definition = template.workflow_definition.deep_dup

      # Substitute variables
      template.variables.each do |var|
        var_name = var["name"]
        var_value = variable_values[var_name] || var["default"]
        definition = substitute_variable(definition, var_name, var_value)
      end

      Ai::Workflow.create!(
        account: account,
        name: "#{template.name} (from DevOps template)",
        description: template.description,
        workflow_type: "devops",
        nodes: definition["nodes"] || [],
        edges: definition["edges"] || [],
        trigger_config: template.trigger_config,
        status: "active"
      )
    rescue StandardError => e
      Rails.logger.error "Failed to create workflow from template: #{e.message}"
      nil
    end

    def substitute_variable(obj, var_name, value)
      case obj
      when Hash
        obj.transform_values { |v| substitute_variable(v, var_name, value) }
      when Array
        obj.map { |v| substitute_variable(v, var_name, value) }
      when String
        obj.gsub("{{#{var_name}}}", value.to_s)
      else
        obj
      end
    end

    def analyze_risk_factors(change_data, environment)
      factors = []

      # Code complexity factor
      if change_data["lines_changed"].to_i > 500
        factors << { name: "code_complexity", score: 0.8, reason: "Large number of lines changed" }
      elsif change_data["lines_changed"].to_i > 100
        factors << { name: "code_complexity", score: 0.5, reason: "Moderate number of lines changed" }
      else
        factors << { name: "code_complexity", score: 0.2, reason: "Small number of lines changed" }
      end

      # Environment factor
      case environment
      when "production"
        factors << { name: "environment_sensitivity", score: 0.9, reason: "Production deployment" }
      when "staging"
        factors << { name: "environment_sensitivity", score: 0.5, reason: "Staging deployment" }
      else
        factors << { name: "environment_sensitivity", score: 0.2, reason: "Non-production deployment" }
      end

      # Test coverage factor
      coverage = change_data["test_coverage"].to_f
      if coverage < 50
        factors << { name: "test_coverage", score: 0.8, reason: "Low test coverage (#{coverage}%)" }
      elsif coverage < 80
        factors << { name: "test_coverage", score: 0.4, reason: "Moderate test coverage (#{coverage}%)" }
      else
        factors << { name: "test_coverage", score: 0.1, reason: "Good test coverage (#{coverage}%)" }
      end

      factors
    end

    def analyze_changes(change_data)
      {
        files_changed: change_data["files_changed"].to_i,
        lines_added: change_data["lines_added"].to_i,
        lines_removed: change_data["lines_removed"].to_i,
        dependencies_changed: change_data["dependencies_changed"] || false,
        database_migrations: change_data["database_migrations"] || false,
        config_changes: change_data["config_changes"] || false
      }
    end

    def analyze_impact(change_data, environment)
      {
        affected_services: change_data["affected_services"] || [],
        user_impact: environment == "production" ? "high" : "low",
        rollback_complexity: change_data["database_migrations"] ? "high" : "low",
        estimated_downtime: change_data["requires_downtime"] ? "yes" : "no"
      }
    end

    def generate_recommendations(risk_factors)
      recommendations = []

      risk_factors.each do |factor|
        if factor[:score] > 0.7
          case factor[:name]
          when "code_complexity"
            recommendations << "Consider breaking down this deployment into smaller, incremental changes"
          when "environment_sensitivity"
            recommendations << "Ensure thorough testing in staging before production deployment"
          when "test_coverage"
            recommendations << "Add more tests before deploying to reduce risk"
          end
        end
      end

      recommendations
    end

    def suggest_mitigations(risk_factors)
      mitigations = []

      avg_score = risk_factors.sum { |f| f[:score] } / risk_factors.length.to_f

      if avg_score > 0.6
        mitigations << { action: "blue_green_deployment", description: "Use blue-green deployment for zero-downtime rollback capability" }
        mitigations << { action: "canary_release", description: "Roll out to a small percentage of users first" }
      end

      if risk_factors.any? { |f| f[:name] == "test_coverage" && f[:score] > 0.5 }
        mitigations << { action: "monitoring", description: "Set up enhanced monitoring and alerting during deployment" }
      end

      mitigations
    end

    def calculate_success_rate(executions)
      return 0 if executions.count.zero?

      completed = executions.where(status: "completed").count
      (completed.to_f / executions.count * 100).round(2)
    end
  end
end
