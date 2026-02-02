# frozen_string_literal: true

# Consolidated Workflows Controller - Phase 3 Controller Consolidation
#
# This controller consolidates 12 workflow-related controllers into a single
# RESTful resource controller following the AI Orchestration Redesign pattern.
#
# Consolidates:
# - ::Ai::WorkflowsController (workflow CRUD)
# - ::Ai::WorkflowRunsController (execution management)
# - ::Ai::WorkflowExecutionsController (legacy orchestration)
# - ::Ai::WorkflowSchedulesController (scheduling)
# - ::Ai::WorkflowTriggersController (triggers)
# - ::Ai::WorkflowTemplatesController (templates)
# - ::Ai::WorkflowNodeExecutionsController (node executions)
# - WorkflowVersionsController (versioning)
# - WorkflowAnalyticsController (analytics)
# - WorkflowMarketplaceController (marketplace)
# - WorkflowRecoveryController (recovery)
# - WorkflowDryRunsController (dry runs)
#
# Architecture:
# - Primary resource: Workflows
# - Nested resources: Runs, Versions, Schedules, Node Executions
# - Delegates to Ai::Workflows::* services for business logic
# - Follows RESTful conventions strictly
# - Thin controller, delegates to services
#
module Api
  module V1
    module Ai
      class WorkflowsController < ApplicationController
        include AuditLogging
        include ::Ai::WorkflowSerialization
        include ::Ai::WorkflowGraphManagement
        include ::Ai::WorkflowDownloadHelpers
        include ::Ai::ResourceFiltering
        include ::Ai::WorkflowRunActions

        before_action :set_workflow, only: %i[
          show update destroy
          execute duplicate validate export
          convert_to_template create_from_template convert_to_workflow
        ]
        before_action :set_workflow_run, only: %i[
          run_show run_update run_destroy
          run_cancel run_retry run_pause run_resume
          run_logs run_node_executions run_metrics run_download
          run_process run_broadcast run_check_timeout
        ]
        before_action :validate_permissions

        # =============================================================================
        # WORKFLOWS - PRIMARY RESOURCE CRUD
        # =============================================================================

        # GET /api/v1/ai/workflows
        def index
          workflows = current_user.account.ai_workflows.includes(:creator, :nodes, :edges)
          workflows = apply_workflow_filters(workflows)
          workflows = apply_sorting(workflows, workflow_sort_fields)
          workflows = apply_pagination(workflows)

          render_success({ items: workflows.map { |w| serialize_workflow(w) }, pagination: pagination_data(workflows) })
          log_audit_event("ai.workflows.read", current_user.account)
        end

        # GET /api/v1/ai/workflows/:id
        def show
          render_success(workflow: serialize_workflow_detail(@workflow))
          log_audit_event("ai.workflows.read", @workflow)
        end

        # POST /api/v1/ai/workflows
        def create
          @workflow = ::Ai::Workflow.new(workflow_params)
          @workflow.account = current_user.account
          @workflow.creator = current_user

          ActiveRecord::Base.transaction do
            if @workflow.save
              workflow_data = params[:workflow] || params
              create_workflow_nodes(workflow_data[:nodes]) if workflow_data[:nodes].present?
              create_workflow_edges(workflow_data[:edges]) if workflow_data[:edges].present?

              render_success(workflow: serialize_workflow_detail(@workflow), status: :created)
              log_audit_event("ai.workflows.create", @workflow)
            else
              render_validation_error(@workflow.errors)
            end
          end
        rescue ActiveRecord::RecordInvalid => e
          render_validation_error(e.record.errors)
        end

        # PATCH /api/v1/ai/workflows/:id
        def update
          ActiveRecord::Base.transaction do
            workflow_data = params[:workflow] || params
            update_workflow_nodes(workflow_data[:nodes]) if workflow_data[:nodes].is_a?(Array)
            update_workflow_edges(workflow_data[:edges]) if workflow_data[:edges].is_a?(Array)

            if @workflow.update(workflow_params)
              render_success(workflow: serialize_workflow_detail(@workflow))
              log_audit_event("ai.workflows.update", @workflow)
            else
              render_validation_error(@workflow.errors)
            end
          end
        rescue ActiveRecord::RecordInvalid => e
          render_validation_error(e.record.errors)
        end

        # DELETE /api/v1/ai/workflows/:id
        def destroy
          if @workflow.can_delete?
            @workflow.destroy
            render_success(message: "Workflow deleted successfully")
            log_audit_event("ai.workflows.delete", @workflow)
          else
            render_error("Cannot delete workflow with active runs", status: :unprocessable_content)
          end
        end

        # =============================================================================
        # WORKFLOWS - CUSTOM ACTIONS
        # =============================================================================

        # POST /api/v1/ai/workflows/:id/execute
        def execute
          result = execution_service.execute(
            input_variables: params[:input_variables] || {},
            trigger_type: params[:trigger_type] || "manual",
            trigger_context: params[:trigger_context] || {}
          )

          if result.success?
            render_success(
              { workflow_run: serialize_run(result.run),
                execution_url: api_v1_ai_workflow_workflow_run_url(@workflow.id, result.run.run_id) },
              status: :created
            )
            log_audit_event("ai.workflows.execute", result.run)
          else
            error_type = result.data[:error_type]
            status = error_type == "provider_unavailable" ? :precondition_failed : :unprocessable_content
            render_error(result.error, status: status, details: result.data[:details])
          end
        end

        # POST /api/v1/ai/workflows/:id/duplicate
        def duplicate
          duplicated_workflow = @workflow.duplicate(current_user.account, current_user)

          if duplicated_workflow.persisted?
            render_success({ workflow: serialize_workflow_detail(duplicated_workflow) }, status: :created)
            log_audit_event("ai.workflows.duplicate", duplicated_workflow, original_workflow_id: @workflow.id)
          else
            render_validation_error(duplicated_workflow.errors)
          end
        end

        # GET /api/v1/ai/workflows/:id/validate
        def validate
          validation_result = @workflow.validate_structure
          render_success(validation_result[:valid] ?
            { valid: true, message: "Workflow structure is valid" } :
            { valid: false, errors: validation_result[:errors], warnings: validation_result[:warnings] })
        end

        # GET /api/v1/ai/workflows/:id/export
        def export
          export_data = {
            workflow: serialize_workflow_detail(@workflow),
            nodes: @workflow.nodes.map { |node| serialize_node_detail(node) },
            edges: @workflow.edges.map { |edge| serialize_edge(edge) },
            metadata: { exported_at: Time.current.iso8601, exported_by: current_user.email, platform_version: "1.0.0" }
          }

          render_success(export_data: export_data, filename: "#{@workflow.name.parameterize}-#{Date.current}.json")
          log_audit_event("ai.workflows.export", @workflow)
        end

        # POST /api/v1/ai/workflows/import
        def import
          return render_error("Import data is required", status: :bad_request) if params[:import_data].blank?

          imported_workflow = ::Ai::Workflow.import_from_data(
            params[:import_data], current_user.account, current_user, name_override: params[:name]
          )

          render_success({ workflow: serialize_workflow_detail(imported_workflow) }, status: :created)
          log_audit_event("ai.workflows.import", imported_workflow)
        rescue StandardError => e
          render_error("Import failed: #{e.message}", status: :unprocessable_content)
        end

        # GET /api/v1/ai/workflows/statistics
        def statistics
          workflows = current_user.account.ai_workflows
          runs = ::Ai::WorkflowRun.joins(:workflow).where(ai_workflows: { account_id: current_user.account.id })

          stats = {
            total_workflows: workflows.count,
            active_workflows: workflows.active.count,
            draft_workflows: workflows.draft.count,
            total_runs: runs.count,
            successful_runs: runs.where(status: "completed").count,
            average_execution_time: runs.where.not(completed_at: nil)
                                       .average("EXTRACT(epoch FROM (completed_at - started_at))"),
            recent_activity: workflows.joins(:workflow_runs)
                                     .where(ai_workflow_runs: { created_at: 7.days.ago.. })
                                     .group("ai_workflows.id").count
          }

          render_success(statistics: stats)
        end

        # =============================================================================
        # TEMPLATES
        # =============================================================================

        # GET /api/v1/ai/workflows/templates
        def templates
          templates_scope = ::Ai::Workflow.templates
                                      .where(visibility: %w[public account])
                                      .or(::Ai::Workflow.templates.where(account_id: current_user.account_id))
                                      .includes(:creator, :nodes)

          templates_scope = templates_scope.where(template_category: params[:category]) if params[:category].present?
          templates_scope = templates_scope.search_by_text(params[:search]) if params[:search].present?

          db_templates = templates_scope.order(created_at: :desc).map { |t| serialize_template(t) }
          builtin_templates = build_workflow_templates
          db_ids = db_templates.map { |t| t[:id] }
          all_templates = db_templates + builtin_templates.reject { |t| db_ids.include?(t[:id]) }

          render_success(templates: all_templates)
        end

        # POST /api/v1/ai/workflows/:id/convert_to_template
        def convert_to_template
          result = template_service.convert_to_template(@workflow,
                                                        category: params[:category] || "custom",
                                                        visibility: params[:visibility] || "account")

          if result.success?
            render_success(template: serialize_template(result.workflow), message: "Workflow converted to template successfully")
            log_audit_event("ai.workflows.convert_to_template", @workflow)
          else
            render_error(result.error, status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/workflows/:id/create_from_template
        def create_from_template
          source = ::Ai::Workflow.find(params[:id])

          unless source.is_template? && (source.visibility == "public" || source.account_id == current_user.account_id)
            return render_error("Template not found or not accessible", status: :not_found)
          end

          result = template_service.create_workflow_from_source(source, name: params[:name])

          if result.success?
            render_success({ workflow: serialize_workflow_detail(result.workflow), message: "Workflow created from template successfully" }, status: :created)
            log_audit_event("ai.workflows.create_from_template", result.workflow, source_template_id: source.id)
          else
            render_error(result.error, status: :unprocessable_content)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Template not found", status: :not_found)
        end

        # POST /api/v1/ai/workflows/:id/convert_to_workflow
        def convert_to_workflow
          unless @workflow.is_template?
            return render_error("This workflow is not a template", status: :unprocessable_content)
          end

          @workflow.update!(is_template: false, template_category: nil)
          render_success(workflow: serialize_workflow_detail(@workflow), message: "Template converted to workflow successfully")
          log_audit_event("ai.workflows.convert_to_workflow", @workflow)
        rescue ActiveRecord::RecordInvalid => e
          render_validation_error(e.record.errors)
        end

        private

        # =============================================================================
        # SERVICE ACCESSORS
        # =============================================================================

        def execution_service
          @execution_service ||= ::Ai::Workflows::ExecutionService.new(
            workflow: @workflow, user: current_user, account: current_user.account
          )
        end

        def run_management_service
          @run_management_service ||= ::Ai::Workflows::RunManagementService.new(
            workflow: @workflow_run.workflow, user: current_user || current_worker, account: @workflow_run.account
          )
        end

        def template_service
          @template_service ||= ::Ai::Workflows::TemplateService.new(
            account: current_user.account, user: current_user
          )
        end

        # =============================================================================
        # RESOURCE LOADING
        # =============================================================================

        def set_workflow
          @workflow = current_user.account.ai_workflows
                                  .includes(:creator, :nodes, :edges, :triggers, :variables)
                                  .find(params[:id] || params[:workflow_id])
        rescue ActiveRecord::RecordNotFound
          render_error("Workflow not found", status: :not_found)
        end

        def set_workflow_run
          run_id_param = params[:run_id] || params[:id]

          @workflow_run = if current_user
                           ::Ai::WorkflowRun.joins(:workflow)
                                      .where(ai_workflows: { account_id: current_user.account_id })
                                      .find_by!(run_id: run_id_param)
          elsif current_worker || current_service
                           ::Ai::WorkflowRun.find_by!(run_id: run_id_param)
          else
                           render_unauthorized("Authentication required")
                           nil
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Workflow run not found", status: :not_found)
        end

        def build_runs_scope
          if params[:workflow_id].present?
            workflow = (current_worker || current_service) ?
              ::Ai::Workflow.find(params[:workflow_id]) :
              current_user.account.ai_workflows.find(params[:workflow_id])
            workflow.runs
          elsif current_worker || current_service
            ::Ai::WorkflowRun.joins(:workflow)
          else
            ::Ai::WorkflowRun.joins(:workflow).where(ai_workflows: { account_id: current_user.account_id })
          end
        end

        # =============================================================================
        # AUTHORIZATION
        # =============================================================================

        def validate_permissions
          return if current_worker || current_service

          permission_map = {
            %w[index show statistics templates] => "ai.workflows.read",
            %w[runs_index run_show run_logs run_node_executions run_metrics run_download runs_lookup] => "ai.workflows.read",
            %w[create import duplicate] => "ai.workflows.create",
            %w[update validate run_update run_update_direct run_check_timeout] => "ai.workflows.update",
            %w[destroy run_destroy runs_destroy_all] => "ai.workflows.delete",
            %w[execute run_cancel run_retry run_pause run_resume run_process run_broadcast] => "ai.workflows.execute",
            %w[export] => "ai.workflows.export",
            %w[convert_to_template create_from_template convert_to_workflow] => "ai.workflows.update"
          }

          permission_map.each do |actions, permission|
            return require_permission(permission) if actions.include?(action_name)
          end
        end

        # =============================================================================
        # PARAMETER HANDLING
        # =============================================================================

        def workflow_params
          params.require(:workflow).permit(
            :name, :description, :status, :visibility, :version,
            :is_template, :template_category, :tags, :trigger_types,
            :execution_mode, :retry_policy, :timeout_seconds, :max_execution_time, :cost_limit,
            configuration: {}, metadata: {}, input_schema: {}, output_schema: {}, tags: [], nodes: [], edges: []
          )
        end

        def run_update_params
          params.require(:workflow_run).permit(
            :status, :started_at, :completed_at, :cancelled_at,
            :failed_nodes, :completed_nodes, :total_cost, :duration_ms,
            output_variables: {}, runtime_context: {}, error_details: {}, metadata: {}
          )
        end

        def sanitize_run_update_params(update_params)
          %w[started_at completed_at cancelled_at].each do |field|
            update_params[field] = Time.parse(update_params[field]) if update_params[field].is_a?(String)
          end
          update_params
        end

        # =============================================================================
        # HELPERS
        # =============================================================================

        def workflow_sort_fields
          { "version" => "version", "creator" => "users.name" }
        end

        def delete_runs_in_transaction(runs)
          deleted_count = 0
          deleted_run_ids = []

          ::Ai::WorkflowRun.transaction do
            runs.find_each do |run|
              ::Ai::WorkflowRunLog.where(ai_workflow_run_id: run.id).destroy_all
              ::Ai::WorkflowNodeExecution.where(ai_workflow_run_id: run.id).destroy_all
              if run.destroy
                deleted_count += 1
                deleted_run_ids << run.run_id
              end
            end
          end

          [ deleted_count, deleted_run_ids ]
        end
      end
    end
  end
end
