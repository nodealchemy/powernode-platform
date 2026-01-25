# frozen_string_literal: true

module Ai
  module WorkflowSerialization
    extend ActiveSupport::Concern

    private

    def serialize_workflow(workflow)
      {
        id: workflow.id,
        name: workflow.name,
        description: workflow.description,
        status: workflow.status,
        visibility: workflow.visibility,
        version: workflow.version,
        is_template: workflow.is_template || false,
        template_category: workflow.template_category,
        tags: workflow.metadata["tags"] || [],
        created_at: workflow.created_at.iso8601,
        updated_at: workflow.updated_at.iso8601,
        created_by: serialize_user(workflow.creator),
        stats: {
          nodes_count: workflow.nodes.count,
          edges_count: workflow.edges.count,
          runs_count: workflow.runs.count,
          last_run_at: workflow.runs.order(:created_at).last&.created_at&.iso8601
        }
      }
    end

    def serialize_workflow_detail(workflow)
      runs = workflow.runs
      completed = runs.where(status: "completed")
      success_rate = runs.count > 0 ? completed.count.to_f / runs.count : nil
      avg_runtime = completed.where.not(duration_ms: nil).average(:duration_ms)&.to_f&./(1000.0)

      {
        id: workflow.id,
        name: workflow.name,
        description: workflow.description,
        status: workflow.status,
        visibility: workflow.visibility,
        version: workflow.version,
        is_template: workflow.is_template || false,
        template_category: workflow.template_category,
        tags: workflow.metadata["tags"] || [],
        trigger_types: workflow.metadata["trigger_types"] || [],
        execution_mode: workflow.configuration["execution_mode"] || "sequential",
        retry_policy: workflow.configuration["retry_policy"] || {},
        timeout_seconds: workflow.configuration["timeout_seconds"] || 300,
        configuration: workflow.configuration,
        metadata: workflow.metadata,
        input_schema: workflow.configuration["input_schema"] || {},
        output_schema: workflow.configuration["output_schema"] || {},
        created_at: workflow.created_at.iso8601,
        updated_at: workflow.updated_at.iso8601,
        created_by: serialize_user(workflow.creator),
        nodes: workflow.nodes.map { |node| serialize_node_detail(node) },
        edges: workflow.edges.map { |edge| serialize_edge(edge) },
        triggers: workflow.workflow_triggers.map { |trigger| serialize_trigger(trigger) },
        variables: workflow.variables.map { |variable| serialize_variable(variable) },
        stats: {
          nodes_count: workflow.nodes.count,
          edges_count: workflow.edges.count,
          runs_count: runs.count,
          success_rate: success_rate,
          avg_runtime: avg_runtime&.round(2),
          last_run_at: runs.order(created_at: :desc).first&.created_at&.iso8601
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
        output_variables: run.output_variables,
        workflow: { id: run.workflow.id, name: run.workflow.name, version: run.workflow.version },
        triggered_by: run.triggered_by_user ? serialize_user(run.triggered_by_user) : nil
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
          id: run.workflow.id,
          name: run.workflow.name,
          description: run.workflow.description,
          version: run.workflow.version
        },
        triggered_by: run.triggered_by_user ? serialize_user(run.triggered_by_user) : nil,
        node_executions: run.node_executions.includes(:node).map { |exec| serialize_node_execution(exec) },
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
        position_x: node.position&.dig("x") || 0,
        position_y: node.position&.dig("y") || 0,
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
        source_handle: edge.source_handle,
        target_handle: edge.target_handle,
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
          node_id: execution.node.node_id,
          node_type: execution.node.node_type,
          name: execution.node.name
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
        node_execution: log.node_execution ? {
          execution_id: log.node_execution.execution_id,
          node_name: log.node_execution.node.name,
          node_type: log.node_execution.node.node_type
        } : nil
      }
    end

    def serialize_template(workflow)
      {
        id: workflow.id,
        name: workflow.name,
        description: workflow.description,
        category: workflow.template_category || "custom",
        execution_mode: workflow.configuration&.dig("execution_mode") || "sequential",
        difficulty: workflow.metadata&.dig("difficulty") || "intermediate",
        estimated_duration: workflow.metadata&.dig("estimated_duration") || "5-15 minutes",
        tags: workflow.metadata&.dig("tags") || [],
        is_database_template: true,
        visibility: workflow.visibility,
        nodes_count: workflow.nodes.count,
        created_at: workflow.created_at.iso8601,
        updated_at: workflow.updated_at.iso8601,
        created_by: workflow.creator ? { id: workflow.creator.id, name: workflow.creator.full_name } : nil
      }
    end

    def serialize_user(user)
      return nil unless user
      { id: user.id, name: user.full_name, email: user.email }
    end
  end
end
