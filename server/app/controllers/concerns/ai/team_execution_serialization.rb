# frozen_string_literal: true

module Ai
  module TeamExecutionSerialization
    extend ActiveSupport::Concern

    private

    def serialize_execution(execution, detailed: false)
      data = {
        id: execution.id,
        execution_id: execution.execution_id,
        status: execution.status,
        objective: execution.objective,
        tasks_total: execution.tasks_total,
        tasks_completed: execution.tasks_completed,
        tasks_failed: execution.tasks_failed,
        progress_percentage: execution.progress_percentage,
        messages_exchanged: execution.messages_exchanged,
        total_tokens_used: execution.total_tokens_used,
        total_cost_usd: execution.total_cost_usd,
        started_at: execution.started_at,
        completed_at: execution.completed_at,
        duration_ms: execution.duration_ms,
        created_at: execution.created_at
      }

      if detailed
        data[:input_context] = execution.input_context
        data[:output_result] = execution.output_result
        data[:shared_memory] = execution.shared_memory
        data[:termination_reason] = execution.termination_reason
        data[:performance_metrics] = execution.performance_metrics
      end

      data
    end

    def serialize_task(task, detailed: false)
      data = {
        id: task.id,
        task_id: task.task_id,
        description: task.description,
        status: task.status,
        task_type: task.task_type,
        priority: task.priority,
        assigned_role_id: task.assigned_role_id,
        assigned_role_name: task.assigned_role&.role_name,
        assigned_agent_id: task.assigned_agent_id,
        tokens_used: task.tokens_used,
        cost_usd: task.cost_usd,
        retry_count: task.retry_count,
        started_at: task.started_at,
        completed_at: task.completed_at,
        duration_ms: task.duration_ms
      }

      if detailed
        data[:expected_output] = task.expected_output
        data[:input_data] = task.input_data
        data[:output_data] = task.output_data
        data[:tools_used] = task.tools_used
        data[:failure_reason] = task.failure_reason
        data[:parent_task_id] = task.parent_task_id
      end

      data
    end

    def serialize_message(message)
      {
        id: message.id,
        sequence_number: message.sequence_number,
        message_type: message.message_type,
        content: message.content,
        from_role_id: message.from_role_id,
        from_role_name: message.from_role&.role_name,
        to_role_id: message.to_role_id,
        to_role_name: message.to_role&.role_name,
        channel_id: message.channel_id,
        priority: message.priority,
        requires_response: message.requires_response,
        responded_at: message.responded_at,
        created_at: message.created_at,
        structured_content: message.structured_content,
        attachments: message.attachments,
        read_at: message.read_at,
        in_reply_to_id: message.in_reply_to_id,
        reply_count: message.replies.count
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
