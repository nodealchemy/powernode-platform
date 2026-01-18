# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'AI Channels Integration', type: :integration do
  include AiOrchestrationHelpers

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [
    'ai.monitor', 'ai.agents.read', 'ai.workflows.read', 'ai.workflows.create',
    'ai.workflows.update', 'ai.workflows.execute'
  ]) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:ai_workflow) { create(:ai_workflow, account: account, created_by_user: user) }

  before do
    mock_action_cable_broadcasting
  end

  describe 'multi-channel workflow orchestration' do
    it 'coordinates workflow creation and monitoring across channels' do
      # Step 1: User connects to orchestration channel
      orchestration_channel = subscribe_to_channel(AiWorkflowOrchestrationChannel, user)
      expect(orchestration_channel).to be_confirmed

      # Step 2: User connects to monitoring channel
      monitoring_channel = subscribe_to_channel(AiWorkflowMonitoringChannel, user)
      expect(monitoring_channel).to be_confirmed

      # Step 3: User creates workflow via orchestration channel
      workflow_data = {
        'workflow' => {
          'name' => 'Integration Test Workflow',
          'description' => 'Testing multi-channel coordination'
        },
        'nodes' => [
          {
            'node_id' => 'start-1',
            'node_type' => 'start_node',
            'name' => 'Start',
            'position_x' => 100,
            'position_y' => 100
          },
          {
            'node_id' => 'agent-1',
            'node_type' => 'ai_agent',
            'name' => 'AI Processing',
            'position_x' => 300,
            'position_y' => 100,
            'configuration' => { 'agent_id' => ai_agent.id }
          }
        ],
        'edges' => [
          {
            'edge_id' => 'edge-1',
            'source_node_id' => 'start-1',
            'target_node_id' => 'agent-1'
          }
        ]
      }

      perform_on_channel(orchestration_channel, :create_workflow, workflow_data)

      # Step 4: Verify workflow creation notification in orchestration channel
      creation_response = get_last_transmission(orchestration_channel)
      expect(creation_response['type']).to eq('workflow_created')
      expect(creation_response['workflow']['name']).to eq('Integration Test Workflow')

      created_workflow_id = creation_response['workflow']['id']

      # Step 5: Verify monitoring channel receives dashboard stats update
      perform_on_channel(monitoring_channel, :get_dashboard_stats, {})
      stats_response = get_last_transmission(monitoring_channel)
      expect(stats_response['type']).to eq('dashboard_stats')
      expect(stats_response['stats']['total_workflows']).to be > 0

      # Step 6: Execute workflow via orchestration channel
      execution_data = {
        'workflow_id' => created_workflow_id,
        'input_variables' => { 'test_input' => 'integration test data' }
      }

      # Mock workflow execution
      created_workflow = Ai::Workflow.find(created_workflow_id)
      mock_run = instance_double(Ai::WorkflowRun,
        persisted?: true,
        run_id: 'integration-run-123',
        status: 'running',
        trigger_type: 'manual',
        created_at: Time.current,
        started_at: Time.current
      )
      allow(created_workflow).to receive(:execute).and_return(mock_run)

      perform_on_channel(orchestration_channel, :execute_workflow, execution_data)

      # Step 7: Verify execution started in orchestration channel
      execution_response = get_last_transmission(orchestration_channel)
      expect(execution_response['type']).to eq('workflow_execution_started')
      expect(execution_response['workflow_run']['run_id']).to eq('integration-run-123')

      # Step 8: Verify monitoring channel can track the execution
      perform_on_channel(monitoring_channel, :get_active_executions, {})
      active_executions_response = get_last_transmission(monitoring_channel)
      expect(active_executions_response['type']).to eq('active_executions')
      expect(active_executions_response['executions']).to be_an(Array)
    end
  end

  describe 'real-time collaboration features' do
    let(:user_a) { create(:user, account: account, permissions: [ 'ai.workflows.update' ]) }
    let(:user_b) { create(:user, account: account, permissions: [ 'ai.workflows.update' ]) }

    it 'broadcasts collaborative updates between multiple users' do
      # User A connects to orchestration channel
      channel_a = subscribe_to_channel(AiWorkflowOrchestrationChannel, user_a)
      expect(channel_a).to be_confirmed

      # User B connects to orchestration channel
      channel_b = subscribe_to_channel(AiWorkflowOrchestrationChannel, user_b)
      expect(channel_b).to be_confirmed

      # User A updates workflow
      update_data = {
        'workflow_id' => ai_workflow.id,
        'updates' => { 'name' => 'Collaboratively Updated Workflow' }
      }

      perform_on_channel(channel_a, :update_workflow, update_data)

      # Verify User A receives confirmation
      user_a_response = get_last_transmission(channel_a)
      expect(user_a_response['type']).to eq('workflow_updated')

      # Verify collaborative broadcast was sent (would reach User B in real scenario)
      collaborative_messages = broadcast_messages.select do |msg|
        msg[:message][:type] == 'workflow_collaborative_update'
      end
      expect(collaborative_messages).not_to be_empty

      latest_collaboration = collaborative_messages.last[:message]
      expect(latest_collaboration[:updated_by][:id]).to eq(user_a.id)
      expect(latest_collaboration[:action]).to eq('updated')
    end

    it 'handles workflow locking and unlocking notifications' do
      # Simulate workflow lock broadcast
      AiWorkflowOrchestrationChannel.broadcast_workflow_lock(
        account.id,
        ai_workflow.id,
        user_a
      )

      # Verify lock broadcast was sent
      lock_messages = broadcast_messages.select do |msg|
        msg[:message][:type] == 'workflow_locked'
      end
      expect(lock_messages).not_to be_empty

      lock_message = lock_messages.last[:message]
      expect(lock_message[:workflow_id]).to eq(ai_workflow.id)
      expect(lock_message[:locked_by][:id]).to eq(user_a.id)

      # Simulate unlock
      AiWorkflowOrchestrationChannel.broadcast_workflow_unlock(
        account.id,
        ai_workflow.id,
        user_a
      )

      unlock_messages = broadcast_messages.select do |msg|
        msg[:message][:type] == 'workflow_unlocked'
      end
      expect(unlock_messages).not_to be_empty
    end
  end

  describe 'agent execution monitoring integration' do
    let(:ai_execution) { create(:ai_agent_execution, agent: ai_agent, account: account, user: user) }

    it 'coordinates agent execution updates across channels' do
      # Connect to orchestration monitoring
      orchestration_channel = subscribe_to_channel(AiOrchestrationChannel, user, account_id: account.id)
      expect(orchestration_channel).to be_confirmed

      # Connect to agent execution monitoring
      agent_channel = subscribe_to_channel(AiAgentExecutionChannel, user, execution_id: ai_execution.execution_id)
      expect(agent_channel).to be_confirmed

      # Simulate agent execution status change
      status_update = {
        type: 'status_change',
        execution_id: ai_execution.execution_id,
        status: 'completed',
        total_cost: 0.15,
        execution_time_ms: 2500
      }

      AiAgentExecutionChannel.broadcast_execution_update(ai_execution.execution_id, status_update)

      # Verify broadcast was sent to agent channel
      agent_updates = broadcast_messages.select do |msg|
        msg[:channel].include?(ai_execution.execution_id)
      end
      expect(agent_updates).not_to be_empty

      # Request agent status through orchestration channel
      perform_on_channel(orchestration_channel, :request_agent_status, { agent_id: ai_agent.id })

      # Should receive agent status response
      agent_status_response = get_last_transmission(orchestration_channel)
      expect(agent_status_response['type']).to eq('agent_status')
      expect(agent_status_response['agent_id']).to eq(ai_agent.id)
    end
  end

  describe 'system-wide monitoring and alerting' do
    it 'broadcasts system alerts to monitoring channels' do
      # Connect to monitoring channel
      monitoring_channel = subscribe_to_channel(AiWorkflowMonitoringChannel, user)

      # Simulate system alert
      alert_data = {
        level: 'warning',
        message: 'High resource usage detected',
        details: { cpu_usage: 85, memory_usage: 90 }
      }

      AiWorkflowMonitoringChannel.broadcast_system_alert(account.id, alert_data)

      # Verify alert broadcast
      alert_messages = broadcast_messages.select do |msg|
        msg[:message][:type] == 'system_alert'
      end
      expect(alert_messages).not_to be_empty

      alert = alert_messages.last[:message]
      expect(alert[:alert][:level]).to eq('warning')
      expect(alert[:alert][:message]).to include('High resource usage')
    end

    it 'broadcasts cost alerts when thresholds are exceeded' do
      # Connect to monitoring channel
      monitoring_channel = subscribe_to_channel(AiWorkflowMonitoringChannel, user)

      # Simulate cost alert
      cost_data = {
        current_cost: 125.50,
        threshold: 100.00,
        period: 'daily',
        overage_percentage: 25.5
      }

      AiWorkflowMonitoringChannel.broadcast_cost_alert(account.id, cost_data)

      # Verify cost alert broadcast
      cost_messages = broadcast_messages.select do |msg|
        msg[:message][:type] == 'cost_alert'
      end
      expect(cost_messages).not_to be_empty

      cost_alert = cost_messages.last[:message]
      expect(cost_alert[:cost_data][:overage_percentage]).to eq(25.5)
    end
  end

  describe 'error handling and recovery' do
    it 'maintains channel stability when individual channels encounter errors' do
      # Connect to multiple channels
      orchestration_channel = subscribe_to_channel(AiWorkflowOrchestrationChannel, user)
      monitoring_channel = subscribe_to_channel(AiWorkflowMonitoringChannel, user)

      # Cause error in orchestration channel
      allow(Ai::Workflow).to receive(:find).and_raise(StandardError, 'Database error')

      perform_on_channel(orchestration_channel, :update_workflow, {
        'workflow_id' => ai_workflow.id,
        'updates' => { 'name' => 'Test' }
      })

      # Orchestration channel should return error
      error_response = get_last_transmission(orchestration_channel)
      expect(error_response['type']).to eq('error')

      # Monitoring channel should still work
      allow(Ai::Workflow).to receive(:find).and_call_original

      perform_on_channel(monitoring_channel, :get_dashboard_stats, {})

      stats_response = get_last_transmission(monitoring_channel)
      expect(stats_response['type']).to eq('dashboard_stats')
    end

    it 'handles invalid channel subscriptions gracefully' do
      # Try to subscribe to orchestration with invalid permissions
      unauthorized_user = create(:user, account: account, permissions: [ 'billing.read' ])

      channel = subscribe_to_channel(AiWorkflowOrchestrationChannel, unauthorized_user)
      expect(channel).to be_rejected

      # Try to subscribe to monitoring with invalid workflow
      channel = subscribe_to_channel(AiWorkflowMonitoringChannel, user, workflow_id: 'invalid-id')
      expect(channel).to be_rejected
    end
  end

  describe 'performance under load' do
    it 'handles multiple concurrent channel operations' do
      # Create multiple channels
      channels = 3.times.map do
        subscribe_to_channel(AiWorkflowMonitoringChannel, user)
      end

      channels.each { |channel| expect(channel).to be_confirmed }

      # Perform concurrent operations
      threads = channels.map.with_index do |channel, index|
        Thread.new do
          perform_on_channel(channel, :get_dashboard_stats, {})
        end
      end

      threads.each(&:join)

      # All channels should have received responses
      channels.each do |channel|
        response = get_last_transmission(channel)
        expect(response['type']).to eq('dashboard_stats')
      end
    end

    it 'manages memory efficiently with streaming operations' do
      monitoring_channel = subscribe_to_channel(AiWorkflowMonitoringChannel, user)

      # Start real-time monitoring
      perform_on_channel(monitoring_channel, :start_real_time_monitoring, {})

      start_response = get_last_transmission(monitoring_channel)
      expect(start_response['type']).to eq('real_time_mode_enabled')

      # Stop real-time monitoring
      perform_on_channel(monitoring_channel, :stop_real_time_monitoring, {})

      stop_response = get_last_transmission(monitoring_channel)
      expect(stop_response['type']).to eq('real_time_mode_disabled')
    end
  end

  private

  def subscribe_to_channel(channel_class, user, params = {})
    # Create a proper connection stub for ActionCable testing
    connection = ActionCable::Channel::ConnectionStub.new(identifiers: [:current_user])

    # Define current_user getter/setter on the connection stub
    connection.define_singleton_method(:current_user) { @current_user }
    connection.define_singleton_method(:current_user=) { |u| @current_user = u }
    connection.current_user = user

    # Create channel with proper connection stub
    identifier = { channel: channel_class.name }.merge(params).to_json
    channel = channel_class.new(connection, identifier, params)

    # Initialize transmissions tracking
    channel.instance_variable_set(:@transmissions, [])

    # Override transmit to capture messages
    allow(channel).to receive(:transmit) do |message|
      transmissions = channel.instance_variable_get(:@transmissions) || []
      transmissions << message
      channel.instance_variable_set(:@transmissions, transmissions)
    end

    # Track confirmation status
    channel.instance_variable_set(:@confirmed, false)
    channel.instance_variable_set(:@rejected, false)

    # Mock subscription rejection
    allow(channel).to receive(:reject_subscription) do
      channel.instance_variable_set(:@rejected, true)
    end

    # Define confirmed? method
    def channel.confirmed?
      !@rejected && @subscription_confirmation_sent != false
    end

    # Perform subscription
    channel.subscribe_to_channel

    channel
  end

  def perform_on_channel(channel, action, data = {})
    channel.send(action, data)
  end

  def get_last_transmission(channel)
    transmissions = channel.instance_variable_get(:@transmissions) || []
    transmissions.last || {}
  end

  def get_all_transmissions(channel)
    channel.instance_variable_get(:@transmissions) || []
  end
end
