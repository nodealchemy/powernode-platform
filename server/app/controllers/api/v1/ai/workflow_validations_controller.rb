# frozen_string_literal: true

module Api
  module V1
    module Ai
      class WorkflowValidationsController < ApplicationController
        include AuditLogging

        before_action :authenticate_request
        before_action :set_workflow
        before_action :set_validation, only: [:show]
        before_action :require_read_permission, only: [:index, :show, :latest]
        before_action :require_write_permission, only: [:create, :auto_fix, :auto_fix_single, :preview_fixes]

        # GET /api/v1/ai/workflows/:workflow_id/validations
        def index
          validations = @workflow.workflow_validations.order(created_at: :desc)

          # Filter by overall_status if provided
          validations = validations.where(overall_status: params[:status]) if params[:status].present?

          # Filter by health status
          case params[:health]
          when 'healthy'
            validations = validations.healthy
          when 'unhealthy'
            validations = validations.unhealthy
          end

          # Apply time filter
          if params[:time_period].present?
            period = params[:time_period].to_i.hours
            validations = validations.recent(period)
          end

          # Pagination
          page = params[:page]&.to_i || 1
          per_page = params[:per_page]&.to_i || 20
          per_page = [per_page, 100].min # Cap at 100

          paginated_validations = validations.limit(per_page).offset((page - 1) * per_page)

          render_success({
            validations: paginated_validations.map { |v| serialize_validation(v) },
            workflow: {
              id: @workflow.id,
              name: @workflow.name
            },
            pagination: {
              page: page,
              per_page: per_page,
              total: validations.count,
              pages: (validations.count.to_f / per_page).ceil
            },
            meta: {
              valid_count: validations.valid.count,
              invalid_count: validations.invalid.count,
              warning_count: validations.warnings.count
            }
          })

          log_audit_event('ai.workflow_validations.read', @workflow)
        rescue => e
          Rails.logger.error "Failed to list workflow validations: #{e.message}"
          render_error('Failed to list workflow validations', status: :internal_server_error)
        end

        # GET /api/v1/ai/workflows/:workflow_id/validations/:id
        def show
          render_success({
            validation: serialize_validation(@validation, include_details: true),
            workflow: {
              id: @workflow.id,
              name: @workflow.name
            }
          })

          log_audit_event('ai.workflow_validations.read', @validation)
        rescue => e
          Rails.logger.error "Failed to get workflow validation: #{e.message}"
          render_error('Failed to get workflow validation', status: :internal_server_error)
        end

        # POST /api/v1/ai/workflows/:workflow_id/validations
        def create
          # Run validation logic
          validation_result = perform_workflow_validation(@workflow)

          validation = @workflow.workflow_validations.create!(validation_result)

          render_success({
            validation: serialize_validation(validation, include_details: true),
            workflow: {
              id: @workflow.id,
              name: @workflow.name
            },
            message: 'Workflow validation completed successfully'
          }, status: :created)

          log_audit_event('ai.workflow_validations.create', validation)
        rescue ActiveRecord::RecordInvalid => e
          render_validation_error(e.record.errors)
        rescue => e
          Rails.logger.error "Failed to create workflow validation: #{e.message}"
          render_error('Failed to create workflow validation', status: :internal_server_error)
        end

        # GET /api/v1/ai/workflows/:workflow_id/validations/latest
        def latest
          validation = @workflow.workflow_validations.order(created_at: :desc).first

          if validation
            render_success({
              validation: serialize_validation(validation, include_details: true),
              workflow: {
                id: @workflow.id,
                name: @workflow.name
              }
            })
          else
            render_success({
              validation: nil,
              workflow: {
                id: @workflow.id,
                name: @workflow.name
              },
              message: 'No validations found for this workflow'
            })
          end

          log_audit_event('ai.workflow_validations.read', @workflow)
        rescue => e
          Rails.logger.error "Failed to get latest workflow validation: #{e.message}"
          render_error('Failed to get latest workflow validation', status: :internal_server_error)
        end

        # POST /api/v1/ai/workflows/:workflow_id/validations/auto_fix
        def auto_fix
          service = AiWorkflowAutoFixService.new(@workflow)
          result = service.fix_all

          # Create new validation after fixes
          validation_service = AiWorkflowValidationService.new(@workflow.reload)
          validation_result = validation_service.validate
          validation = @workflow.workflow_validations.create!(validation_result)

          render_success({
            fixed_count: result[:fixed_count],
            fixes_applied: result[:fixes_applied],
            errors: result[:errors],
            health_score_improvement: result[:health_score_improvement],
            validation: serialize_validation(validation, include_details: true),
            workflow: {
              id: @workflow.id,
              name: @workflow.name
            },
            message: "Applied #{result[:fixed_count]} automatic fixes"
          })

          log_audit_event('ai.workflow_validations.auto_fix', @workflow, {
            fixed_count: result[:fixed_count],
            fixes: result[:fixes_applied].map { |f| f[:code] }
          })
        rescue => e
          Rails.logger.error "Failed to auto-fix workflow: #{e.message}"
          render_error('Failed to apply automatic fixes', status: :internal_server_error)
        end

        # POST /api/v1/ai/workflows/:workflow_id/validations/auto_fix/:issue_code
        def auto_fix_single
          issue_code = params[:issue_code]
          node_id = params[:node_id]

          service = AiWorkflowAutoFixService.new(@workflow)
          result = service.fix_issue(issue_code, node_id: node_id)

          if result[:success]
            # Create new validation after fix
            validation_service = AiWorkflowValidationService.new(@workflow.reload)
            validation_result = validation_service.validate
            validation = @workflow.workflow_validations.create!(validation_result)

            render_success({
              message: result[:message],
              fixes_applied: result[:fixes_applied],
              validation: serialize_validation(validation, include_details: true),
              workflow: {
                id: @workflow.id,
                name: @workflow.name
              }
            })

            log_audit_event('ai.workflow_validations.auto_fix_single', @workflow, {
              issue_code: issue_code,
              node_id: node_id
            })
          else
            render_error(result[:message], status: :unprocessable_content)
          end
        rescue => e
          Rails.logger.error "Failed to fix issue #{issue_code}: #{e.message}"
          render_error("Failed to fix issue: #{e.message}", status: :internal_server_error)
        end

        # GET /api/v1/ai/workflows/:workflow_id/validations/preview_fixes
        def preview_fixes
          service = AiWorkflowAutoFixService.new(@workflow)
          preview = service.preview_fixes

          render_success({
            fixable_count: preview[:fixable_count],
            planned_fixes: preview[:planned_fixes],
            estimated_health_score_improvement: preview[:estimated_health_score_improvement],
            workflow: {
              id: @workflow.id,
              name: @workflow.name
            }
          })

          log_audit_event('ai.workflow_validations.preview_fixes', @workflow)
        rescue => e
          Rails.logger.error "Failed to preview fixes: #{e.message}"
          render_error('Failed to preview fixes', status: :internal_server_error)
        end

        private

        def set_workflow
          @workflow = current_user.account.ai_workflows.find(params[:workflow_id])
        rescue ActiveRecord::RecordNotFound
          render_error('Workflow not found', status: :not_found)
        end

        def set_validation
          @validation = @workflow.workflow_validations.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error('Validation not found', status: :not_found)
        end

        def require_read_permission
          unless current_user.has_permission?('ai.workflows.read')
            render_error('Insufficient permissions to view workflow validations', status: :forbidden)
          end
        end

        def require_write_permission
          unless current_user.has_permission?('ai.workflows.execute')
            render_error('Insufficient permissions to create workflow validations', status: :forbidden)
          end
        end

        def perform_workflow_validation(workflow)
          # Use comprehensive AiWorkflowValidationService
          service = AiWorkflowValidationService.new(workflow)
          service.validate
        end

        def serialize_validation(validation, include_details: false)
          result = {
            id: validation.id,
            workflow_id: validation.workflow_id,
            overall_status: validation.overall_status,
            health_score: validation.health_score,
            total_nodes: validation.total_nodes,
            validated_nodes: validation.validated_nodes,
            error_count: validation.error_count,
            warning_count: validation.warning_count,
            created_at: validation.created_at
          }

          if include_details
            result.merge!({
              issues: validation.issues,
              summary: validation.summary
            })
          end

          result
        end
      end
    end
  end
end
