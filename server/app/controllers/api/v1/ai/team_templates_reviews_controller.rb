# frozen_string_literal: true

module Api
  module V1
    module Ai
      class TeamTemplatesReviewsController < ApplicationController
        rescue_from ::Ai::TeamAuthorityService::AuthorityViolation do |e|
          render_error(e.message, status: :forbidden)
        end

        before_action :authenticate_request
        before_action :set_team_service

        # ============================================================================
        # TEMPLATES
        # ============================================================================

        # GET /api/v1/ai/teams/templates
        def list_templates
          templates = @config_service.list_templates(template_filter_params)

          render_success(
            templates: templates.map { |t| serialize_template(t) },
            total_count: templates.respond_to?(:total_count) ? templates.total_count : templates.count
          )
        end

        # GET /api/v1/ai/teams/templates/:id
        def show_template
          template = @config_service.get_template(params[:id])
          render_success(serialize_template(template, detailed: true))
        end

        # POST /api/v1/ai/teams/templates
        def create_template
          template = @config_service.create_template(template_params, user: current_user)
          render_success(serialize_template(template), status: :created)
        end

        # POST /api/v1/ai/teams/templates/:id/publish
        def publish_template
          template = @config_service.publish_template(params[:id])
          render_success(serialize_template(template))
        end

        # ============================================================================
        # ROLE PROFILES
        # ============================================================================

        # GET /api/v1/ai/teams/role_profiles
        def list_role_profiles
          profiles = @crud_service.list_role_profiles(role_profile_filter_params)
          render_success(role_profiles: profiles.map { |p| serialize_role_profile(p) })
        end

        # GET /api/v1/ai/teams/role_profiles/:id
        def show_role_profile
          profile = @crud_service.get_role_profile(params[:id])
          render_success(serialize_role_profile(profile))
        end

        # ============================================================================
        # TRAJECTORIES
        # ============================================================================

        # GET /api/v1/ai/teams/trajectories
        def list_trajectories
          trajectories = @crud_service.list_trajectories(trajectory_filter_params)
          render_success(trajectories: trajectories.map { |t| serialize_trajectory(t) })
        end

        # GET /api/v1/ai/teams/trajectories/search
        def search_trajectories
          trajectories = @crud_service.search_trajectories(
            params[:query],
            trajectory_filter_params
          )
          render_success(trajectories: trajectories.map { |t| serialize_trajectory(t) })
        end

        # GET /api/v1/ai/teams/trajectories/:id
        def show_trajectory
          trajectory = @crud_service.get_trajectory(params[:id])
          render_success(serialize_trajectory(trajectory, detailed: true))
        end

        # ============================================================================
        # REVIEWS
        # ============================================================================

        # GET /api/v1/ai/teams/reviews/:id
        def show_review
          review = @crud_service.get_task_review(params[:id])
          render_success(serialize_review(review))
        end

        # POST /api/v1/ai/teams/reviews/:id/process
        def process_review
          review = @crud_service.process_review(
            params[:id],
            action: params[:action_type],
            notes: params[:notes]
          )
          render_success(serialize_review(review))
        end

        # GET /api/v1/ai/teams/reviews/:review_id/comments
        def list_review_comments
          authorize_code_reviews_read!
          review = current_account.ai_task_reviews.find(params[:review_id])
          comments = review.code_review_comments.ordered
          render_success({ comments: comments.map(&:comment_summary) })
        end

        # POST /api/v1/ai/teams/reviews/:review_id/comments
        def create_review_comment
          authorize_code_reviews_manage!
          review = current_account.ai_task_reviews.find(params[:review_id])
          comment = review.code_review_comments.create!(
            account: current_account,
            **review_comment_params
          )
          render_success({ comment: comment.comment_summary }, status: :created)
        end

        # PATCH /api/v1/ai/teams/reviews/:review_id/comments/:comment_id
        def update_review_comment
          authorize_code_reviews_manage!
          review = current_account.ai_task_reviews.find(params[:review_id])
          comment = review.code_review_comments.find(params[:comment_id])
          comment.update!(review_comment_params)
          render_success({ comment: comment.comment_summary })
        end

        private

        def set_team_service
          @crud_service = ::Ai::Teams::CrudService.new(account: current_account)
          @config_service = ::Ai::Teams::ConfigurationService.new(account: current_account)
        end

        def template_filter_params
          params.permit(:public_only, :system_only, :category, :topology, :page, :per_page)
        end

        def template_params
          params.permit(
            :name, :description, :category, :team_topology, :is_public,
            role_definitions: [], channel_definitions: [], tags: [],
            workflow_pattern: {}, default_config: {}
          )
        end

        def role_profile_filter_params
          params.permit(:role_type, :is_system)
        end

        def trajectory_filter_params
          params.permit(:type, :status, :query, :limit, :agent_id, tags: [])
        end

        def authorize_code_reviews_read!
          return if current_user.has_permission?("ai.code_reviews.read")

          render_forbidden
        end

        def authorize_code_reviews_manage!
          return if current_user.has_permission?("ai.code_reviews.manage")

          render_forbidden
        end

        def review_comment_params
          params.require(:comment).permit(:file_path, :line_start, :line_end, :comment_type, :severity, :content, :suggested_fix, :category, :resolved)
        end

        def serialize_template(template, detailed: false)
          data = {
            id: template.id,
            name: template.name,
            slug: template.slug,
            description: template.description,
            category: template.category,
            team_topology: template.team_topology,
            is_system: template.is_system,
            is_public: template.is_public,
            usage_count: template.usage_count,
            average_rating: template.average_rating,
            published_at: template.published_at,
            tags: template.tags
          }

          if detailed
            data[:role_definitions] = template.role_definitions
            data[:channel_definitions] = template.channel_definitions
            data[:workflow_pattern] = template.workflow_pattern
            data[:default_config] = template.default_config
          end

          data
        end

        def serialize_role_profile(profile)
          {
            id: profile.id,
            name: profile.name,
            slug: profile.slug,
            role_type: profile.role_type,
            description: profile.description,
            system_prompt_template: profile.system_prompt_template,
            communication_style: profile.communication_style,
            expected_output_schema: profile.expected_output_schema,
            review_criteria: profile.review_criteria,
            quality_checks: profile.quality_checks,
            delegation_rules: profile.delegation_rules,
            escalation_rules: profile.escalation_rules,
            is_system: profile.is_system,
            metadata: profile.metadata
          }
        end

        def serialize_trajectory(trajectory, detailed: false)
          data = {
            id: trajectory.id,
            trajectory_id: trajectory.trajectory_id,
            title: trajectory.title,
            summary: trajectory.summary,
            status: trajectory.status,
            trajectory_type: trajectory.trajectory_type,
            quality_score: trajectory.quality_score,
            access_count: trajectory.access_count,
            chapter_count: trajectory.chapter_count,
            tags: trajectory.tags,
            outcome_summary: trajectory.outcome_summary,
            created_at: trajectory.created_at
          }

          if detailed
            chapters = trajectory.chapters.loaded? ? trajectory.chapters : trajectory.chapters.includes(:trajectory)
            data[:chapters] = chapters.ordered.map { |c| serialize_chapter(c) }
          end

          data
        end

        def serialize_chapter(chapter)
          {
            id: chapter.id,
            chapter_number: chapter.chapter_number,
            title: chapter.title,
            chapter_type: chapter.chapter_type,
            content: chapter.content,
            reasoning: chapter.reasoning,
            key_decisions: chapter.key_decisions,
            artifacts: chapter.artifacts,
            context_references: chapter.context_references,
            duration_ms: chapter.duration_ms,
            metadata: chapter.metadata
          }
        end

        def serialize_review(review)
          {
            id: review.id,
            review_id: review.review_id,
            status: review.status,
            review_mode: review.review_mode,
            quality_score: review.quality_score,
            findings: review.findings,
            completeness_checks: review.completeness_checks,
            approval_notes: review.approval_notes,
            rejection_reason: review.rejection_reason,
            revision_count: review.revision_count,
            review_duration_ms: review.review_duration_ms,
            reviewer_role_id: review.reviewer_role_id,
            reviewer_agent_id: review.reviewer_agent_id,
            team_task_id: review.team_task_id,
            created_at: review.created_at
          }
        end
      end
    end
  end
end
