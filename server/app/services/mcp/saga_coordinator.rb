# frozen_string_literal: true

module Mcp
  # Saga pattern coordinator for distributed transaction management
  # Handles compensation, rollback, and error recovery in multi-step workflows
  class SagaCoordinator
    attr_reader :workflow_run

    def initialize(workflow_run:)
      @workflow_run = workflow_run
    end

    # Execute workflow with saga pattern
    def execute_with_saga(execution_plan:, compensation_config: {})
      execution_log = []
      compensations = []

      begin
        # Execute each step and register compensation
        execution_plan.each_with_index do |step, index|
          result = execute_step(step, index)
          execution_log << result

          if result[:success]
            # Register compensation for successful step
            compensation = register_compensation(
              step: step,
              result: result,
              config: compensation_config
            )
            compensations << compensation if compensation
          else
            # Step failed - trigger saga rollback
            Rails.logger.error "Saga step #{index} failed: #{result[:error]}"
            rollback_saga(compensations.reverse)
            return {
              success: false,
              error: "Saga failed at step #{index}",
              failed_step: step,
              execution_log: execution_log,
              compensations_executed: compensations.length
            }
          end
        end

        # All steps succeeded
        {
          success: true,
          execution_log: execution_log,
          compensations_registered: compensations.length
        }

      rescue StandardError => e
        Rails.logger.error "Saga execution error: #{e.message}"
        rollback_saga(compensations.reverse)

        {
          success: false,
          error: e.message,
          execution_log: execution_log,
          compensations_executed: compensations.length
        }
      end
    end

    # Register compensation for a step
    def register_compensation(step:, result:, config:)
      return nil unless step[:compensatable]

      compensation_action = build_compensation_action(step, result)

      AiWorkflowCompensation.create!(
        ai_workflow_run: workflow_run,
        ai_workflow_node_execution_id: result[:node_execution_id],
        compensation_type: step[:compensation_type] || 'rollback',
        trigger_reason: 'step_execution',
        status: 'pending',
        original_action: {
          step_name: step[:name],
          step_type: step[:type],
          result: result[:output]
        },
        compensation_action: compensation_action,
        max_retries: config[:max_retries] || 3,
        metadata: {
          step_index: step[:index],
          registered_at: Time.current.iso8601
        }
      )
    end

    # Rollback saga by executing compensations
    def rollback_saga(compensations)
      Rails.logger.info "Starting saga rollback: #{compensations.length} compensations"

      results = []

      compensations.each_with_index do |compensation, index|
        result = compensation.execute!

        results << {
          compensation_id: compensation.compensation_id,
          success: result,
          index: index
        }

        unless result
          Rails.logger.error "Compensation #{index} failed: #{compensation.compensation_id}"

          # Retry if possible
          if compensation.can_retry?
            Rails.logger.info "Retrying compensation #{compensation.compensation_id}"
            retry_result = compensation.retry!
            results.last[:retry_success] = retry_result
          end
        end
      end

      {
        total_compensations: compensations.length,
        successful: results.count { |r| r[:success] },
        failed: results.count { |r| !r[:success] },
        details: results
      }
    end

    # Create saga-aware workflow execution plan
    def create_saga_execution_plan(workflow:, input_data:)
      nodes = workflow.ai_workflow_nodes.order(:created_at)

      nodes.map.with_index do |node, index|
        {
          index: index,
          name: node.name,
          node_id: node.node_id,
          type: node.node_type,
          compensatable: compensatable_node?(node),
          compensation_type: determine_compensation_type(node),
          input_data: build_node_input(node, input_data, index),
          config: node.configuration
        }
      end
    end

    # Two-phase commit coordination
    def execute_two_phase_commit(participants:)
      # Phase 1: Prepare
      prepare_results = prepare_phase(participants)

      if prepare_results[:all_prepared]
        # Phase 2: Commit
        commit_results = commit_phase(participants)

        {
          success: commit_results[:all_committed],
          phase: 'commit',
          results: commit_results
        }
      else
        # Abort if any participant failed to prepare
        abort_results = abort_phase(participants)

        {
          success: false,
          phase: 'prepare_failed',
          results: {
            prepare: prepare_results,
            abort: abort_results
          }
        }
      end
    end

    # Get saga execution status
    def saga_status
      compensations = workflow_run.ai_workflow_compensations

      {
        total_compensations: compensations.count,
        by_status: compensations.group(:status).count,
        by_type: compensations.group(:compensation_type).count,
        pending: compensations.pending.count,
        completed: compensations.completed.count,
        failed: compensations.failed.count,
        retryable: compensations.retryable.count
      }
    end

    # Retry all failed compensations
    def retry_failed_compensations
      failed_comps = workflow_run.ai_workflow_compensations.retryable

      results = failed_comps.map do |comp|
        {
          compensation_id: comp.compensation_id,
          success: comp.retry!
        }
      end

      {
        attempted: results.length,
        successful: results.count { |r| r[:success] },
        failed: results.count { |r| !r[:success] },
        results: results
      }
    end

    # Manual compensation trigger
    def trigger_manual_compensation(node_execution:, reason:, compensation_action:)
      AiWorkflowCompensation.create!(
        ai_workflow_run: workflow_run,
        ai_workflow_node_execution: node_execution,
        compensation_type: 'compensate',
        trigger_reason: "manual: #{reason}",
        status: 'pending',
        original_action: {
          node_id: node_execution.node_id,
          output: node_execution.output_data
        },
        compensation_action: compensation_action,
        metadata: {
          manual_trigger: true,
          triggered_at: Time.current.iso8601
        }
      ).tap(&:execute!)
    end

    # Distributed saga coordination
    def coordinate_distributed_saga(saga_id:, participants:)
      saga_state = {
        saga_id: saga_id,
        participants: participants.map { |p| { id: p[:id], status: 'pending' } },
        started_at: Time.current.iso8601
      }

      # Execute saga steps across participants
      participants.each do |participant|
        result = execute_participant_step(participant)

        update_participant_status(saga_state, participant[:id], result[:success] ? 'completed' : 'failed')

        unless result[:success]
          # Trigger distributed rollback
          rollback_distributed_saga(saga_state)
          return {
            success: false,
            saga_id: saga_id,
            failed_participant: participant[:id],
            saga_state: saga_state
          }
        end
      end

      {
        success: true,
        saga_id: saga_id,
        saga_state: saga_state
      }
    end

    private

    # Execute a single saga step
    def execute_step(step, index)
      node_execution = workflow_run.ai_workflow_node_executions.create!(
        ai_workflow_node_id: step[:node_id],
        node_id: step[:node_id],
        node_type: step[:type],
        input_data: step[:input_data],
        status: 'running',
        metadata: { saga_step: true, step_index: index }
      )

      # Simulate step execution (in real implementation, would call orchestrator)
      result = {
        success: true,
        output: { step: step[:name], completed: true },
        node_execution_id: node_execution.id
      }

      node_execution.update!(
        status: 'completed',
        output_data: result[:output]
      )

      result
    rescue StandardError => e
      node_execution&.update!(status: 'failed', error_details: { error: e.message })
      { success: false, error: e.message, node_execution_id: node_execution&.id }
    end

    # Build compensation action based on step type
    def build_compensation_action(step, result)
      case step[:type]
      when 'ai_agent'
        build_agent_compensation(step, result)
      when 'api_call'
        build_api_compensation(step, result)
      when 'webhook'
        build_webhook_compensation(step, result)
      else
        build_generic_compensation(step, result)
      end
    end

    # Build agent compensation
    def build_agent_compensation(step, result)
      {
        type: 'agent',
        rollback_action: {
          type: 'message',
          recipient: step[:config]['agent_id'],
          message: {
            action: 'rollback',
            original_result: result[:output]
          }
        }
      }
    end

    # Build API compensation
    def build_api_compensation(step, result)
      {
        type: 'api',
        rollback_action: {
          type: 'api_call',
          url: step[:config]['rollback_url'] || step[:config]['url'],
          method: 'DELETE',
          payload: { rollback: true, original_result: result[:output] }
        }
      }
    end

    # Build webhook compensation
    def build_webhook_compensation(step, result)
      {
        type: 'webhook',
        rollback_action: {
          type: 'api_call',
          url: step[:config]['url'],
          method: 'POST',
          payload: { action: 'rollback', data: result[:output] }
        }
      }
    end

    # Build generic compensation
    def build_generic_compensation(step, result)
      {
        type: 'generic',
        rollback_action: {
          type: 'revert',
          previous_state: step[:input_data]
        }
      }
    end

    # Check if node is compensatable
    def compensatable_node?(node)
      %w[ai_agent api_call webhook transform].include?(node.node_type)
    end

    # Determine compensation type for node
    def determine_compensation_type(node)
      case node.node_type
      when 'api_call', 'webhook'
        'rollback'
      when 'ai_agent'
        'compensate'
      when 'transform'
        'revert'
      else
        'undo'
      end
    end

    # Build node input data
    def build_node_input(node, workflow_input, index)
      workflow_input.merge(
        node_index: index,
        node_config: node.configuration
      )
    end

    # Two-phase commit: Prepare phase
    def prepare_phase(participants)
      results = participants.map do |p|
        { id: p[:id], prepared: true } # Simulate prepare
      end

      {
        all_prepared: results.all? { |r| r[:prepared] },
        results: results
      }
    end

    # Two-phase commit: Commit phase
    def commit_phase(participants)
      results = participants.map do |p|
        { id: p[:id], committed: true } # Simulate commit
      end

      {
        all_committed: results.all? { |r| r[:committed] },
        results: results
      }
    end

    # Two-phase commit: Abort phase
    def abort_phase(participants)
      results = participants.map do |p|
        { id: p[:id], aborted: true } # Simulate abort
      end

      {
        all_aborted: results.all? { |r| r[:aborted] },
        results: results
      }
    end

    # Execute participant step in distributed saga
    def execute_participant_step(participant)
      # Simulate participant execution
      { success: true, participant_id: participant[:id] }
    end

    # Update participant status in saga state
    def update_participant_status(saga_state, participant_id, status)
      participant = saga_state[:participants].find { |p| p[:id] == participant_id }
      participant[:status] = status if participant
    end

    # Rollback distributed saga
    def rollback_distributed_saga(saga_state)
      completed_participants = saga_state[:participants].select { |p| p[:status] == 'completed' }

      completed_participants.reverse.each do |participant|
        # Trigger rollback for participant
        update_participant_status(saga_state, participant[:id], 'rolled_back')
      end
    end
  end
end
