# frozen_string_literal: true

module Api
  module V1
    module Ai
      class DevopsRiskReviewController < ApplicationController
        before_action :set_service

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

        private

        def set_service
          @service = ::Ai::DevopsService.new(current_account)
        end

        def authorize_action!(permission)
          unless current_user.has_permission?(permission)
            render_forbidden("Insufficient permissions")
          end
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
