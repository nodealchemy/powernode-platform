# MCP Integration Guide

**Model Context Protocol implementation architecture and patterns**

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Service Categories](#service-categories)
4. [Node Execution Pipeline](#node-execution-pipeline)
5. [State Management](#state-management)
6. [Error Recovery](#error-recovery)
7. [Telemetry and Monitoring](#telemetry-and-monitoring)

---

## Overview

The Model Context Protocol (MCP) implementation in Powernode provides a robust workflow execution engine with support for AI agents, integrations, and DevOps automation.

### Key Features

- **50+ Node Types**: AI agents, API calls, conditions, loops, CI/CD, content management
- **Saga Pattern**: Transaction-like execution with compensation
- **Circuit Breakers**: Provider resilience and fallback
- **Real-time Updates**: WebSocket-based execution monitoring
- **Checkpointing**: Long-running workflow recovery

### Directory Structure

```
server/app/services/mcp/
├── # Core Services
├── ai_workflow_orchestrator.rb    # Main orchestrator
├── workflow_executor.rb           # Execution engine
├── workflow_state_machine.rb      # State transitions
├── saga_coordinator.rb            # Transaction management
│
├── # Node Execution
├── node_executors/                # 50+ node type executors
│   ├── base.rb                    # Base executor class
│   └── ...                        # Individual node types
├── node_execution_context.rb      # Execution context
├── conditional_evaluator.rb       # Condition evaluation
│
├── # State & Recovery
├── workflow_state_manager.rb      # State persistence
├── workflow_checkpoint_manager.rb # Checkpointing
├── advanced_error_recovery_service.rb
│
├── # Protocol Services
├── protocol_service.rb            # MCP protocol handling
├── transport_service.rb           # Transport layer
├── security_service.rb            # Security & auth
├── permission_validator.rb        # Permission checks
│
├── # Integration Services
├── prompt_service.rb              # Prompt management
├── resource_service.rb            # Resource access
├── registry_service.rb            # Tool registry
├── oauth_service.rb               # OAuth integration
│
├── # Monitoring
├── telemetry_service.rb           # Metrics & tracing
├── execution_tracer.rb            # Execution tracing
├── workflow_monitor.rb            # Health monitoring
├── broadcast_service.rb           # WebSocket broadcasts
│
├── # Events & Analytics
├── workflow_event_store.rb        # Event sourcing
├── execution_event_store.rb       # Execution events
├── workflow_analytics_engine.rb   # Analytics
│
├── # Utilities
├── dynamic_workflow_generator.rb  # Dynamic workflows
├── workflow_version_manager.rb    # Version control
├── workflow_marketplace_service.rb # Marketplace
├── sync_execution_service.rb      # Sync execution
├── streamable_http_service.rb     # HTTP streaming
└── hosting_service.rb             # Hosting service
```

---

## Architecture

### Execution Flow

```
                    ┌─────────────────────┐
                    │   API Request       │
                    │ POST /workflows/:id │
                    │      /execute       │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │  AiWorkflowsController
                    │    execute method   │
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │ WorkflowExecutor    │
                    │  - Validates workflow
                    │  - Creates run record
                    │  - Enqueues job     │
                    └──────────┬──────────┘
                               │
         ┌─────────────────────┼─────────────────────┐
         │                     │                     │
    ┌────▼────┐         ┌──────▼──────┐       ┌──────▼──────┐
    │ Sidekiq │         │ Real-time   │       │ Sync Mode   │
    │ Worker  │         │ WebSocket   │       │ (testing)   │
    └────┬────┘         └──────┬──────┘       └──────┬──────┘
         │                     │                     │
         └─────────────────────┼─────────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │ AiWorkflowOrchestrator
                    │  - State machine    │
                    │  - Node execution   │
                    │  - Data flow        │
                    └──────────┬──────────┘
                               │
            ┌──────────────────┼──────────────────┐
            │                  │                  │
     ┌──────▼──────┐    ┌──────▼──────┐    ┌──────▼──────┐
     │ Start Node  │    │ Process     │    │ End Node   │
     │  Executor   │    │ Nodes       │    │  Executor  │
     └──────┬──────┘    └──────┬──────┘    └──────┬──────┘
            │                  │                  │
            └──────────────────┼──────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │ Broadcast Updates   │
                    │  - ActionCable      │
                    │  - McpChannel       │
                    └─────────────────────┘
```

### Component Responsibilities

| Component | Responsibility |
|-----------|----------------|
| `WorkflowExecutor` | Entry point, validation, job dispatch |
| `AiWorkflowOrchestrator` | Node traversal, data flow, error handling |
| `WorkflowStateMachine` | State transitions, validations |
| `NodeExecutors::*` | Individual node type logic |
| `SagaCoordinator` | Transaction management, compensation |
| `BroadcastService` | Real-time WebSocket updates |

---

## Service Categories

### Core Orchestration

#### AiWorkflowOrchestrator

Main orchestration service that executes workflows.

```ruby
class Mcp::AiWorkflowOrchestrator
  def initialize(workflow:, workflow_run:, account:, user:)
  def execute
  def execute_node(node)
  def evaluate_condition(condition_node)
  def handle_node_failure(node, error)
end
```

**Key methods**:
- `execute`: Runs the complete workflow
- `execute_node`: Executes individual nodes
- `evaluate_condition`: Handles condition branching
- `handle_node_failure`: Error recovery logic

#### WorkflowExecutor

Entry point for workflow execution.

```ruby
class Mcp::WorkflowExecutor
  def initialize(workflow:, input_variables: {}, user: nil)
  def execute(async: true)
  def validate_workflow
  def create_workflow_run
end
```

#### WorkflowStateMachine

Manages workflow run state transitions.

```ruby
class Mcp::WorkflowStateMachine
  STATES = %i[pending initializing running paused completed failed cancelled].freeze

  def transition_to(new_state)
  def can_transition_to?(new_state)
  def valid_transitions
end
```

**State Transitions**:
```
pending → initializing → running → completed
                            ↓
                         paused → running
                            ↓
                         failed
                            ↓
                       cancelled
```

### Protocol Services

#### ProtocolService

Handles MCP protocol communication.

```ruby
class Mcp::ProtocolService
  def send_request(method, params)
  def handle_response(response)
  def handle_notification(notification)
end
```

#### TransportService

Transport layer abstraction.

```ruby
class Mcp::TransportService
  def connect(server_uri)
  def send(message)
  def receive
  def disconnect
end
```

#### SecurityService

Security and authentication.

```ruby
class Mcp::SecurityService
  def authenticate_request(request)
  def validate_permissions(user, resource)
  def encrypt_credentials(credentials)
  def decrypt_credentials(encrypted)
end
```

### State Management

#### WorkflowStateManager

Persists and retrieves workflow state.

```ruby
class Mcp::WorkflowStateManager
  def save_state(run, state)
  def load_state(run)
  def clear_state(run)
end
```

#### WorkflowCheckpointManager

Checkpointing for long-running workflows.

```ruby
class Mcp::WorkflowCheckpointManager
  def create_checkpoint(run, node_id, state)
  def restore_from_checkpoint(run, checkpoint_id)
  def list_checkpoints(run)
  def cleanup_old_checkpoints(run)
end
```

### Integration Services

#### PromptService

Manages MCP prompts.

```ruby
class Mcp::PromptService
  def list_prompts(server_id)
  def get_prompt(server_id, prompt_name)
  def execute_prompt(server_id, prompt_name, arguments)
end
```

#### ResourceService

Accesses MCP resources.

```ruby
class Mcp::ResourceService
  def list_resources(server_id)
  def read_resource(server_id, uri)
  def subscribe_resource(server_id, uri, &callback)
end
```

#### RegistryService

Tool and server registry.

```ruby
class Mcp::RegistryService
  def register_server(server_config)
  def list_servers
  def get_server(server_id)
  def list_tools(server_id)
end
```

---

## Node Execution Pipeline

### Execution Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Node Execution                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Create NodeExecutionContext                             │
│     - Load input data                                       │
│     - Resolve predecessor outputs                           │
│     - Prepare variables                                     │
│                                                             │
│  2. Select Node Executor                                    │
│     - Look up by node_type                                  │
│     - Instantiate with context                              │
│                                                             │
│  3. Execute Node                                            │
│     - Call perform_execution()                              │
│     - Track timing and cost                                 │
│     - Handle errors                                         │
│                                                             │
│  4. Store Results                                           │
│     - Save output_data                                      │
│     - Update node execution record                          │
│     - Set variables for successors                          │
│                                                             │
│  5. Broadcast Update                                        │
│     - Send WebSocket notification                           │
│     - Update run progress                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### NodeExecutionContext

```ruby
class Mcp::NodeExecutionContext
  attr_reader :node, :workflow_run, :input_data, :previous_results, :variables

  def initialize(node:, workflow_run:, orchestrator:)
    @input_data = build_input_data
    @previous_results = load_predecessor_outputs
    @variables = merge_variables
  end

  def get_variable(name)
    @variables[name.to_s] || @variables[name.to_sym]
  end

  def set_variable(name, value)
    @variables[name.to_s] = value
  end
end
```

### Executor Selection

```ruby
def select_executor(node)
  executor_class = case node.node_type
  when 'start' then NodeExecutors::Start
  when 'end' then NodeExecutors::End
  when 'ai_agent' then NodeExecutors::AiAgent
  when 'condition' then NodeExecutors::Condition
  when 'loop' then NodeExecutors::Loop
  when 'api_call' then NodeExecutors::ApiCall
  # ... 44 more node types
  else
    raise UnknownNodeTypeError, "Unknown node type: #{node.node_type}"
  end

  executor_class.new(
    node: node,
    node_execution: node_execution,
    node_context: context,
    orchestrator: self
  )
end
```

### Data Flow

See [WORKFLOW_IO_STANDARD.md](WORKFLOW_IO_STANDARD.md) for complete I/O specification.

```ruby
# Auto-wire predecessor outputs
def auto_wire_predecessor_outputs
  incoming_edges.each do |edge|
    predecessor_result = @previous_results[edge.source_node_id]

    if edge.data_mapping.present?
      # Apply explicit mapping
      apply_data_mapping(edge.data_mapping, predecessor_result)
    else
      # Auto-merge output, data, result keys
      @input_data.merge!(predecessor_result[:output_data] || {})
    end
  end
end
```

---

## State Management

### Saga Pattern

The `SagaCoordinator` implements the saga pattern for distributed transactions.

```ruby
class Mcp::SagaCoordinator
  def initialize(workflow_run)
    @workflow_run = workflow_run
    @completed_steps = []
    @compensation_handlers = {}
  end

  def execute_step(step_name, &block)
    result = yield
    @completed_steps << { name: step_name, result: result }
    result
  rescue StandardError => e
    compensate
    raise
  end

  def register_compensation(step_name, &handler)
    @compensation_handlers[step_name] = handler
  end

  def compensate
    @completed_steps.reverse.each do |step|
      handler = @compensation_handlers[step[:name]]
      handler&.call(step[:result])
    end
  end
end
```

### Workflow State Persistence

```ruby
# Save state after each node
def save_execution_state
  state = {
    current_node_id: @current_node&.id,
    completed_nodes: @completed_nodes.map(&:id),
    variables: @variables,
    results: serialize_results(@node_results)
  }

  WorkflowStateManager.save_state(@workflow_run, state)
end

# Restore from checkpoint
def restore_from_checkpoint(checkpoint_id)
  checkpoint = WorkflowCheckpointManager.restore_from_checkpoint(
    @workflow_run,
    checkpoint_id
  )

  @current_node = find_node(checkpoint.node_id)
  @variables = checkpoint.variables
  @node_results = deserialize_results(checkpoint.results)
end
```

---

## Error Recovery

### Advanced Error Recovery Service

```ruby
class Mcp::AdvancedErrorRecoveryService
  RECOVERY_STRATEGIES = %i[
    retry
    skip
    fallback
    compensate
    escalate
  ].freeze

  def initialize(workflow_run, node_execution)
    @workflow_run = workflow_run
    @node_execution = node_execution
  end

  def recover(error)
    strategy = determine_strategy(error)

    case strategy
    when :retry
      retry_with_backoff
    when :skip
      skip_node_with_default
    when :fallback
      execute_fallback_node
    when :compensate
      trigger_compensation
    when :escalate
      escalate_to_human
    end
  end

  private

  def determine_strategy(error)
    case error
    when Timeout::Error, Net::OpenTimeout
      :retry
    when ValidationError
      :skip
    when ProviderError
      :fallback
    when CriticalError
      :compensate
    else
      :escalate
    end
  end
end
```

### Retry with Exponential Backoff

```ruby
def retry_with_backoff
  max_retries = @node.configuration['max_retries'] || 3
  base_delay = @node.configuration['retry_delay'] || 1

  @node_execution.retry_count.times do |attempt|
    return if attempt >= max_retries

    delay = base_delay * (2 ** attempt) + rand(0.0..0.5)
    sleep(delay)

    begin
      return execute_node(@node)
    rescue StandardError => e
      @logger.warn "Retry #{attempt + 1} failed: #{e.message}"
    end
  end

  raise MaxRetriesExceeded, "Node failed after #{max_retries} retries"
end
```

---

## Telemetry and Monitoring

### TelemetryService

Collects execution metrics.

```ruby
class Mcp::TelemetryService
  def record_execution_start(workflow_run)
    @start_time = Time.current
    @metrics = {
      workflow_id: workflow_run.ai_workflow_id,
      run_id: workflow_run.id,
      started_at: @start_time
    }
  end

  def record_node_execution(node_execution)
    @node_metrics << {
      node_id: node_execution.node_id,
      node_type: node_execution.node_type,
      duration_ms: node_execution.duration_ms,
      cost: node_execution.cost,
      status: node_execution.status
    }
  end

  def record_execution_complete(status)
    @metrics.merge!(
      completed_at: Time.current,
      total_duration_ms: ((Time.current - @start_time) * 1000).round,
      status: status,
      nodes_executed: @node_metrics.count,
      total_cost: @node_metrics.sum { |n| n[:cost] || 0 }
    )

    persist_metrics
  end
end
```

### BroadcastService

Real-time WebSocket updates.

```ruby
class Mcp::BroadcastService
  def broadcast_status_change(workflow_run, old_status, new_status)
    ActionCable.server.broadcast(
      "ai_orchestration:workflow_run:#{workflow_run.id}",
      {
        event: 'workflow.status_changed',
        payload: {
          run_id: workflow_run.id,
          old_status: old_status,
          new_status: new_status,
          updated_at: Time.current.iso8601
        }
      }
    )
  end

  def broadcast_node_execution(node_execution)
    ActionCable.server.broadcast(
      "ai_orchestration:workflow_run:#{node_execution.ai_workflow_run_id}",
      {
        event: 'workflow.node.execution_update',
        payload: {
          node_id: node_execution.node_id,
          status: node_execution.status,
          progress: calculate_progress,
          output_preview: truncate_output(node_execution.output_data)
        }
      }
    )
  end
end
```

### WorkflowMonitor

Health and performance monitoring.

```ruby
class Mcp::WorkflowMonitor
  def check_health
    {
      status: healthy? ? 'healthy' : 'degraded',
      active_runs: active_run_count,
      stuck_runs: stuck_run_count,
      avg_execution_time: average_execution_time,
      error_rate: error_rate_last_hour
    }
  end

  def detect_stuck_runs
    AiWorkflowRun
      .where(status: %w[initializing running])
      .where('updated_at < ?', 30.minutes.ago)
  end
end
```

---

## Best Practices

### 1. Node Executor Implementation

```ruby
class Mcp::NodeExecutors::MyCustomNode < Base
  protected

  def perform_execution
    # Validate configuration
    validate_configuration!

    # Execute logic
    result = execute_custom_logic

    # Return standard format
    {
      output: result,
      data: { custom_field: 'value' },
      metadata: {
        node_id: @node.node_id,
        node_type: 'my_custom_node',
        executed_at: Time.current.iso8601
      }
    }
  end

  private

  def validate_configuration!
    raise ArgumentError, "Required field missing" unless configuration['required_field']
  end
end
```

### 2. Error Handling

```ruby
def execute_with_recovery
  perform_execution
rescue RecoverableError => e
  log_error "Recoverable error: #{e.message}"
  recovery_service.recover(e)
rescue CriticalError => e
  log_error "Critical error: #{e.message}"
  saga_coordinator.compensate
  raise
end
```

### 3. Broadcasting Updates

```ruby
def broadcast_progress
  broadcast_service.broadcast_node_execution(@node_execution)

  # Throttle broadcasts for fast-executing nodes
  @last_broadcast ||= Time.current
  return unless (Time.current - @last_broadcast) > 0.1

  @last_broadcast = Time.current
end
```

---

## Related Documentation

- [NODE_EXECUTOR_REFERENCE.md](../backend/NODE_EXECUTOR_REFERENCE.md) - Complete node executor documentation
- [WORKFLOW_IO_STANDARD.md](WORKFLOW_IO_STANDARD.md) - I/O specification
- [WORKFLOW_SYSTEM_STANDARDS.md](WORKFLOW_SYSTEM_STANDARDS.md) - Data flow standards
- [WORKFLOW_RELIABILITY_GUIDE.md](WORKFLOW_RELIABILITY_GUIDE.md) - Reliability patterns

---

**Document Status**: Complete
**Last Updated**: 2025-01-30
**Source**: `server/app/services/mcp/`
