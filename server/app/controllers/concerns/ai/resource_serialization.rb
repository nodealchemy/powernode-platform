# frozen_string_literal: true

# Shared serialization methods for AI resources
#
# This concern provides standardized serialization for:
# - Workflows and workflow details
# - Workflow runs and run details
# - Templates and template details
# - Agents and agent details
# - Nodes, edges, triggers, and other workflow components
#
# Usage:
#   class WorkflowsController < ApplicationController
#     include Ai::ResourceSerialization
#
#     def show
#       render_success(workflow: serialize_workflow_detail(@workflow))
#     end
#   end
#
module Ai
  module ResourceSerialization
    extend ActiveSupport::Concern

    # =============================================================================
    # WORKFLOW SERIALIZATION
    # =============================================================================

    # Serialize workflow for list views (compact format)
    # @param workflow [Ai::Workflow] The workflow to serialize
    # @return [Hash] Serialized workflow data
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
        created_by: serialize_user_compact(workflow.creator),
        stats: {
          nodes_count: workflow.nodes.count,
          edges_count: workflow.edges.count,
          runs_count: workflow.runs.count,
          last_run_at: workflow.runs.order(:created_at).last&.created_at&.iso8601
        }
      }
    end

    # Serialize workflow with full details
    # @param workflow [Ai::Workflow] The workflow to serialize
    # @return [Hash] Detailed serialized workflow data
    def serialize_workflow_detail(workflow)
      workflow_runs = workflow.runs
      completed_runs = workflow_runs.where(status: "completed")

      success_rate = workflow_runs.count > 0 ? (completed_runs.count.to_f / workflow_runs.count) : nil
      avg_runtime = completed_runs.where.not(duration_ms: nil).exists? ?
                      completed_runs.where.not(duration_ms: nil).average(:duration_ms).to_f / 1000.0 : nil

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
        created_by: serialize_user_compact(workflow.creator),
        nodes: workflow.nodes.map { |node| serialize_node_detail(node) },
        edges: workflow.edges.map { |edge| serialize_edge(edge) },
        triggers: workflow.workflow_triggers.map { |trigger| serialize_trigger(trigger) },
        variables: workflow.variables.map { |variable| serialize_variable(variable) },
        stats: {
          nodes_count: workflow.nodes.count,
          edges_count: workflow.edges.count,
          runs_count: workflow_runs.count,
          success_rate: success_rate,
          avg_runtime: avg_runtime&.round(2),
          last_run_at: workflow_runs.order(created_at: :desc).first&.created_at&.iso8601
        }
      }
    end

    # Serialize workflow for summary views (minimal format)
    # @param workflow [Ai::Workflow] The workflow to serialize
    # @return [Hash] Summary serialized workflow data
    def serialize_workflow_summary(workflow)
      {
        id: workflow.id,
        name: workflow.name,
        description: workflow.description,
        status: workflow.status,
        version: workflow.version,
        nodes_count: workflow.nodes.count
      }
    end

    # =============================================================================
    # WORKFLOW RUN SERIALIZATION
    # =============================================================================

    # Serialize workflow run for list views
    # @param run [Ai::WorkflowRun] The run to serialize
    # @return [Hash] Serialized run data
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
        workflow: {
          id: run.workflow.id,
          name: run.workflow.name,
          version: run.workflow.version
        },
        triggered_by: run.triggered_by_user ? serialize_user_compact(run.triggered_by_user) : nil
      }
    end

    # Serialize workflow run with full details
    # @param run [Ai::WorkflowRun] The run to serialize
    # @return [Hash] Detailed serialized run data
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
        triggered_by: run.triggered_by_user ? serialize_user_compact(run.triggered_by_user) : nil,
        node_executions: run.node_executions.includes(:node).map { |exec| serialize_node_execution(exec) },
        can_cancel: run.can_cancel?,
        can_retry: run.can_retry?,
        can_pause: run.can_pause?,
        can_resume: run.can_resume?
      }

      result[:error_details] = run.error_details if run.error_details.present? && !run.error_details.empty?
      result
    end

    # =============================================================================
    # TEMPLATE SERIALIZATION
    # =============================================================================

    # Serialize template for list views
    # @param template [Ai::WorkflowTemplate] The template to serialize
    # @return [Hash] Serialized template data
    def serialize_template(template)
      {
        id: template.id,
        name: template.name,
        description: template.description,
        category: template.category,
        difficulty_level: template.difficulty_level,
        version: template.version,
        is_public: template.is_public,
        is_featured: template.is_featured || false,
        license: template.license,
        tags: template.tags || [],
        author: {
          name: template.author_name,
          email: template.author_email
        },
        stats: {
          installations_count: template.installation_count || 0,
          average_rating: template.average_rating || 0,
          ratings_count: template.ratings_count || 0
        },
        created_at: template.created_at.iso8601,
        updated_at: template.updated_at.iso8601
      }
    end

    # Serialize template with full details
    # @param template [Ai::WorkflowTemplate] The template to serialize
    # @return [Hash] Detailed serialized template data
    def serialize_template_detail(template)
      base = serialize_template(template)
      base.merge(
        workflow_definition: template.workflow_definition,
        configuration_schema: template.metadata&.dig("configuration_schema") || {},
        requirements: template.metadata&.dig("requirements") || [],
        documentation_url: template.metadata&.dig("documentation_url"),
        preview_images: template.metadata&.dig("preview_images") || [],
        changelog: template.metadata&.dig("changelog") || [],
        metadata: template.metadata || {},
        source_workflow: template.source_workflow ? serialize_workflow_summary(template.source_workflow) : nil,
        created_by: template.created_by_user ? serialize_user_compact(template.created_by_user) : nil
      )
    end

    # =============================================================================
    # AGENT SERIALIZATION
    # =============================================================================

    # Serialize agent for list views
    # @param agent [Ai::Agent] The agent to serialize
    # @return [Hash] Serialized agent data
    def serialize_agent(agent)
      {
        id: agent.id,
        name: agent.name,
        description: agent.description,
        agent_type: agent.agent_type,
        status: agent.status,
        is_active: agent.is_active,
        version: agent.version,
        tags: agent.metadata&.dig("tags") || [],
        created_at: agent.created_at.iso8601,
        updated_at: agent.updated_at.iso8601,
        stats: {
          executions_count: agent.executions.count,
          success_rate: calculate_agent_success_rate(agent),
          avg_response_time: calculate_agent_avg_response_time(agent)
        }
      }
    end

    # Serialize agent with full details
    # @param agent [Ai::Agent] The agent to serialize
    # @return [Hash] Detailed serialized agent data
    def serialize_agent_detail(agent)
      base = serialize_agent(agent)
      base.merge(
        system_prompt: agent.system_prompt,
        configuration: agent.configuration,
        model_settings: agent.model_settings,
        capabilities: agent.capabilities || [],
        tools: agent.tools || [],
        metadata: agent.metadata || {},
        provider: agent.provider ? {
          id: agent.provider.id,
          name: agent.provider.name,
          provider_type: agent.provider.provider_type
        } : nil,
        created_by: agent.creator ? serialize_user_compact(agent.creator) : nil
      )
    end

    # =============================================================================
    # WORKFLOW COMPONENT SERIALIZATION
    # =============================================================================

    # Serialize workflow node
    # @param node [Ai::WorkflowNode] The node to serialize
    # @return [Hash] Serialized node data
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

    # Serialize workflow edge
    # @param edge [Ai::WorkflowEdge] The edge to serialize
    # @return [Hash] Serialized edge data
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

    # Serialize workflow trigger
    # @param trigger [Ai::WorkflowTrigger] The trigger to serialize
    # @return [Hash] Serialized trigger data
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

    # Serialize workflow variable
    # @param variable [Ai::WorkflowVariable] The variable to serialize
    # @return [Hash] Serialized variable data
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

    # Serialize node execution
    # @param execution [Ai::NodeExecution] The execution to serialize
    # @return [Hash] Serialized execution data
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

    # Serialize execution log
    # @param log [Ai::ExecutionLog] The log to serialize
    # @return [Hash] Serialized log data
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

    # =============================================================================
    # USER SERIALIZATION
    # =============================================================================

    # Serialize user in compact format (for nested objects)
    # @param user [User] The user to serialize
    # @return [Hash] Compact serialized user data
    def serialize_user_compact(user)
      return nil unless user

      {
        id: user.id,
        name: user.full_name,
        email: user.email
      }
    end

    private

    # Calculate agent success rate
    # @param agent [Ai::Agent] The agent
    # @return [Float, nil] Success rate as decimal (0.0-1.0) or nil if no executions
    def calculate_agent_success_rate(agent)
      return nil unless agent.executions.exists?

      total = agent.executions.count
      successful = agent.executions.where(status: "completed").count
      (successful.to_f / total).round(4)
    end

    # Calculate agent average response time in milliseconds
    # @param agent [Ai::Agent] The agent
    # @return [Float, nil] Average response time in ms or nil if no data
    def calculate_agent_avg_response_time(agent)
      completed = agent.executions.where(status: "completed").where.not(duration_ms: nil)
      return nil unless completed.exists?

      completed.average(:duration_ms).to_f.round(2)
    end
  end
end
