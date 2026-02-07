# frozen_string_literal: true

module Api
  module V1
    module Ai
      class DevopsController < ApplicationController
        before_action :set_service

        # Templates
        # GET /api/v1/ai/devops/templates
        def templates
          authorize_action!("ai.devops.read")
          return if performed?

          templates = @service.search_templates(
            query: params[:query],
            category: params[:category],
            template_type: params[:template_type],
            page: params[:page] || 1,
            per_page: params[:per_page] || 20
          )

          render_success(
            templates: templates.map { |t| template_json(t) },
            pagination: pagination_meta(templates)
          )
        end

        # GET /api/v1/ai/devops/templates/:id
        def show_template
          authorize_action!("ai.devops.read")
          return if performed?

          template = ::Ai::DevopsTemplate.find(params[:id])
          render_success(template: template_json(template, detailed: true))
        end

        # POST /api/v1/ai/devops/templates
        def create_template
          authorize_action!("ai.devops.manage")
          return if performed?

          template = @service.create_template(
            name: params[:name],
            category: params[:category],
            template_type: params[:template_type],
            workflow_definition: params[:workflow_definition],
            user: current_user,
            description: params[:description],
            trigger_config: params[:trigger_config] || {},
            variables: params[:variables] || [],
            secrets_required: params[:secrets_required] || []
          )

          render_success(template: template_json(template), status: :created)
        end

        # PATCH /api/v1/ai/devops/templates/:id
        def update_template
          authorize_action!("ai.devops.manage")
          return if performed?

          template = ::Ai::DevopsTemplate.find(params[:id])

          permitted = {}
          permitted[:name] = params[:name] if params.key?(:name)
          permitted[:description] = params[:description] if params.key?(:description)
          permitted[:category] = params[:category] if params.key?(:category)
          permitted[:template_type] = params[:template_type] if params.key?(:template_type)
          permitted[:status] = params[:status] if params.key?(:status)
          permitted[:visibility] = params[:visibility] if params.key?(:visibility)
          permitted[:workflow_definition] = params[:workflow_definition] if params.key?(:workflow_definition)
          permitted[:trigger_config] = params[:trigger_config] if params.key?(:trigger_config)
          permitted[:input_schema] = params[:input_schema] if params.key?(:input_schema)
          permitted[:output_schema] = params[:output_schema] if params.key?(:output_schema)
          permitted[:variables] = params[:variables] if params.key?(:variables)
          permitted[:secrets_required] = params[:secrets_required] if params.key?(:secrets_required)
          permitted[:integrations_required] = params[:integrations_required] if params.key?(:integrations_required)
          permitted[:tags] = params[:tags] if params.key?(:tags)
          permitted[:usage_guide] = params[:usage_guide] if params.key?(:usage_guide)

          template.update!(permitted)
          render_success(template: template_json(template, detailed: true))
        end

        # Installations
        # GET /api/v1/ai/devops/installations
        def installations
          authorize_action!("ai.devops.read")
          return if performed?

          installations = current_account.ai_devops_template_installations
                                         .includes(:devops_template)
                                         .order(created_at: :desc)
                                         .page(params[:page])
                                         .per(params[:per_page] || 20)

          render_success(
            installations: installations.map { |i| installation_json(i) },
            pagination: pagination_meta(installations)
          )
        end

        # POST /api/v1/ai/devops/templates/:template_id/install
        def install
          authorize_action!("ai.devops.manage")
          return if performed?

          template = ::Ai::DevopsTemplate.find(params[:template_id])
          result = @service.install_template(
            template: template,
            user: current_user,
            variable_values: params[:variable_values] || {},
            custom_config: params[:custom_config] || {}
          )

          if result[:success]
            render_success(installation: installation_json(result[:installation]))
          else
            render_error(result[:error], :unprocessable_content)
          end
        end

        # DELETE /api/v1/ai/devops/installations/:id
        def uninstall
          authorize_action!("ai.devops.manage")
          return if performed?

          installation = current_account.ai_devops_template_installations.find(params[:id])
          installation.destroy!

          render_success(message: "Template uninstalled successfully")
        end

        # Pipeline Executions
        # GET /api/v1/ai/devops/executions
        def executions
          authorize_action!("ai.devops.read")
          return if performed?

          executions = current_account.ai_pipeline_executions
                                     .order(created_at: :desc)
                                     .page(params[:page])
                                     .per(params[:per_page] || 20)

          executions = executions.by_type(params[:pipeline_type]) if params[:pipeline_type].present?
          executions = executions.where(status: params[:status]) if params[:status].present?
          executions = executions.for_repository(params[:repository_id]) if params[:repository_id].present?

          render_success(
            executions: executions.map { |e| execution_json(e) },
            pagination: pagination_meta(executions)
          )
        end

        # POST /api/v1/ai/devops/executions
        def create_execution
          authorize_action!("ai.devops.manage")
          return if performed?

          installation = params[:installation_id].present? ?
            current_account.ai_devops_template_installations.find(params[:installation_id]) : nil

          result = @service.execute_pipeline(
            installation: installation,
            pipeline_type: params[:pipeline_type],
            user: current_user,
            input_data: params[:input_data] || {},
            trigger_source: params[:trigger_source],
            trigger_event: params[:trigger_event],
            repository_id: params[:repository_id],
            branch: params[:branch],
            commit_sha: params[:commit_sha],
            pull_request_number: params[:pull_request_number]
          )

          if result[:success]
            render_success(execution: execution_json(result[:execution]), status: :created)
          else
            render_error(result[:error], :unprocessable_content)
          end
        end

        # GET /api/v1/ai/devops/executions/:id
        def show_execution
          authorize_action!("ai.devops.read")
          return if performed?

          execution = current_account.ai_pipeline_executions.find(params[:id])
          render_success(execution: execution_json(execution, detailed: true))
        end

        # Deployment Risks
        # GET /api/v1/ai/devops/risks
        def risks
          authorize_action!("ai.devops.read")
          return if performed?

          risks = current_account.ai_deployment_risks
                                .order(created_at: :desc)
                                .page(params[:page])
                                .per(params[:per_page] || 20)

          risks = risks.by_environment(params[:environment]) if params[:environment].present?
          risks = risks.where(risk_level: params[:risk_level]) if params[:risk_level].present?

          render_success(
            risks: risks.map { |r| risk_json(r) },
            pagination: pagination_meta(risks)
          )
        end

        # POST /api/v1/ai/devops/risks/assess
        def assess_risk
          authorize_action!("ai.devops.manage")
          return if performed?

          execution = params[:execution_id].present? ?
            current_account.ai_pipeline_executions.find(params[:execution_id]) : nil

          result = @service.assess_deployment_risk(
            execution: execution,
            deployment_type: params[:deployment_type],
            target_environment: params[:target_environment],
            change_data: params[:change_data] || {},
            user: current_user
          )

          if result[:success]
            render_success(assessment: risk_json(result[:assessment]))
          else
            render_error(result[:error], :unprocessable_content)
          end
        end

        # PUT /api/v1/ai/devops/risks/:id/approve
        def approve_risk
          authorize_action!("ai.devops.manage")
          return if performed?

          risk = current_account.ai_deployment_risks.find(params[:id])
          risk.approve!(user: current_user, rationale: params[:rationale])

          render_success(assessment: risk_json(risk))
        end

        # PUT /api/v1/ai/devops/risks/:id/reject
        def reject_risk
          authorize_action!("ai.devops.manage")
          return if performed?

          risk = current_account.ai_deployment_risks.find(params[:id])
          risk.reject!(user: current_user, rationale: params[:rationale])

          render_success(assessment: risk_json(risk))
        end

        # Code Reviews
        # GET /api/v1/ai/devops/reviews
        def reviews
          authorize_action!("ai.devops.read")
          return if performed?

          reviews = current_account.ai_code_reviews
                                  .order(created_at: :desc)
                                  .page(params[:page])
                                  .per(params[:per_page] || 20)

          reviews = reviews.where(status: params[:status]) if params[:status].present?
          reviews = reviews.for_repository(params[:repository_id]) if params[:repository_id].present?

          render_success(
            reviews: reviews.map { |r| review_json(r) },
            pagination: pagination_meta(reviews)
          )
        end

        # POST /api/v1/ai/devops/reviews
        def create_review
          authorize_action!("ai.devops.manage")
          return if performed?

          execution = params[:execution_id].present? ?
            current_account.ai_pipeline_executions.find(params[:execution_id]) : nil

          result = @service.create_code_review(
            execution: execution,
            repository_id: params[:repository_id],
            pull_request_number: params[:pull_request_number],
            commit_sha: params[:commit_sha],
            base_branch: params[:base_branch],
            head_branch: params[:head_branch]
          )

          if result[:success]
            render_success(review: review_json(result[:review]), status: :created)
          else
            render_error(result[:error], :unprocessable_content)
          end
        end

        # GET /api/v1/ai/devops/reviews/:id
        def show_review
          authorize_action!("ai.devops.read")
          return if performed?

          review = current_account.ai_code_reviews.find(params[:id])
          render_success(review: review_json(review, detailed: true))
        end

        # GET /api/v1/ai/devops/analytics
        def analytics
          authorize_action!("ai.devops.read")
          return if performed?

          analytics = @service.get_pipeline_analytics(
            start_date: params[:start_date]&.to_datetime || 30.days.ago,
            end_date: params[:end_date]&.to_datetime || Time.current
          )

          render_success(analytics: analytics)
        end

        private

        def set_service
          @service = ::Ai::DevopsService.new(current_account)
        end

        def authorize_action!(permission)
          unless current_user.has_permission?(permission)
            render_forbidden("Insufficient permissions")
          end
        end

        def template_json(template, detailed: false)
          json = {
            id: template.id,
            name: template.name,
            slug: template.slug,
            description: template.description,
            category: template.category,
            template_type: template.template_type,
            status: template.status,
            visibility: template.visibility,
            version: template.version,
            installation_count: template.installation_count,
            average_rating: template.average_rating,
            is_system: template.is_system,
            is_featured: template.is_featured,
            price_usd: template.price_usd,
            published_at: template.published_at,
            is_owner: template.account_id == current_account.id
          }

          if detailed
            json.merge!(
              workflow_definition: template.workflow_definition,
              trigger_config: template.trigger_config,
              input_schema: template.input_schema,
              output_schema: template.output_schema,
              variables: template.variables,
              secrets_required: template.secrets_required,
              integrations_required: template.integrations_required,
              tags: template.tags,
              usage_guide: template.usage_guide
            )
          end

          json
        end

        def installation_json(installation)
          {
            id: installation.id,
            status: installation.status,
            installed_version: installation.installed_version,
            execution_count: installation.execution_count,
            success_count: installation.success_count,
            failure_count: installation.failure_count,
            success_rate: installation.success_rate,
            last_executed_at: installation.last_executed_at,
            created_at: installation.created_at,
            template: {
              id: installation.devops_template.id,
              name: installation.devops_template.name
            }
          }
        end

        def execution_json(execution, detailed: false)
          json = {
            id: execution.id,
            execution_id: execution.execution_id,
            pipeline_type: execution.pipeline_type,
            status: execution.status,
            trigger_source: execution.trigger_source,
            trigger_event: execution.trigger_event,
            repository_id: execution.repository_id,
            branch: execution.branch,
            commit_sha: execution.commit_sha,
            pull_request_number: execution.pull_request_number,
            duration_ms: execution.duration_ms,
            started_at: execution.started_at,
            completed_at: execution.completed_at,
            created_at: execution.created_at
          }

          if detailed
            json.merge!(
              input_data: execution.input_data,
              output_data: execution.output_data,
              ai_analysis: execution.ai_analysis,
              metrics: execution.metrics
            )
          end

          json
        end

        def risk_json(risk)
          {
            id: risk.id,
            assessment_id: risk.assessment_id,
            deployment_type: risk.deployment_type,
            target_environment: risk.target_environment,
            risk_level: risk.risk_level,
            risk_score: risk.risk_score,
            status: risk.status,
            decision: risk.decision,
            requires_approval: risk.requires_approval,
            risk_factors: risk.risk_factors,
            change_analysis: risk.change_analysis,
            impact_analysis: risk.impact_analysis,
            recommendations: risk.recommendations,
            mitigations: risk.mitigations,
            summary: risk.summary,
            decision_rationale: risk.decision_rationale,
            assessed_at: risk.assessed_at,
            decision_at: risk.decision_at,
            created_at: risk.created_at
          }
        end

        def review_json(review, detailed: false)
          json = {
            id: review.id,
            review_id: review.review_id,
            status: review.status,
            repository_id: review.repository_id,
            pull_request_number: review.pull_request_number,
            commit_sha: review.commit_sha,
            base_branch: review.base_branch,
            head_branch: review.head_branch,
            files_reviewed: review.files_reviewed,
            lines_added: review.lines_added,
            lines_removed: review.lines_removed,
            issues_found: review.issues_found,
            critical_issues: review.critical_issues,
            suggestions_count: review.suggestions_count,
            overall_rating: review.overall_rating,
            approval_recommendation: review.approval_recommendation,
            tokens_used: review.tokens_used,
            cost_usd: review.cost_usd,
            started_at: review.started_at,
            completed_at: review.completed_at,
            created_at: review.created_at
          }

          if detailed
            json.merge!(
              file_analyses: review.file_analyses,
              issues: review.issues,
              suggestions: review.suggestions,
              security_findings: review.security_findings,
              quality_metrics: review.quality_metrics,
              summary: review.summary
            )
          end

          json
        end

        def pagination_meta(collection)
          {
            current_page: collection.current_page,
            total_pages: collection.total_pages,
            total_count: collection.total_count,
            per_page: collection.limit_value
          }
        end
      end
    end
  end
end
