#!/usr/bin/env ruby
# frozen_string_literal: true

workflow = AiWorkflow.first
orchestrator = AiAgent.find_by(slug: 'workflow-orchestrator')

# Update workflow to use the orchestrator
workflow.update!(
  configuration: workflow.configuration.merge({
    'orchestrator' => {
      'agent_id' => orchestrator.id,
      'enabled' => true,
      'coordination_strategy' => 'sequential_with_dependencies',
      'error_handling' => {
        'retry_failed_nodes' => true,
        'create_checkpoints' => true,
        'max_retries' => 3
      },
      'monitoring' => {
        'track_progress' => true,
        'broadcast_events' => true,
        'collect_metrics' => true
      }
    }
  }),
  metadata: workflow.metadata.merge({
    'assigned_orchestrator' => {
      'agent_id' => orchestrator.id,
      'agent_name' => orchestrator.name,
      'assigned_at' => Time.current.iso8601,
      'mcp_tool_id' => orchestrator.mcp_tool_id,
      'capabilities' => orchestrator.mcp_capabilities
    }
  })
)

puts "✅ Workflow Orchestrator Successfully Assigned!"
puts ""
puts "Workflow: #{workflow.name}"
puts "Orchestrator: #{orchestrator.name}"
puts ""
puts "📋 Configuration:"
puts "   Orchestrator ID: #{workflow.configuration['orchestrator']['agent_id']}"
puts "   Coordination Strategy: #{workflow.configuration['orchestrator']['coordination_strategy']}"
puts "   Error Handling:"
puts "     - Retry Failed Nodes: #{workflow.configuration['orchestrator']['error_handling']['retry_failed_nodes']}"
puts "     - Create Checkpoints: #{workflow.configuration['orchestrator']['error_handling']['create_checkpoints']}"
puts "     - Max Retries: #{workflow.configuration['orchestrator']['error_handling']['max_retries']}"
puts "   Monitoring:"
puts "     - Track Progress: #{workflow.configuration['orchestrator']['monitoring']['track_progress']}"
puts "     - Broadcast Events: #{workflow.configuration['orchestrator']['monitoring']['broadcast_events']}"
puts "     - Collect Metrics: #{workflow.configuration['orchestrator']['monitoring']['collect_metrics']}"
puts ""
puts "📊 Orchestrator Capabilities:"
orchestrator.mcp_capabilities.each { |cap| puts "   - #{cap}" }
