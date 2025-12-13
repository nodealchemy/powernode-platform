#!/usr/bin/env ruby
# frozen_string_literal: true

# Get account and user
account = Account.first
user = account.users.first
claude_provider = AiProvider.find_by(name: 'Claude (Anthropic)')

# Create Workflow Orchestrator Agent
orchestrator = AiAgent.create!(
  account: account,
  creator: user,
  ai_provider: claude_provider,
  name: 'Workflow Orchestrator',
  description: 'Orchestrates and manages workflow execution, coordinating between different AI agents and handling workflow state transitions',
  agent_type: 'workflow_operations',
  version: '1.0.0',
  status: 'active',
  mcp_capabilities: [
    'workflow:coordinate',
    'workflow:execute',
    'workflow:monitor',
    'state:manage',
    'error:recover',
    'checkpoint:create',
    'checkpoint:restore'
  ],
  mcp_tool_manifest: {
    'name' => 'workflow_orchestrator',
    'description' => 'Orchestrates workflow execution and coordinates multi-agent tasks',
    'type' => 'workflow_operations',
    'version' => '1.0.0',
    'operations' => [
      'coordinate_execution',
      'manage_state',
      'handle_transitions',
      'recover_errors',
      'create_checkpoints',
      'restore_checkpoints'
    ],
    'capabilities' => [
      'workflow:coordinate',
      'workflow:execute',
      'state:manage',
      'error:recover'
    ]
  },
  mcp_input_schema: {
    'type' => 'object',
    'properties' => {
      'workflow_id' => {
        'type' => 'string',
        'description' => 'ID of the workflow to orchestrate'
      },
      'operation' => {
        'type' => 'string',
        'enum' => [ 'execute', 'monitor', 'recover', 'checkpoint' ],
        'description' => 'Operation to perform'
      },
      'parameters' => {
        'type' => 'object',
        'description' => 'Additional parameters for the operation'
      }
    },
    'required' => [ 'workflow_id', 'operation' ]
  },
  mcp_output_schema: {
    'type' => 'object',
    'properties' => {
      'success' => {
        'type' => 'boolean',
        'description' => 'Whether the operation succeeded'
      },
      'result' => {
        'type' => 'object',
        'description' => 'Operation result data'
      },
      'state' => {
        'type' => 'string',
        'description' => 'Current workflow state'
      },
      'metadata' => {
        'type' => 'object',
        'description' => 'Additional metadata'
      }
    },
    'required' => [ 'success', 'state' ]
  },
  configuration: {
    model: 'claude-3-5-sonnet-20241022',
    temperature: 0.3,
    max_tokens: 4000,
    system_prompt: 'You are a workflow orchestration agent responsible for managing complex multi-agent workflows. Coordinate execution between specialized agents, manage workflow state, handle transitions, and ensure reliable execution with proper error handling and recovery.',
    retry_strategy: {
      enabled: true,
      max_retries: 3,
      strategy: 'exponential',
      initial_delay_ms: 1000
    }
  },
  mcp_metadata: {
    role: 'orchestrator',
    scope: 'workflow_management',
    responsibilities: [
      'Coordinate multi-agent execution',
      'Manage workflow state transitions',
      'Handle node execution',
      'Implement retry and recovery strategies',
      'Monitor workflow progress',
      'Create and manage checkpoints'
    ],
    supported_workflows: [ 'blog_generation', 'multi_agent', 'sequential', 'parallel' ]
  }
)

puts "\n✅ Workflow Orchestrator Agent Created Successfully!"
puts "   ID: #{orchestrator.id}"
puts "   Name: #{orchestrator.name}"
puts "   Type: #{orchestrator.agent_type}"
puts "   Slug: #{orchestrator.slug}"
puts "   Version: #{orchestrator.version}"
puts "   MCP Tool ID: #{orchestrator.mcp_tool_id}"
puts "   Provider: #{orchestrator.ai_provider.name}"
puts "   Status: #{orchestrator.status}"
puts "\n   MCP Capabilities:"
orchestrator.mcp_capabilities.each { |cap| puts "     - #{cap}" }
