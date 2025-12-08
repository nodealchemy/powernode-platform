# frozen_string_literal: true

# Consolidated Workflows Controller - Phase 3 Controller Consolidation
#
# This controller consolidates 12 workflow-related controllers into a single
# RESTful resource controller following the AI Orchestration Redesign pattern.
#
# Consolidates:
# - AiWorkflowsController (workflow CRUD)
# - AiWorkflowRunsController (execution management)
# - AiWorkflowExecutionsController (legacy orchestration)
# - AiWorkflowSchedulesController (scheduling)
# - AiWorkflowTriggersController (triggers)
# - AiWorkflowTemplatesController (templates)
# - AiWorkflowNodeExecutionsController (node executions)
# - WorkflowVersionsController (versioning)
# - WorkflowAnalyticsController (analytics)
# - WorkflowMarketplaceController (marketplace)
# - WorkflowRecoveryController (recovery)
# - WorkflowDryRunsController (dry runs)
#
# Architecture:
# - Primary resource: Workflows
# - Nested resources: Runs, Versions, Schedules, Node Executions
# - Uses base service abstractions from Phase 1
# - Follows RESTful conventions strictly
# - Thin controller, delegates to services
#
module Api
  module V1
    module Ai
      class WorkflowsController < ApplicationController
        include AuditLogging

        # Authentication and resource loading
        before_action :set_workflow, only: [
          :show, :update, :destroy,
          :execute, :duplicate, :validate, :export
        ]

        before_action :set_workflow_run, only: [
          :run_show, :run_update, :run_destroy,
          :run_cancel, :run_retry, :run_pause, :run_resume,
          :run_logs, :run_node_executions, :run_metrics, :run_download,
          :run_process, :run_broadcast
        ]

        before_action :validate_permissions

        # =============================================================================
        # WORKFLOWS - PRIMARY RESOURCE CRUD
        # =============================================================================

        # GET /api/v1/ai/workflows
        def index
          workflows = current_user.account.ai_workflows
                                  .includes(:creator, :ai_workflow_nodes, :ai_workflow_edges)

          workflows = apply_workflow_filters(workflows)
          workflows = apply_sorting(workflows)
          workflows = apply_pagination(workflows)

          render_success({
            items: workflows.map { |w| serialize_workflow(w) },
            pagination: pagination_data(workflows)
          })

          log_audit_event('ai.workflows.read', current_user.account)
        end

        # GET /api/v1/ai/workflows/:id
        def show
          render_success({
            workflow: serialize_workflow_detail(@workflow)
          })

          log_audit_event('ai.workflows.read', @workflow)
        end

        # POST /api/v1/ai/workflows
        def create
          @workflow = AiWorkflow.new(workflow_params)
          @workflow.account = current_user.account
          @workflow.creator = current_user

          ActiveRecord::Base.transaction do
            if @workflow.save
              # Create initial nodes and edges if provided
              # Access nodes/edges from nested workflow params
              workflow_data = params[:workflow] || params
              create_workflow_nodes(workflow_data[:nodes]) if workflow_data[:nodes].present?
              create_workflow_edges(workflow_data[:edges]) if workflow_data[:edges].present?

              render_success({
                workflow: serialize_workflow_detail(@workflow)
              }, status: :created)

              log_audit_event('ai.workflows.create', @workflow)
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
            # Update nodes and edges FIRST before workflow validation
            # Access nodes/edges from nested workflow params
            workflow_data = params[:workflow] || params

            if workflow_data[:nodes].is_a?(Array)
              if workflow_data[:nodes].any?
                update_workflow_nodes(workflow_data[:nodes])
              else
                @workflow.ai_workflow_nodes.destroy_all
              end
            end

            if workflow_data[:edges].is_a?(Array)
              if workflow_data[:edges].any?
                update_workflow_edges(workflow_data[:edges])
              else
                @workflow.ai_workflow_edges.destroy_all
              end
            end

            # Update workflow itself
            if @workflow.update(workflow_params)
              render_success({
                workflow: serialize_workflow_detail(@workflow)
              })

              log_audit_event('ai.workflows.update', @workflow)
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
            render_success({ message: 'Workflow deleted successfully' })
            log_audit_event('ai.workflows.delete', @workflow)
          else
            render_error('Cannot delete workflow with active runs', status: :unprocessable_content)
          end
        end

        # =============================================================================
        # WORKFLOWS - CUSTOM ACTIONS
        # =============================================================================

        # POST /api/v1/ai/workflows/:id/execute
        def execute
          # Validate all providers required by workflow before execution
          ProviderAvailabilityService.validate_workflow_providers!(@workflow)

          # Create workflow run
          run = @workflow.ai_workflow_runs.create!(
            status: 'initializing',
            input_variables: params[:input_variables] || {},
            trigger_type: params[:trigger_type] || 'manual',
            trigger_context: params[:trigger_context] || {},
            triggered_by_user: current_user,
            account: current_user.account
          )

          # Queue execution via worker service
          WorkerJobService.enqueue_ai_workflow_execution(
            run.run_id,
            { 'realtime' => true, 'channel_id' => "ai_workflow_execution_#{run.run_id}" }
          )

          render_success({
            workflow_run: serialize_run(run),
            execution_url: api_v1_ai_workflow_workflow_run_url(@workflow.id, run.run_id)
          }, status: :created)

          log_audit_event('ai.workflows.execute', run)

        rescue ProviderAvailabilityService::ProviderUnavailableError => e
          render_error(e.message, status: :precondition_failed)
        rescue ArgumentError => e
          render_error(e.message, :unprocessable_content, details: build_execution_error_details)
        rescue WorkerJobService::WorkerServiceError => e
          render_error("Failed to start workflow execution: #{e.message}", status: :service_unavailable)
        rescue StandardError => e
          Rails.logger.error "Workflow execution error: #{e.class}: #{e.message}"
          Rails.logger.error e.backtrace.first(10).join("\n")
          render_error("Failed to start workflow execution: #{e.message}", status: :internal_server_error)
        end

        # POST /api/v1/ai/workflows/:id/duplicate
        def duplicate
          duplicated_workflow = @workflow.duplicate(current_user.account, current_user)

          if duplicated_workflow.persisted?
            render_success({
              workflow: serialize_workflow_detail(duplicated_workflow)
            }, status: :created)

            log_audit_event('ai.workflows.duplicate', duplicated_workflow,
              original_workflow_id: @workflow.id
            )
          else
            render_validation_error(duplicated_workflow.errors)
          end
        end

        # GET /api/v1/ai/workflows/:id/validate
        def validate
          validation_result = @workflow.validate_structure

          if validation_result[:valid]
            render_success({
              valid: true,
              message: 'Workflow structure is valid'
            })
          else
            render_success({
              valid: false,
              errors: validation_result[:errors],
              warnings: validation_result[:warnings]
            })
          end
        end

        # GET /api/v1/ai/workflows/:id/export
        def export
          export_data = {
            workflow: serialize_workflow_detail(@workflow),
            nodes: @workflow.ai_workflow_nodes.map { |node| serialize_node_detail(node) },
            edges: @workflow.ai_workflow_edges.map { |edge| serialize_edge(edge) },
            metadata: {
              exported_at: Time.current.iso8601,
              exported_by: current_user.email,
              platform_version: '1.0.0'
            }
          }

          render_success({
            export_data: export_data,
            filename: "#{@workflow.name.parameterize}-#{Date.current}.json"
          })

          log_audit_event('ai.workflows.export', @workflow)
        end

        # POST /api/v1/ai/workflows/import
        def import
          import_data = params[:import_data]

          if import_data.blank?
            return render_error('Import data is required', status: :bad_request)
          end

          begin
            imported_workflow = AiWorkflow.import_from_data(
              import_data,
              current_user.account,
              current_user,
              name_override: params[:name]
            )

            render_success({
              workflow: serialize_workflow_detail(imported_workflow)
            }, status: :created)

            log_audit_event('ai.workflows.import', imported_workflow)

          rescue StandardError => e
            render_error("Import failed: #{e.message}", status: :unprocessable_content)
          end
        end

        # GET /api/v1/ai/workflows/statistics
        def statistics
          workflows = current_user.account.ai_workflows

          stats = {
            total_workflows: workflows.count,
            active_workflows: workflows.active.count,
            draft_workflows: workflows.draft.count,
            total_runs: AiWorkflowRun.joins(:ai_workflow)
                                     .where(ai_workflows: { account_id: current_user.account.id })
                                     .count,
            successful_runs: AiWorkflowRun.joins(:ai_workflow)
                                          .where(ai_workflows: { account_id: current_user.account.id })
                                          .where(status: 'completed')
                                          .count,
            average_execution_time: AiWorkflowRun.joins(:ai_workflow)
                                                 .where(ai_workflows: { account_id: current_user.account.id })
                                                 .where.not(completed_at: nil)
                                                 .average('EXTRACT(epoch FROM (completed_at - started_at))'),
            recent_activity: workflows.joins(:ai_workflow_runs)
                                     .where(ai_workflow_runs: { created_at: 7.days.ago.. })
                                     .group('ai_workflows.id')
                                     .count
          }

          render_success({ statistics: stats })
        end

        # GET /api/v1/ai/workflows/templates
        def templates
          # Workflow templates for common use cases
          templates = build_workflow_templates

          render_success({ templates: templates })
        end

        # =============================================================================
        # WORKFLOW RUNS - NESTED RESOURCE
        # =============================================================================

        # GET /api/v1/ai/workflows/:workflow_id/runs
        def runs_index
          # Determine scope based on route
          runs = if params[:workflow_id].present?
                  # Nested under specific workflow
                  workflow = current_user.account.ai_workflows.find(params[:workflow_id])
                  workflow.ai_workflow_runs
                else
                  # All runs across all workflows
                  AiWorkflowRun.joins(:ai_workflow)
                              .where(ai_workflows: { account_id: current_user.account_id })
                end

          runs = runs.includes(:ai_workflow, :triggered_by_user, :ai_workflow_node_executions)
          runs = apply_run_filters(runs)
          runs = apply_pagination(runs.order(created_at: :desc))

          render_success({
            items: runs.map { |run| serialize_run(run) },
            pagination: pagination_data(runs)
          })
        end

        # GET /api/v1/ai/workflows/:workflow_id/runs/:run_id
        def run_show
          render_success({
            workflow_run: serialize_run_detail(@workflow_run)
          })
        end

        # PATCH /api/v1/ai/workflows/:workflow_id/runs/:run_id
        def run_update
          # Handle workflow run status updates from workers
          update_params = run_update_params

          # Convert datetime strings
          %w[started_at completed_at cancelled_at].each do |field|
            if update_params[field].present? && update_params[field].is_a?(String)
              update_params[field] = Time.parse(update_params[field])
            end
          end

          if @workflow_run.update(update_params)
            render_success({
              workflow_run: serialize_run_detail(@workflow_run),
              message: 'Workflow run updated successfully'
            })
          else
            render_validation_error(@workflow_run.errors)
          end

        rescue ArgumentError => e
          render_error("Invalid parameter format: #{e.message}", status: :bad_request)
        rescue StandardError => e
          render_error("Update failed: #{e.message}", status: :unprocessable_content)
        end

        # DELETE /api/v1/ai/workflows/:workflow_id/runs/:run_id
        def run_destroy
          if @workflow_run.status.in?(['running', 'initializing'])
            return render_error('Cannot delete workflow run while it is running', status: :unprocessable_content)
          end

          workflow_name = @workflow_run.ai_workflow.name
          run_id = @workflow_run.run_id

          # Delete related records
          AiWorkflowRunLog.where(ai_workflow_run_id: @workflow_run.id).destroy_all
          AiWorkflowNodeExecution.where(ai_workflow_run_id: @workflow_run.id).destroy_all

          if @workflow_run.destroy
            render_success({
              message: "Workflow run #{run_id} for '#{workflow_name}' deleted successfully",
              deleted_run_id: run_id
            })

            log_audit_event('ai.workflows.run.delete', @workflow_run)
          else
            render_error('Failed to delete workflow run', status: :unprocessable_content)
          end
        end

        # DELETE /api/v1/ai/workflows/:workflow_id/runs
        def runs_destroy_all
          runs = AiWorkflowRun.joins(:ai_workflow)
                             .where(ai_workflows: { account_id: current_user.account_id })

          runs = apply_run_filters(runs)

          # Check for running runs
          running_runs = runs.where(status: ['running', 'initializing'])
          if running_runs.exists?
            running_count = running_runs.count
            return render_error(
              "Cannot delete #{running_count} workflow run#{'s' if running_count > 1} that are currently running",
              status: :unprocessable_content
            )
          end

          delete_count = runs.count
          return render_success({ message: 'No workflow runs found to delete', deleted_count: 0 }) if delete_count.zero?

          begin
            deleted_count = 0
            deleted_run_ids = []

            AiWorkflowRun.transaction do
              runs.find_each do |run|
                AiWorkflowRunLog.where(ai_workflow_run_id: run.id).destroy_all
                AiWorkflowNodeExecution.where(ai_workflow_run_id: run.id).destroy_all

                if run.destroy
                  deleted_count += 1
                  deleted_run_ids << run.run_id
                end
              end
            end

            render_success({
              message: "Successfully deleted #{deleted_count} workflow run#{'s' if deleted_count != 1}",
              deleted_count: deleted_count,
              deleted_run_ids: deleted_run_ids
            })

            log_audit_event('ai.workflows.runs.bulk_delete', current_user.account, { deleted_count: deleted_count })

          rescue StandardError => e
            Rails.logger.error "Bulk delete workflow runs failed: #{e.message}"
            render_error('Failed to delete workflow runs', status: :internal_server_error)
          end
        end

        # POST /api/v1/ai/workflows/:workflow_id/runs/:run_id/cancel
        def run_cancel
          if @workflow_run.can_cancel?
            result = @workflow_run.cancel!(
              reason: params[:reason] || 'Cancelled by user',
              cancelled_by: current_user
            )

            if result
              render_success({
                workflow_run: serialize_run_detail(@workflow_run),
                message: 'Workflow run cancelled successfully'
              })

              log_audit_event('ai.workflows.run.cancel', @workflow_run)
            else
              render_error('Failed to cancel workflow run', status: :unprocessable_content)
            end
          else
            render_error('Cannot cancel workflow run in current state', status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/workflows/:workflow_id/runs/:run_id/retry
        def run_retry
          if @workflow_run.can_retry?
            new_run = @workflow_run.retry!(
              retry_options: params[:retry_options] || {},
              triggered_by: current_user
            )

            if new_run.persisted?
              render_success({
                original_run: serialize_run(@workflow_run),
                new_run: serialize_run_detail(new_run)
              }, status: :created)

              log_audit_event('ai.workflows.run.retry', new_run,
                metadata: { original_run_id: @workflow_run.run_id }
              )
            else
              render_validation_error(new_run.errors)
            end
          else
            render_error('Cannot retry workflow run in current state', status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/workflows/:workflow_id/runs/:run_id/pause
        def run_pause
          if @workflow_run.can_pause?
            result = @workflow_run.pause!(
              reason: params[:reason] || 'Paused by user',
              paused_by: current_user
            )

            if result
              render_success({
                workflow_run: serialize_run_detail(@workflow_run),
                message: 'Workflow run paused successfully'
              })

              log_audit_event('ai.workflows.run.pause', @workflow_run)
            else
              render_error('Failed to pause workflow run', status: :unprocessable_content)
            end
          else
            render_error('Cannot pause workflow run in current state', status: :unprocessable_content)
          end
        end

        # POST /api/v1/ai/workflows/:workflow_id/runs/:run_id/resume
        def run_resume
          if @workflow_run.can_resume?
            result = @workflow_run.resume!(resumed_by: current_user)

            if result
              render_success({
                workflow_run: serialize_run_detail(@workflow_run),
                message: 'Workflow run resumed successfully'
              })

              log_audit_event('ai.workflows.run.resume', @workflow_run)
            else
              render_error('Failed to resume workflow run', status: :unprocessable_content)
            end
          else
            render_error('Cannot resume workflow run in current state', status: :unprocessable_content)
          end
        end

        # GET /api/v1/ai/workflows/:workflow_id/runs/:run_id/logs
        def run_logs
          logs = @workflow_run.ai_workflow_run_logs
                             .includes(:ai_workflow_node_execution)
                             .order(created_at: :desc)
                             .page(params[:page])
                             .per(params[:per_page] || 50)

          render_success({
            logs: logs.map { |log| serialize_log(log) },
            pagination: pagination_data(logs),
            total_count: logs.total_count
          })
        end

        # GET /api/v1/ai/workflows/:workflow_id/runs/:run_id/node_executions
        def run_node_executions
          executions = @workflow_run.ai_workflow_node_executions
                                   .includes(:ai_workflow_node)
                                   .order(created_at: :asc)
                                   .page(params[:page])
                                   .per(params[:per_page] || 25)

          render_success({
            node_executions: executions.map { |exec| serialize_node_execution(exec) },
            pagination: pagination_data(executions),
            total_count: executions.total_count
          })
        end

        # GET /api/v1/ai/workflows/:workflow_id/runs/:run_id/metrics
        def run_metrics
          metrics = @workflow_run.calculate_execution_metrics

          render_success({
            metrics: metrics
          })
        end

        # GET /api/v1/ai/workflows/:workflow_id/runs/:run_id/download
        def run_download
          download_data = prepare_download_data(@workflow_run)
          filename = "#{@workflow_run.ai_workflow.name.parameterize}-#{@workflow_run.run_id}-#{Date.current}"
          format = params[:format] || 'json'

          case format.downcase
          when 'json'
            # Return as JSON response for API clients
            render_success({
              export_data: download_data,
              filename: "#{filename}.json"
            })
          when 'txt', 'text'
            # Return as file download
            text_content = extract_text_content(download_data)
            send_data text_content,
                      filename: "#{filename}.txt",
                      type: 'text/plain',
                      disposition: 'attachment'
          when 'markdown', 'md'
            # Return as file download
            markdown_content = format_as_markdown(download_data)
            send_data markdown_content,
                      filename: "#{filename}.md",
                      type: 'text/markdown',
                      disposition: 'attachment'
          else
            render_error('Unsupported download format. Use json, txt, or markdown', :bad_request)
          end

          log_audit_event('ai.workflows.run.download', @workflow_run, metadata: { format: format }) unless format == 'json'
        end

        # POST /api/v1/ai/workflows/:workflow_id/runs/:run_id/process
        def run_process
          # Workflow orchestration endpoint called by worker service
          begin
            orchestrator = Mcp::AiWorkflowOrchestrator.new(
              workflow_run: @workflow_run,
              account: @workflow_run.account,
              user: @workflow_run.triggered_by_user
            )

            # Execute returns the updated workflow_run, not a result hash
            workflow_run = orchestrator.execute

            if workflow_run.status == 'completed'
              render_success({
                success: true,
                output_variables: workflow_run.output_variables || {},
                duration_ms: workflow_run.duration_ms || 0,
                total_cost: workflow_run.total_cost || 0
              })
            else
              render_error(
                workflow_run.error_details&.dig('error_message') || 'Workflow processing failed',
                status: :unprocessable_content,
                details: workflow_run.error_details
              )
            end
          rescue StandardError => e
            Rails.logger.error "Workflow processing error: #{e.message}"
            Rails.logger.error e.backtrace.first(10).join("\n")
            render_error("Workflow processing failed: #{e.message}", status: :internal_server_error)
          end
        end

        # POST /api/v1/ai/workflows/:workflow_id/runs/:run_id/broadcast
        def run_broadcast
          # ActionCable broadcast endpoint for worker service
          broadcast_data = params[:broadcast] || {}
          channel_id = params[:channel_id]

          if channel_id.present?
            ActionCable.server.broadcast(channel_id, broadcast_data)
            render_success({ message: 'Broadcast sent successfully' })
          else
            render_error('channel_id is required', status: :bad_request)
          end
        end

        # GET /api/v1/ai/workflows/runs/lookup/:run_id
        def runs_lookup
          # Lookup workflow run by run_id without knowing workflow_id
          # Used by worker service to find workflow_id for nested routes
          run_id = params[:run_id]

          if current_worker || current_service
            # Worker/service context - trusted access across all accounts
            workflow_run = AiWorkflowRun.find_by!(run_id: run_id)
          else
            # User context - scope to user's account
            workflow_run = AiWorkflowRun.joins(:ai_workflow)
                                     .where(ai_workflows: { account_id: current_user.account_id })
                                     .find_by!(run_id: run_id)
          end

          render_success({
            workflow_run: serialize_run_detail(workflow_run).merge({
              workflow_id: workflow_run.ai_workflow_id,
              ai_workflow_id: workflow_run.ai_workflow_id
            })
          })

        rescue ActiveRecord::RecordNotFound
          render_error('Workflow run not found', status: :not_found)
        end

        # POST /api/v1/ai/workflows/:workflow_id/runs/:run_id/check_timeout
        def run_check_timeout
          # Check if workflow run or any node executions have timed out
          timed_out = false
          timeout_reason = nil

          # Check workflow-level timeout
          if @workflow_run.status.in?(['running', 'initializing'])
            workflow = @workflow_run.ai_workflow
            max_execution_time = workflow.configuration&.dig('max_execution_time') || 3600

            if @workflow_run.started_at && (Time.current - @workflow_run.started_at) > max_execution_time
              # Use fail_execution! method to trigger proper broadcasts
              @workflow_run.fail_execution!(
                "Workflow exceeded maximum execution time of #{max_execution_time} seconds",
                {
                  'error_type' => 'workflow_timeout',
                  'max_execution_time' => max_execution_time,
                  'execution_duration' => (Time.current - @workflow_run.started_at).to_i
                }
              )
              timed_out = true
              timeout_reason = "Workflow timeout (#{max_execution_time}s)"
            end
          end

          # Check node-level timeouts
          unless timed_out
            @workflow_run.ai_workflow_node_executions.where(status: 'running').each do |node_exec|
              node = node_exec.ai_workflow_node
              timeout_seconds = node.timeout_seconds || 300

              if node_exec.started_at && (Time.current - node_exec.started_at) > timeout_seconds
                # Use fail_execution! method to trigger proper broadcasts
                node_exec.fail_execution!(
                  "Node execution exceeded timeout of #{timeout_seconds} seconds",
                  {
                    'error_type' => 'node_timeout',
                    'timeout_seconds' => timeout_seconds,
                    'execution_duration' => (Time.current - node_exec.started_at).to_i
                  }
                )

                # Update workflow run progress (failed_nodes counter)
                @workflow_run.update!(
                  failed_nodes: (@workflow_run.failed_nodes || 0) + 1
                )

                # Mark workflow as failed using fail_execution! to trigger broadcasts
                @workflow_run.fail_execution!(
                  "Workflow failed due to node timeout: #{node.name}",
                  {
                    'error_type' => 'node_timeout',
                    'failed_node_id' => node.node_id,
                    'failed_node_name' => node.name,
                    'timeout_seconds' => timeout_seconds
                  }
                )

                timed_out = true
                timeout_reason = "Node timeout: #{node.name} (#{timeout_seconds}s)"
                break
              end
            end
          end

          render_success({
            timed_out: timed_out,
            reason: timeout_reason,
            workflow_run: {
              run_id: @workflow_run.run_id,
              status: @workflow_run.status
            }
          })
        end

        private

        # =============================================================================
        # RESOURCE LOADING
        # =============================================================================

        def set_workflow
          @workflow = current_user.account.ai_workflows
                                  .includes(:creator, :ai_workflow_nodes, :ai_workflow_edges, :ai_workflow_triggers, :ai_workflow_variables)
                                  .find(params[:id] || params[:workflow_id])
        rescue ActiveRecord::RecordNotFound
          render_error('Workflow not found', status: :not_found)
        end

        def set_workflow_run
          # Handle different authentication contexts
          run_id_param = params[:run_id] || params[:id]

          if current_user
            # User context - scope to user's account
            @workflow_run = AiWorkflowRun.joins(:ai_workflow)
                                       .where(ai_workflows: { account_id: current_user.account_id })
                                       .find_by!(run_id: run_id_param)
          elsif current_worker || current_service
            # Worker/service context - trusted access across all accounts
            @workflow_run = AiWorkflowRun.find_by!(run_id: run_id_param)
          else
            return render_unauthorized('Authentication required')
          end
        rescue ActiveRecord::RecordNotFound
          render_error('Workflow run not found', status: :not_found)
        end

        # =============================================================================
        # AUTHORIZATION
        # =============================================================================

        def validate_permissions
          # Skip permission checks for workers and services
          return if current_worker || current_service

          case action_name
          when 'index', 'show', 'statistics', 'templates'
            require_permission('ai.workflows.read')
          when 'runs_index', 'run_show', 'run_logs', 'run_node_executions', 'run_metrics', 'run_download'
            require_permission('ai.workflows.read')
          when 'create', 'import', 'duplicate'
            require_permission('ai.workflows.create')
          when 'update', 'validate'
            require_permission('ai.workflows.update')
          when 'run_update', 'run_check_timeout'
            require_permission('ai.workflows.update')
          when 'destroy', 'run_destroy', 'runs_destroy_all'
            require_permission('ai.workflows.delete')
          when 'execute', 'run_cancel', 'run_retry', 'run_pause', 'run_resume'
            require_permission('ai.workflows.execute')
          when 'export'
            require_permission('ai.workflows.export')
          end
        end

        # =============================================================================
        # PARAMETER HANDLING
        # =============================================================================

        def workflow_params
          params.require(:workflow).permit(
            :name, :description, :status, :visibility, :version,
            :tags, :trigger_types, :execution_mode, :retry_policy,
            :timeout_seconds, :max_execution_time, :cost_limit,
            configuration: {},
            metadata: {},
            input_schema: {},
            output_schema: {},
            tags: [],
            nodes: [],
            edges: []
          )
        end

        def run_update_params
          params.require(:workflow_run).permit(
            :status, :started_at, :completed_at, :cancelled_at,
            :failed_nodes, :completed_nodes, :total_cost, :duration_ms,
            output_variables: {},
            runtime_context: {},
            error_details: {},
            metadata: {}
          )
        end

        # =============================================================================
        # FILTERING & SORTING
        # =============================================================================

        def apply_workflow_filters(workflows)
          workflows = workflows.where(status: params[:status]) if params[:status].present?
          workflows = workflows.where(visibility: params[:visibility]) if params[:visibility].present?
          workflows = workflows.search_by_text(params[:search]) if params[:search].present?
          workflows
        end

        def apply_run_filters(runs)
          runs = runs.where(ai_workflow_id: params[:workflow_id]) if params[:workflow_id].present?
          runs = runs.where(status: params[:status]) if params[:status].present?
          runs = runs.where(triggered_by_user_id: params[:user_id]) if params[:user_id].present?

          if params[:start_date].present?
            runs = runs.where('created_at >= ?', Date.parse(params[:start_date]))
          end

          if params[:end_date].present?
            runs = runs.where('created_at <= ?', Date.parse(params[:end_date]))
          end

          runs
        end

        def apply_sorting(collection)
          sort_by = params[:sort_by] || 'created_at'
          sort_order = params[:sort_order] || 'desc'

          valid_sort_fields = {
            'name' => 'name',
            'created_at' => 'created_at',
            'updated_at' => 'updated_at',
            'status' => 'status',
            'version' => 'version',
            'creator' => 'users.name'
          }

          sort_field = valid_sort_fields[sort_by] || 'created_at'
          sort_direction = %w[asc desc].include?(sort_order) ? sort_order : 'desc'

          if sort_by == 'creator'
            collection = collection.joins(:creator)
            collection.order(Arel.sql("#{sort_field} #{sort_direction}"))
          else
            collection.order("#{sort_field} #{sort_direction}")
          end
        end

        def apply_pagination(collection)
          collection.page(params[:page])
                   .per(params[:per_page] || 25)
        end

        def pagination_data(collection)
          {
            current_page: collection.current_page,
            per_page: collection.limit_value,
            total_pages: collection.total_pages,
            total_count: collection.total_count
          }
        end

        # =============================================================================
        # NODE & EDGE MANAGEMENT
        # =============================================================================

        def create_workflow_nodes(nodes_data)
          nodes_data.each do |node_data|
            @workflow.ai_workflow_nodes.create!(
              node_id: node_data[:node_id],
              node_type: node_data[:node_type],
              name: node_data[:name],
              description: node_data[:description],
              position: node_data[:position] || { x: 0, y: 0 },
              configuration: node_data[:configuration] || {},
              metadata: node_data[:metadata] || {}
            )
          end
        end

        def update_workflow_nodes(nodes_data)
          valid_nodes = nodes_data.select do |node_data|
            node_data[:node_id].present? && node_data[:node_type].present?
          end

          current_node_ids = valid_nodes.map { |n| n[:node_id] }
          @workflow.ai_workflow_nodes.where.not(node_id: current_node_ids).destroy_all

          @workflow.instance_variable_set(:@bulk_updating_nodes, true)

          valid_nodes.each do |node_data|
            node = @workflow.ai_workflow_nodes.find_or_initialize_by(node_id: node_data[:node_id])
            node.assign_attributes(
              node_type: node_data[:node_type],
              name: node_data[:name],
              description: node_data[:description],
              position: node_data[:position] || { x: 0, y: 0 },
              configuration: node_data[:configuration] || {},
              metadata: node_data[:metadata] || {},
              is_start_node: node_data[:is_start_node] || false,
              is_end_node: node_data[:is_end_node] || false
            )
            node.save!
          end

          @workflow.instance_variable_set(:@bulk_updating_nodes, false)
          raise ActiveRecord::RecordInvalid.new(@workflow) unless @workflow.valid?
        end

        def create_workflow_edges(edges_data)
          edges_data.each do |edge_data|
            @workflow.ai_workflow_edges.create!(
              edge_id: edge_data[:edge_id],
              source_node_id: edge_data[:source_node_id],
              target_node_id: edge_data[:target_node_id],
              edge_type: edge_data[:edge_type] || 'default',
              is_conditional: edge_data[:is_conditional] || false,
              condition: edge_data[:condition] || {},
              metadata: edge_data[:metadata] || {}
            )
          end
        end

        def update_workflow_edges(edges_data)
          valid_edges = edges_data.select do |edge_data|
            edge_data[:edge_id].present? &&
              edge_data[:source_node_id].present? &&
              edge_data[:target_node_id].present?
          end

          current_edge_ids = valid_edges.map { |e| e[:edge_id] }
          @workflow.ai_workflow_edges.where.not(edge_id: current_edge_ids).destroy_all

          valid_edges.each do |edge_data|
            edge = @workflow.ai_workflow_edges.find_or_initialize_by(edge_id: edge_data[:edge_id])
            edge.assign_attributes(
              source_node_id: edge_data[:source_node_id],
              target_node_id: edge_data[:target_node_id],
              edge_type: edge_data[:edge_type] || 'default',
              is_conditional: edge_data[:is_conditional] || false,
              condition: edge_data[:condition] || {},
              metadata: edge_data[:metadata] || {}
            )
            edge.save!
          end
        end

        # =============================================================================
        # SERIALIZATION
        # =============================================================================

        def serialize_workflow(workflow)
          {
            id: workflow.id,
            name: workflow.name,
            description: workflow.description,
            status: workflow.status,
            visibility: workflow.visibility,
            version: workflow.version,
            tags: workflow.metadata['tags'] || [],
            created_at: workflow.created_at.iso8601,
            updated_at: workflow.updated_at.iso8601,
            created_by: {
              id: workflow.creator.id,
              name: workflow.creator.full_name,
              email: workflow.creator.email
            },
            stats: {
              nodes_count: workflow.ai_workflow_nodes.count,
              edges_count: workflow.ai_workflow_edges.count,
              runs_count: workflow.ai_workflow_runs.count,
              last_run_at: workflow.ai_workflow_runs.order(:created_at).last&.created_at&.iso8601
            }
          }
        end

        def serialize_workflow_detail(workflow)
          workflow_runs = workflow.ai_workflow_runs
          completed_runs = workflow_runs.where(status: 'completed')

          success_rate = if workflow_runs.count > 0
                          (completed_runs.count.to_f / workflow_runs.count)
                        else
                          nil
                        end

          avg_runtime = if completed_runs.exists?
                         completed_runs.where.not(duration_ms: nil).exists? ?
                           completed_runs.where.not(duration_ms: nil).average(:duration_ms).to_f / 1000.0 :
                           nil
                       else
                         nil
                       end

          {
            id: workflow.id,
            name: workflow.name,
            description: workflow.description,
            status: workflow.status,
            visibility: workflow.visibility,
            version: workflow.version,
            tags: workflow.metadata['tags'] || [],
            trigger_types: workflow.metadata['trigger_types'] || [],
            execution_mode: workflow.configuration['execution_mode'] || 'sequential',
            retry_policy: workflow.configuration['retry_policy'] || {},
            timeout_seconds: workflow.configuration['timeout_seconds'] || 300,
            configuration: workflow.configuration,
            metadata: workflow.metadata,
            input_schema: workflow.configuration['input_schema'] || {},
            output_schema: workflow.configuration['output_schema'] || {},
            created_at: workflow.created_at.iso8601,
            updated_at: workflow.updated_at.iso8601,
            created_by: {
              id: workflow.creator.id,
              name: workflow.creator.full_name,
              email: workflow.creator.email
            },
            nodes: workflow.ai_workflow_nodes.map { |node| serialize_node_detail(node) },
            edges: workflow.ai_workflow_edges.map { |edge| serialize_edge(edge) },
            triggers: workflow.ai_workflow_triggers.map { |trigger| serialize_trigger(trigger) },
            variables: workflow.ai_workflow_variables.map { |variable| serialize_variable(variable) },
            stats: {
              nodes_count: workflow.ai_workflow_nodes.count,
              edges_count: workflow.ai_workflow_edges.count,
              runs_count: workflow_runs.count,
              success_rate: success_rate,
              avg_runtime: avg_runtime&.round(2),
              last_run_at: workflow_runs.order(created_at: :desc).first&.created_at&.iso8601
            }
          }
        end

        def serialize_run(run)
          {
            id: run.id,
            run_id: run.run_id,
            status: run.status,
            trigger_type: run.trigger_type,
            created_at: run.created_at.iso8601,
            started_at: run.started_at&.iso8601,
            completed_at: run.completed_at&.iso8601,
            total_nodes: run.total_nodes,
            completed_nodes: run.completed_nodes,
            failed_nodes: run.failed_nodes,
            cost_usd: run.total_cost.to_f,
            duration_ms: run.execution_time_ms,
            output_variables: run.output_variables,  # Include output_variables for preview modal
            workflow: {
              id: run.ai_workflow.id,
              name: run.ai_workflow.name,
              version: run.ai_workflow.version
            },
            triggered_by: run.triggered_by_user ? {
              id: run.triggered_by_user.id,
              name: run.triggered_by_user.full_name,
              email: run.triggered_by_user.email
            } : nil
          }
        end

        def serialize_run_detail(run)
          result = {
            id: run.id,
            run_id: run.run_id,
            status: run.status,
            trigger_type: run.trigger_type,
            trigger_context: run.trigger_context,
            input_variables: run.input_variables,
            output_variables: run.output_variables,
            runtime_context: run.runtime_context,
            total_cost: run.total_cost,
            execution_time_ms: run.execution_time_ms,
            total_nodes: run.total_nodes,
            completed_nodes: run.completed_nodes,
            failed_nodes: run.failed_nodes,
            created_at: run.created_at.iso8601,
            started_at: run.started_at&.iso8601,
            completed_at: run.completed_at&.iso8601,
            workflow: {
              id: run.ai_workflow.id,
              name: run.ai_workflow.name,
              description: run.ai_workflow.description,
              version: run.ai_workflow.version
            },
            triggered_by: run.triggered_by_user ? {
              id: run.triggered_by_user.id,
              name: run.triggered_by_user.full_name,
              email: run.triggered_by_user.email
            } : nil,
            node_executions: run.ai_workflow_node_executions.includes(:ai_workflow_node).map do |execution|
              serialize_node_execution(execution)
            end,
            can_cancel: run.can_cancel?,
            can_retry: run.can_retry?,
            can_pause: run.can_pause?,
            can_resume: run.can_resume?
          }

          result[:error_details] = run.error_details if run.error_details.present? && !run.error_details.empty?
          result
        end

        def serialize_node_detail(node)
          {
            id: node.id,
            node_id: node.node_id,
            node_type: node.node_type,
            name: node.name,
            description: node.description,
            position_x: node.position&.dig('x') || 0,
            position_y: node.position&.dig('y') || 0,
            configuration: node.configuration,
            metadata: node.metadata,
            created_at: node.created_at.iso8601,
            updated_at: node.updated_at.iso8601
          }
        end

        def serialize_edge(edge)
          {
            id: edge.id,
            edge_id: edge.edge_id,
            source_node_id: edge.source_node_id,
            target_node_id: edge.target_node_id,
            edge_type: edge.edge_type,
            is_conditional: edge.is_conditional,
            condition: edge.condition || {},
            priority: edge.priority,
            metadata: edge.metadata
          }
        end

        def serialize_trigger(trigger)
          {
            id: trigger.id,
            trigger_type: trigger.trigger_type,
            name: trigger.name,
            is_active: trigger.is_active,
            configuration: trigger.configuration,
            created_at: trigger.created_at.iso8601
          }
        end

        def serialize_variable(variable)
          {
            id: variable.id,
            name: variable.name,
            variable_type: variable.variable_type,
            default_value: variable.default_value,
            is_required: variable.is_required,
            description: variable.description
          }
        end

        def serialize_node_execution(execution)
          result = {
            execution_id: execution.execution_id,
            status: execution.status,
            started_at: execution.started_at&.iso8601,
            completed_at: execution.completed_at&.iso8601,
            execution_time_ms: execution.execution_time_ms,
            cost: execution.cost,
            retry_count: execution.retry_count,
            node: {
              node_id: execution.ai_workflow_node.node_id,
              node_type: execution.ai_workflow_node.node_type,
              name: execution.ai_workflow_node.name
            },
            input_data: execution.input_data,
            output_data: execution.output_data,
            metadata: execution.metadata
          }

          result[:error_details] = execution.error_details if execution.error_details.present? && !execution.error_details.empty?
          result
        end

        def serialize_log(log)
          {
            id: log.id,
            level: log.log_level,
            message: log.message,
            event_type: log.event_type,
            context_data: log.context_data,
            metadata: log.metadata,
            created_at: log.created_at.iso8601,
            node_execution: log.ai_workflow_node_execution ? {
              execution_id: log.ai_workflow_node_execution.execution_id,
              node_name: log.ai_workflow_node_execution.ai_workflow_node.name,
              node_type: log.ai_workflow_node_execution.ai_workflow_node.node_type
            } : nil
          }
        end

        # =============================================================================
        # HELPERS
        # =============================================================================

        def build_execution_error_details
          node_count = @workflow.ai_workflow_nodes.count
          start_node_count = @workflow.start_nodes.count
          end_node_count = @workflow.end_nodes.count

          {
            workflow_status: @workflow.status,
            node_count: node_count,
            start_node_count: start_node_count,
            end_node_count: end_node_count,
            can_execute: @workflow.can_execute?,
            recommendations: build_execution_recommendations(node_count, start_node_count, end_node_count)
          }
        end

        def build_execution_recommendations(node_count, start_node_count, end_node_count)
          recommendations = []

          recommendations << "Add at least one node to the workflow" if node_count.zero?
          recommendations << "Mark at least one node as a start node" if start_node_count.zero?
          recommendations << "Mark at least one node as an end node" if end_node_count.zero?
          recommendations << "Set the workflow status to 'active' or 'published'" unless @workflow.active?

          recommendations
        end

        def prepare_download_data(workflow_run)
          {
            workflow_execution: {
              id: workflow_run.id,
              run_id: workflow_run.run_id,
              status: workflow_run.status,
              started_at: workflow_run.started_at,
              completed_at: workflow_run.completed_at,
              duration_ms: workflow_run.execution_time_ms,
              total_cost: workflow_run.total_cost,
              input_variables: workflow_run.input_variables,
              output_variables: workflow_run.output_variables
            },
            workflow: {
              id: workflow_run.ai_workflow.id,
              name: workflow_run.ai_workflow.name,
              description: workflow_run.ai_workflow.description
            },
            node_executions: workflow_run.ai_workflow_node_executions.includes(:ai_workflow_node).map do |node_exec|
              {
                node_name: node_exec.ai_workflow_node.name,
                node_type: node_exec.ai_workflow_node.node_type,
                status: node_exec.status,
                started_at: node_exec.started_at,
                completed_at: node_exec.completed_at,
                duration_ms: node_exec.duration_ms,
                input_data: node_exec.input_data,
                output_data: node_exec.output_data,
                error_details: node_exec.failed? ? node_exec.error_details : nil
              }
            end,
            generated_at: Time.current.iso8601
          }
        end

        def extract_text_content(download_data)
          content_parts = []
          exec_data = download_data[:workflow_execution]

          content_parts << "Workflow: #{download_data[:workflow][:name]}"
          content_parts << "Run ID: #{exec_data[:run_id]}"
          content_parts << "Status: #{exec_data[:status]}"
          content_parts << "Duration: #{(exec_data[:duration_ms] / 1000.0).round(1)} seconds" if exec_data[:duration_ms]
          content_parts << ""

          content_parts.join("\n")
        end

        def format_as_markdown(download_data)
          exec_data = download_data[:workflow_execution]
          output_vars = exec_data[:output_variables] || {}

          # Try to extract markdown content from output variables
          # PRIORITY 1: Check for new structured format with dedicated markdown field
          markdown_content = output_vars['markdown']

          # PRIORITY 2: Check nested End node output structure
          # End node stores: result.final_output.result (where the markdown formatter output lives)
          if markdown_content.blank? && output_vars['result'].is_a?(Hash) && output_vars['result']['final_output'].is_a?(Hash)
            # Extract from End node's final_output
            final_output = output_vars['result']['final_output']
            markdown_content = final_output['markdown'] || final_output['result'] || final_output['output']
          end

          # PRIORITY 3: Check other common field names (legacy formats)
          if markdown_content.blank?
            markdown_content = output_vars['final_markdown'] ||
                              output_vars['markdown_formatter_output']
          end

          # PRIORITY 3: Try to find in node executions (fallback)
          if markdown_content.blank?
            # Look for markdown formatter node or last AI agent node
            node_executions = download_data[:node_executions] || []
            markdown_node = node_executions.find { |n| n[:node_name]&.include?('Markdown') || n[:node_name]&.include?('Format') } ||
                           node_executions.reverse.find { |n| n[:node_type] == 'ai_agent' }

            if markdown_node
              output_data = markdown_node[:output_data] || {}
              markdown_content = extract_content_from_output(output_data)
            end
          end

          # If we found markdown content, return it
          # Otherwise, return a simple summary
          if markdown_content.present? && markdown_content.to_s.length > 50
            # Return the actual markdown content
            markdown_content.to_s
          else
            # Fallback: return workflow summary in markdown format
            markdown_parts = []
            markdown_parts << "# #{download_data[:workflow][:name]}"
            markdown_parts << ""
            markdown_parts << "**Run ID:** `#{exec_data[:run_id]}`"
            markdown_parts << "**Status:** #{exec_data[:status]}"
            markdown_parts << "**Duration:** #{(exec_data[:duration_ms] / 1000.0).round(1)} seconds" if exec_data[:duration_ms]
            markdown_parts << ""
            markdown_parts << "## Workflow completed successfully"
            markdown_parts << ""
            markdown_parts << "No markdown output was found. The workflow may not have produced formatted content."

            markdown_parts.join("\n")
          end
        end

        # Helper method to extract content from various output structures
        def extract_content_from_output(output_data, depth = 0)
          # Prevent infinite recursion
          return nil if depth > 10
          return nil if output_data.blank?

          # Handle string output - return full content without truncation
          return output_data if output_data.is_a?(String)

          # Handle hash output - check common field names
          if output_data.is_a?(Hash)
            # PRIORITY 1: Check for markdown field
            return output_data['markdown'] if output_data['markdown'].is_a?(String)

            # PRIORITY 2: Recurse into nested structures
            return extract_content_from_output(output_data['final_markdown'], depth + 1) if output_data['final_markdown'].present?
            return extract_content_from_output(output_data['markdown_formatter_output'], depth + 1) if output_data['markdown_formatter_output'].present?
            return extract_content_from_output(output_data['output'], depth + 1) if output_data['output'].present?
            return extract_content_from_output(output_data['result'], depth + 1) if output_data['result'].present?
            return extract_content_from_output(output_data['content'], depth + 1) if output_data['content'].present?
            return extract_content_from_output(output_data['text'], depth + 1) if output_data['text'].present?
            # CRITICAL: Recurse into data field (matches frontend fix)
            return extract_content_from_output(output_data['data'], depth + 1) if output_data['data'].present?
            return extract_content_from_output(output_data['response'], depth + 1) if output_data['response'].present?
          end

          # If no content found, return nil
          nil
        end

        def build_workflow_templates
          [
            {
              id: 'content-generation',
              name: 'Content Generation Pipeline',
              description: 'Sequential workflow for research, writing, and review',
              category: 'content',
              execution_mode: 'sequential',
              difficulty: 'beginner',
              estimated_duration: '5-10 minutes',
              tags: ['content', 'research', 'writing']
            },
            {
              id: 'data-analysis',
              name: 'Parallel Data Analysis',
              description: 'Analyze data from multiple perspectives simultaneously',
              category: 'analytics',
              execution_mode: 'parallel',
              difficulty: 'intermediate',
              estimated_duration: '10-15 minutes',
              tags: ['analytics', 'data', 'statistics']
            },
            {
              id: 'conditional-processing',
              name: 'Smart Conditional Workflow',
              description: 'Adaptive workflow with conditional execution',
              category: 'automation',
              execution_mode: 'conditional',
              difficulty: 'advanced',
              estimated_duration: '15-20 minutes',
              tags: ['automation', 'conditional', 'smart-routing']
            }
          ]
        end
      end
    end
  end
end
