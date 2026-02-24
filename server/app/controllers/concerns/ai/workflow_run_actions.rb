# frozen_string_literal: true

# Actions for managing workflow runs
#
# Provides CRUD and lifecycle actions for runs nested under workflows:
# - List, show, update, destroy runs
# - Run lifecycle: cancel, retry, pause, resume
# - Run logs and metrics
# - Run download and processing
#
# Requires:
# - @workflow_run to be set for single-run actions (use before_action :set_workflow_run)
# - run_management_service method to be defined
# - WorkflowSerialization concern for serialization methods
# - ResourceFiltering concern for apply_run_filters and apply_pagination
#
module Ai
  module WorkflowRunActions
    extend ActiveSupport::Concern

    # =============================================================================
    # RUN CRUD
    # =============================================================================

    # GET /api/v1/ai/workflows/:workflow_id/runs
    def runs_index
      runs = build_runs_scope.includes(:workflow, :triggered_by_user, :node_executions)
      runs = apply_run_filters(runs)
      runs = apply_pagination(runs.order(created_at: :desc))

      render_success(
        workflow_runs: runs.map { |run| serialize_run(run) },
        items: runs.map { |run| serialize_run(run) },
        pagination: pagination_data(runs)
      )
    end

    # GET /api/v1/ai/workflows/:workflow_id/runs/:run_id
    def run_show
      render_success(workflow_run: serialize_run_detail(@workflow_run))
    end

    # PATCH /api/v1/ai/workflows/:workflow_id/runs/:run_id
    def run_update
      update_params = sanitize_run_update_params(run_update_params)

      if @workflow_run.update(update_params)
        render_success(workflow_run: serialize_run_detail(@workflow_run), message: "Workflow run updated successfully")
      else
        render_validation_error(@workflow_run.errors)
      end
    rescue ArgumentError => e
      render_error("Invalid parameter format: #{e.message}", status: :bad_request)
    end

    # PATCH /api/v1/ai/workflow_runs/:run_id
    def run_update_direct
      unless current_worker
        return render_error("Unauthorized: this endpoint is for worker services only", status: :forbidden)
      end

      workflow_run = ::Ai::WorkflowRun.find_by!(run_id: params[:run_id])
      update_params = sanitize_run_update_params(run_update_params)

      if workflow_run.update(update_params)
        render_success(workflow_run: serialize_run_detail(workflow_run), message: "Workflow run updated successfully")
      else
        render_validation_error(workflow_run.errors)
      end
    rescue ActiveRecord::RecordNotFound
      render_error("Workflow run not found", status: :not_found)
    rescue ArgumentError => e
      render_error("Invalid parameter format: #{e.message}", status: :bad_request)
    end

    # DELETE /api/v1/ai/workflows/:workflow_id/runs/:run_id
    def run_destroy
      result = run_management_service.delete_run(@workflow_run)

      if result.success?
        render_success(message: "Workflow run #{@workflow_run.run_id} deleted successfully", deleted_run_id: @workflow_run.run_id)
        log_audit_event("ai.workflows.run.delete", @workflow_run)
      else
        render_error(result.error, status: :unprocessable_content)
      end
    end

    # DELETE /api/v1/ai/workflows/:workflow_id/runs
    def runs_destroy_all
      runs = ::Ai::WorkflowRun.joins(:workflow).where(ai_workflows: { account_id: current_user.account_id })
      runs = apply_run_filters(runs)

      running_runs = runs.where(status: %w[running initializing])
      return render_error("Cannot delete #{running_runs.count} running workflow run(s)", status: :unprocessable_content) if running_runs.exists?
      return render_success(message: "No workflow runs found to delete", deleted_count: 0) if runs.count.zero?

      deleted_count, deleted_run_ids = delete_runs_in_transaction(runs)

      render_success(message: "Successfully deleted #{deleted_count} workflow run(s)", deleted_count: deleted_count, deleted_run_ids: deleted_run_ids)
      log_audit_event("ai.workflows.runs.bulk_delete", current_user.account, deleted_count: deleted_count)
    rescue StandardError => e
      Rails.logger.error "Bulk delete workflow runs failed: #{e.message}"
      render_error("Failed to delete workflow runs", status: :internal_server_error)
    end

    # =============================================================================
    # RUN LIFECYCLE
    # =============================================================================

    # POST /api/v1/ai/workflows/:workflow_id/runs/:run_id/cancel
    def run_cancel
      result = run_management_service.cancel_run(@workflow_run, reason: params[:reason])

      if result.success?
        render_success(workflow_run: serialize_run_detail(@workflow_run), message: "Workflow run cancelled successfully")
        log_audit_event("ai.workflows.run.cancel", @workflow_run)
      else
        render_error(result.error, status: :unprocessable_content)
      end
    end

    # POST /api/v1/ai/workflows/:workflow_id/runs/:run_id/retry
    def run_retry
      result = run_management_service.retry_run(@workflow_run)

      if result.success?
        render_success({ original_run: serialize_run(@workflow_run), new_run: serialize_run_detail(result.run) }, status: :created)
        log_audit_event("ai.workflows.run.retry", result.run, metadata: { original_run_id: @workflow_run.run_id })
      else
        render_error(result.error, status: :unprocessable_content)
      end
    end

    # POST /api/v1/ai/workflows/:workflow_id/runs/:run_id/pause
    def run_pause
      result = run_management_service.pause_run(@workflow_run)

      if result.success?
        render_success(workflow_run: serialize_run_detail(@workflow_run), message: "Workflow run paused successfully")
        log_audit_event("ai.workflows.run.pause", @workflow_run)
      else
        render_error(result.error, status: :unprocessable_content)
      end
    end

    # POST /api/v1/ai/workflows/:workflow_id/runs/:run_id/resume
    def run_resume
      result = run_management_service.resume_run(@workflow_run)

      if result.success?
        render_success(workflow_run: serialize_run_detail(@workflow_run), message: "Workflow run resumed successfully")
        log_audit_event("ai.workflows.run.resume", @workflow_run)
      else
        render_error(result.error, status: :unprocessable_content)
      end
    end

    # =============================================================================
    # RUN LOGS & METRICS
    # =============================================================================

    # GET /api/v1/ai/workflows/:workflow_id/runs/:run_id/logs
    def run_logs
      logs = @workflow_run.run_logs.includes(:node_execution).order(created_at: :desc)
                          .page(params[:page]).per(params[:per_page] || 50)

      render_success({ logs: logs.map { |log| serialize_log(log) }, pagination: pagination_data(logs), total_count: logs.total_count })
    end

    # GET /api/v1/ai/workflows/:workflow_id/runs/:run_id/node_executions
    def run_node_executions
      executions = @workflow_run.node_executions.includes(:node).order(created_at: :asc)
                                .page(params[:page]).per(params[:per_page] || 25)

      render_success(node_executions: executions.map { |exec| serialize_node_execution(exec) },
                    pagination: pagination_data(executions), total_count: executions.total_count)
    end

    # GET /api/v1/ai/workflows/:workflow_id/runs/:run_id/metrics
    def run_metrics
      render_success(metrics: @workflow_run.calculate_execution_metrics)
    end

    # =============================================================================
    # RUN DOWNLOAD & PROCESSING
    # =============================================================================

    # GET /api/v1/ai/workflows/:workflow_id/runs/:run_id/download
    def run_download
      download_data = prepare_download_data(@workflow_run)
      filename = "#{@workflow_run.workflow.name.parameterize}-#{@workflow_run.run_id}-#{Date.current}"
      format = params[:format] || "json"

      case format.downcase
      when "json"
        render_success(export_data: download_data, filename: "#{filename}.json")
      when "txt", "text"
        send_data extract_text_content(download_data), filename: "#{filename}.txt", type: "text/plain", disposition: "attachment"
        log_audit_event("ai.workflows.run.download", @workflow_run, metadata: { format: format })
      when "markdown", "md"
        send_data format_as_markdown(download_data), filename: "#{filename}.md", type: "text/markdown", disposition: "attachment"
        log_audit_event("ai.workflows.run.download", @workflow_run, metadata: { format: format })
      else
        render_error("Unsupported download format. Use json, txt, or markdown", :bad_request)
      end
    end

    # POST /api/v1/ai/workflows/:workflow_id/runs/:run_id/process
    def run_process
      orchestrator = ::Mcp::AiWorkflowOrchestrator.new(
        workflow_run: @workflow_run, account: @workflow_run.account, user: @workflow_run.triggered_by_user
      )
      workflow_run = orchestrator.execute

      if workflow_run.status == "completed"
        render_success(success: true, output_variables: workflow_run.output_variables || {},
                      duration_ms: workflow_run.duration_ms || 0, total_cost: workflow_run.total_cost || 0)
      else
        render_error(workflow_run.error_details&.dig("error_message") || "Workflow processing failed",
                    status: :unprocessable_content, details: workflow_run.error_details)
      end
    rescue StandardError => e
      render_internal_error("Workflow processing failed", exception: e)
    end

    # POST /api/v1/ai/workflows/:workflow_id/runs/:run_id/broadcast
    def run_broadcast
      channel_id = params[:channel_id]
      return render_error("channel_id is required", status: :bad_request) if channel_id.blank?

      ActionCable.server.broadcast(channel_id, params[:broadcast] || {})
      render_success(message: "Broadcast sent successfully")
    end

    # GET /api/v1/ai/workflows/runs/lookup/:run_id
    def runs_lookup
      workflow_run = if current_worker
                      ::Ai::WorkflowRun.find_by!(run_id: params[:run_id])
      else
                      ::Ai::WorkflowRun.joins(:workflow)
                                 .where(ai_workflows: { account_id: current_user.account_id })
                                 .find_by!(run_id: params[:run_id])
      end

      render_success(workflow_run: serialize_run_detail(workflow_run).merge(
        workflow_id: workflow_run.ai_workflow_id, ai_workflow_id: workflow_run.ai_workflow_id
      ))
    rescue ActiveRecord::RecordNotFound
      render_error("Workflow run not found", status: :not_found)
    end

    # POST /api/v1/ai/workflows/:workflow_id/runs/:run_id/check_timeout
    def run_check_timeout
      result = run_management_service.check_timeout(@workflow_run)

      render_success(
        timed_out: result.data[:timed_out] || false,
        reason: result.data[:reason],
        workflow_run: { run_id: @workflow_run.run_id, status: @workflow_run.status }
      )
    end

    private

    # Build base scope for runs based on authentication type
    def build_runs_scope
      if params[:workflow_id].present?
        workflow = current_user.account.ai_workflows.find(params[:workflow_id])
        workflow.runs
      elsif current_worker
        ::Ai::WorkflowRun.all
      else
        ::Ai::WorkflowRun.joins(:workflow).where(ai_workflows: { account_id: current_user.account_id })
      end
    end

    # Run update parameters
    def run_update_params
      params.require(:workflow_run).permit(
        :status, :started_at, :completed_at, :total_cost, :execution_time_ms,
        :total_nodes, :completed_nodes, :failed_nodes,
        input_variables: {}, output_variables: {}, runtime_context: {}, error_details: {}
      )
    end

    # Sanitize run update parameters (convert string timestamps)
    def sanitize_run_update_params(update_params)
      sanitized = update_params.to_h
      %w[started_at completed_at].each do |field|
        next unless sanitized[field].is_a?(String)
        sanitized[field] = Time.parse(sanitized[field])
      end
      sanitized
    end

    # Delete runs in a transaction
    def delete_runs_in_transaction(runs)
      deleted_count = 0
      deleted_run_ids = []

      ActiveRecord::Base.transaction do
        runs.find_each do |run|
          deleted_run_ids << run.run_id
          run.destroy!
          deleted_count += 1
        end
      end

      [ deleted_count, deleted_run_ids ]
    end
  end
end
