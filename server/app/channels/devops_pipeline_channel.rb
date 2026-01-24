# frozen_string_literal: true

class DevopsPipelineChannel < ApplicationCable::Channel
  def subscribed
    account_id = params[:account_id]
    pipeline_id = params[:pipeline_id]

    if current_user && authorized_for_account?(account_id)
      if pipeline_id.present?
        # Subscribe to specific pipeline updates
        stream_from "devops_pipeline_#{pipeline_id}"
        Rails.logger.info "User #{current_user.id} subscribed to pipeline #{pipeline_id}"
      else
        # Subscribe to all pipelines for account
        stream_from "devops_account_#{account_id}"
        Rails.logger.info "User #{current_user.id} subscribed to all DevOps updates for account #{account_id}"
      end

      transmit({
        type: "subscribed",
        message: "Connected to DevOps pipeline updates",
        pipeline_id: pipeline_id,
        timestamp: Time.current.iso8601
      })
    else
      Rails.logger.warn "Unauthorized DevOps subscription attempt by user #{current_user&.id}"
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "User #{current_user&.id} unsubscribed from DevOps updates"
  end

  class << self
    def broadcast_run_created(run)
      data = {
        type: "run_created",
        pipeline_run: serialize_run(run),
        timestamp: Time.current.iso8601
      }

      broadcast_to_pipeline(run.pipeline, data)
      broadcast_to_account(run.pipeline.account, data)
    end

    def broadcast_run_updated(run)
      data = {
        type: "run_updated",
        pipeline_run: serialize_run(run),
        timestamp: Time.current.iso8601
      }

      broadcast_to_pipeline(run.pipeline, data)
      broadcast_to_account(run.pipeline.account, data)
    end

    def broadcast_run_completed(run)
      data = {
        type: "run_completed",
        pipeline_run: serialize_run(run),
        timestamp: Time.current.iso8601
      }

      broadcast_to_pipeline(run.pipeline, data)
      broadcast_to_account(run.pipeline.account, data)
    end

    def broadcast_step_updated(step_execution)
      run = step_execution.pipeline_run
      data = {
        type: "step_updated",
        pipeline_run_id: run.id,
        step_execution: serialize_step(step_execution),
        progress_percentage: run.progress_percentage,
        timestamp: Time.current.iso8601
      }

      broadcast_to_pipeline(run.pipeline, data)
      broadcast_to_account(run.pipeline.account, data)
    end

    # Broadcast step update with custom event and additional context
    def broadcast_step_update(pipeline, step_execution, event:, **options)
      run = step_execution.pipeline_run
      data = {
        type: "step_update",
        event: event,
        pipeline_run_id: run.id,
        step_execution: serialize_step(step_execution),
        progress_percentage: run.progress_percentage,
        timestamp: Time.current.iso8601
      }.merge(options)

      broadcast_to_pipeline(pipeline, data)
      broadcast_to_account(pipeline.account, data)
    end

    # Broadcast approval status updates for pipeline approval gates
    def broadcast_approval_status(pipeline, status:, gate_name:, **options)
      data = {
        type: "approval_status",
        status: status,
        gate_name: gate_name,
        pipeline_id: pipeline.id,
        pipeline_name: pipeline.name,
        timestamp: Time.current.iso8601
      }.merge(options)

      broadcast_to_pipeline(pipeline, data)
      broadcast_to_account(pipeline.account, data)
    end

    private

    def broadcast_to_pipeline(pipeline, data)
      ActionCable.server.broadcast("devops_pipeline_#{pipeline.id}", data)
    end

    def broadcast_to_account(account, data)
      ActionCable.server.broadcast("devops_account_#{account.id}", data)
    end

    def serialize_run(run)
      {
        id: run.id,
        run_number: run.run_number,
        status: run.status,
        trigger_type: run.trigger_type,
        started_at: run.started_at,
        completed_at: run.completed_at,
        duration_seconds: run.duration_seconds,
        progress_percentage: run.progress_percentage,
        error_message: run.error_message,
        pipeline_id: run.ci_cd_pipeline_id,
        pipeline_name: run.pipeline.name,
        current_step: run.current_step ? {
          id: run.current_step.id,
          name: run.current_step.pipeline_step.name,
          status: run.current_step.status
        } : nil
      }
    end

    def serialize_step(step_execution)
      {
        id: step_execution.id,
        step_name: step_execution.pipeline_step.name,
        step_type: step_execution.pipeline_step.step_type,
        status: step_execution.status,
        started_at: step_execution.started_at,
        completed_at: step_execution.completed_at,
        error_message: step_execution.error_message
      }
    end
  end
end
