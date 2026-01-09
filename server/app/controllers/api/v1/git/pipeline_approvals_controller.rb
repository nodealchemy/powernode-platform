# frozen_string_literal: true

module Api
  module V1
    module Git
      class PipelineApprovalsController < ApplicationController
        before_action :set_approval, only: %i[show approve reject cancel]
        before_action :validate_permissions

        # GET /api/v1/git/pipeline_approvals
        def index
          approvals = ::Git::PipelineApproval.where(account: current_user.account)
                                         .includes(:pipeline, :requested_by, :responded_by)

          # Filters
          approvals = approvals.where(status: params[:status]) if params[:status].present?
          approvals = approvals.for_environment(params[:environment]) if params[:environment].present?
          approvals = approvals.for_pipeline(params[:pipeline_id]) if params[:pipeline_id].present?

          # Sorting
          case params[:sort]
          when "created_at"
            approvals = approvals.order(created_at: params[:direction] == "asc" ? :asc : :desc)
          when "expires_at"
            approvals = approvals.order(expires_at: params[:direction] == "desc" ? :desc : :asc)
          else
            approvals = approvals.order(created_at: :desc)
          end

          # Pagination
          page = (params[:page] || 1).to_i
          per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
          total_count = approvals.count
          approvals = approvals.offset((page - 1) * per_page).limit(per_page)

          # Stats
          all_approvals = ::Git::PipelineApproval.where(account: current_user.account)
          stats = {
            total: all_approvals.count,
            pending: all_approvals.pending.count,
            approved: all_approvals.approved.count,
            rejected: all_approvals.rejected.count,
            expired: all_approvals.expired.count
          }

          render_success({
            approvals: approvals.map { |a| serialize_approval(a) },
            stats: stats,
            pagination: {
              current_page: page,
              per_page: per_page,
              total_count: total_count,
              total_pages: (total_count.to_f / per_page).ceil
            }
          })
        end

        # GET /api/v1/git/pipeline_approvals/pending
        def pending
          approvals = ::Git::PipelineApproval.where(account: current_user.account)
                                         .active
                                         .includes(:pipeline, :requested_by)
                                         .order(expires_at: :asc)

          render_success({
            approvals: approvals.map { |a| serialize_approval(a) },
            count: approvals.count
          })
        end

        # GET /api/v1/git/pipeline_approvals/:id
        def show
          render_success({ approval: serialize_approval_detail(@approval) })
        end

        # POST /api/v1/git/pipeline_approvals/:id/approve
        def approve
          unless @approval.can_respond?
            return render_error("Cannot approve this request", status: :unprocessable_entity)
          end

          unless @approval.can_user_approve?(current_user)
            return render_error("You are not authorized to approve this request", status: :forbidden)
          end

          @approval.approve!(current_user, params[:comment])

          # Notify the pipeline to continue (if applicable)
          notify_pipeline_approval(@approval)

          render_success({
            approval: serialize_approval_detail(@approval),
            message: "Approval granted successfully"
          })
        end

        # POST /api/v1/git/pipeline_approvals/:id/reject
        def reject
          unless @approval.can_respond?
            return render_error("Cannot reject this request", status: :unprocessable_entity)
          end

          @approval.reject!(current_user, params[:comment])

          # Notify the pipeline of rejection
          notify_pipeline_rejection(@approval)

          render_success({
            approval: serialize_approval_detail(@approval),
            message: "Approval rejected"
          })
        end

        # POST /api/v1/git/pipeline_approvals/:id/cancel
        def cancel
          unless @approval.pending?
            return render_error("Can only cancel pending approvals", status: :unprocessable_entity)
          end

          @approval.cancel!

          render_success({
            approval: serialize_approval_detail(@approval),
            message: "Approval cancelled"
          })
        end

        private

        def set_approval
          @approval = ::Git::PipelineApproval.where(account: current_user.account)
                                         .includes(:pipeline, :requested_by, :responded_by)
                                         .find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_not_found("Approval")
        end

        def validate_permissions
          case action_name.to_sym
          when :index, :pending, :show
            return if current_user.has_permission?("git.approvals.read")
          when :approve, :reject, :cancel
            return if current_user.has_permission?("git.approvals.manage")
          end

          render_forbidden
        end

        def notify_pipeline_approval(approval)
          # In a real implementation, this would notify the CI/CD system
          # to resume the pipeline execution
          Rails.logger.info "Pipeline #{approval.git_pipeline_id} approved at gate #{approval.gate_name}"
        end

        def notify_pipeline_rejection(approval)
          # In a real implementation, this would notify the CI/CD system
          # to fail/stop the pipeline
          Rails.logger.info "Pipeline #{approval.git_pipeline_id} rejected at gate #{approval.gate_name}"
        end

        def serialize_approval(approval)
          {
            id: approval.id,
            gate_name: approval.gate_name,
            environment: approval.environment,
            status: approval.status,
            expires_at: approval.expires_at&.iso8601,
            responded_at: approval.responded_at&.iso8601,
            can_respond: approval.can_respond?,
            can_user_approve: approval.can_user_approve?(current_user),
            pipeline: {
              id: approval.git_pipeline.id,
              name: approval.git_pipeline.name,
              status: approval.git_pipeline.status
            },
            requested_by: approval.requested_by ? {
              id: approval.requested_by.id,
              name: approval.requested_by.name,
              email: approval.requested_by.email
            } : nil,
            created_at: approval.created_at.iso8601
          }
        end

        def serialize_approval_detail(approval)
          serialize_approval(approval).merge(
            description: approval.description,
            response_comment: approval.response_comment,
            metadata: approval.metadata,
            required_approvers: approval.required_approvers,
            time_until_expiry: approval.time_until_expiry,
            response_time: approval.response_time,
            responded_by: approval.responded_by ? {
              id: approval.responded_by.id,
              name: approval.responded_by.name,
              email: approval.responded_by.email
            } : nil,
            repository: approval.git_repository ? {
              id: approval.git_repository.id,
              name: approval.git_repository.name,
              full_name: approval.git_repository.full_name
            } : nil,
            updated_at: approval.updated_at.iso8601
          )
        end
      end
    end
  end
end
