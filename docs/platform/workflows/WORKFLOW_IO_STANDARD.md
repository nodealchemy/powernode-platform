# Workflow I/O Standard

**Industry-aligned input/output specification for workflow node execution**

---

## Table of Contents

1. [Overview](#overview)
2. [Core I/O Contract](#core-io-contract)
3. [Standard Keys](#standard-keys)
4. [Template Variable Syntax](#template-variable-syntax)
5. [Node Type-Specific Requirements](#node-type-specific-requirements)
6. [Data Flow Validation](#data-flow-validation)
7. [Error Format Specification](#error-format-specification)

---

## Overview

This document defines the standard I/O format for all workflow node executors. All nodes in `server/app/services/mcp/node_executors/` MUST adhere to this specification to ensure consistent data flow and interoperability.

### Industry Alignment

Based on analysis of major workflow platforms:

| Platform | Primary Keys | Data Keys | Metadata Keys |
|----------|--------------|-----------|---------------|
| **LangChain** | `input`, `output` | `context`, `chat_history` | `intermediate_steps` |
| **n8n** | - | `json`, `binary` | `pairedItem` |
| **Zapier** | `input_data`, `output_data` | - | `meta` |
| **Make** | `input`, `output` | `data` | `metadata` |
| **Temporal** | `input`, `result` | `context` | `metadata` |

**Powernode adopts**: `output`, `data`, `result`, `metadata` as universal keys.

---

## Core I/O Contract

Every node executor's `perform_execution` method MUST return a hash with these keys:

```ruby
{
  output: <primary_result>,      # REQUIRED - The main output value
  data: { ... },                 # Optional - Additional structured data
  result: { ... },               # Optional - Computed/evaluation results
  metadata: {                    # REQUIRED - Execution context
    node_id: @node.node_id,
    node_type: "<type>",
    executed_at: Time.current.iso8601
  }
}
```

### Key Definitions

| Key | Required | Type | Purpose |
|-----|----------|------|---------|
| `output` | **Yes** | Any | Primary result produced by the node |
| `data` | No | Hash | Supporting data, agent info, additional context |
| `result` | No | Hash | Computed values, evaluation results, status info |
| `metadata` | **Yes** | Hash | Execution info: node_id, node_type, timestamps, cost |
| `context` | No | Hash | Contextual information passed between nodes |
| `error` | No | Hash | Error details when execution fails |

---

## Standard Keys

### `output` (Required)

The primary result produced by the node. This is the value that flows to downstream nodes automatically.

```ruby
# String output (AI Agent)
{ output: "Generated blog post content..." }

# Boolean output (Condition)
{ output: true }

# Array output (Loop)
{ output: [item1, item2, item3] }

# Hash output (API Call)
{ output: { status: 200, body: {...} } }
```

### `data` (Optional)

Supporting data and structured results that provide context or additional information.

```ruby
{
  data: {
    agent_id: "agent_123",
    agent_name: "Blog Writer",
    model: "claude-3-5-sonnet-20241022",
    word_count: 500,
    keywords: ["AI", "Healthcare"]
  }
}
```

### `result` (Optional)

Computed values from node evaluation, typically for control flow nodes.

```ruby
# Condition node
{
  result: {
    condition_met: true,
    evaluated_branch: "then"
  }
}

# Loop node
{
  result: {
    iterations_completed: 10,
    iterations_successful: 9,
    iterations_failed: 1,
    loop_status: "completed_with_errors"
  }
}
```

### `metadata` (Required)

Execution information and context that MUST be included in every node output.

```ruby
{
  metadata: {
    node_id: "agent_1",           # REQUIRED
    node_type: "ai_agent",        # REQUIRED
    executed_at: "2025-01-30T10:30:00Z",  # REQUIRED
    cost: 0.002,                  # Optional - execution cost
    tokens_used: 150,             # Optional - for AI nodes
    duration_ms: 1234,            # Optional - execution time
    model: "claude-3-5-sonnet"    # Optional - model used
  }
}
```

---

## Template Variable Syntax

Nodes support variable interpolation using double-brace syntax:

### Basic Variable Reference

```ruby
"{{variable_name}}"  # References variable from execution context
```

### Nested Path Reference

```ruby
"{{node_id.output}}"         # Output from specific node
"{{input.topic}}"            # Input variable path
"{{previous.data.field}}"    # Previous node's data
```

### Usage in Configuration

```ruby
# Prompt template
configuration = {
  "prompt_template" => "Write about {{topic}} for {{audience}}"
}

# API URL with variables
configuration = {
  "url" => "https://api.example.com/{{resource}}/{{id}}"
}
```

### Resolution Priority

When building node input data, values merge in this priority order (later overrides earlier):

1. Workflow input variables (lowest priority)
2. Predecessor `output`, `data`, `result` keys (merged from all predecessors)
3. Explicit input mapping (if configured)
4. Static inputs (highest priority)

---

## Node Type-Specific Requirements

### AI Agent Node

```ruby
{
  output: "Generated content...",  # Agent's text response
  data: {
    agent_id: "agent_123",
    agent_name: "Blog Writer",
    agent_type: "content_generation",
    model: "claude-3-5-sonnet-20241022"
  },
  metadata: {
    node_id: "writer_1",
    node_type: "ai_agent",
    executed_at: "2025-01-30T10:30:00Z",
    cost: 0.002,
    tokens_used: 150,
    duration_ms: 1234,
    agent_execution_id: "exec_456"
  }
}
```

### Condition Node

```ruby
{
  output: true,  # Boolean result
  result: {
    condition_met: true,
    evaluated_branch: "then"  # or "else"
  },
  data: {
    condition_type: "expression"  # or "comparison", "exists"
  },
  metadata: {
    node_id: "condition_1",
    node_type: "condition",
    executed_at: "2025-01-30T10:30:00Z"
  }
}
```

### Loop Node

```ruby
{
  output: [result1, result2, result3],  # Array of iteration results
  result: {
    iterations_completed: 3,
    iterations_successful: 3,
    iterations_failed: 0,
    loop_status: "completed"
  },
  data: {
    item_variable: "item",
    index_variable: "index",
    execution_mode: "serial",
    iteration_details: [
      { index: 0, success: true },
      { index: 1, success: true },
      { index: 2, success: true }
    ]
  },
  metadata: {
    node_id: "loop_1",
    node_type: "loop",
    executed_at: "2025-01-30T10:30:00Z",
    total_items: 3
  }
}
```

### API Call Node

```ruby
{
  output: { status: 200, body: {...} },  # Parsed response or mapped value
  data: {
    status_code: 200,
    headers: {...},
    response_time_ms: 123,
    content_type: "application/json",
    attempts: 1
  },
  result: {
    success: true,
    status: 200,
    response_size_bytes: 1024
  },
  metadata: {
    node_id: "api_1",
    node_type: "api_call",
    executed_at: "2025-01-30T10:30:00Z",
    http_method: "POST",
    url: "https://api.example.com/..."
  }
}
```

### Transform Node

```ruby
{
  output: transformed_data,  # Transformed result
  result: {
    transformation: "map",  # or "filter", "reduce", "template"
    items_processed: 10
  },
  metadata: {
    node_id: "transform_1",
    node_type: "transform",
    executed_at: "2025-01-30T10:30:00Z",
    transform_type: "map"
  }
}
```

### Human Approval Node

```ruby
{
  output: {
    approval_requested: true,
    approval_id: "apr_abc123",
    status: "pending"
  },
  data: {
    approval_id: "apr_abc123",
    status: "pending",
    approval_type: "any",  # or "all", "majority", "quorum"
    required_approvals: 1,
    current_approvals: 0,
    approvers_count: 3,
    deadline: "2025-01-31T10:30:00Z",
    timeout_action: "reject",
    workflow_paused: true
  },
  result: {
    approved: false,
    approval_status: "pending",
    requires_action: true
  },
  metadata: {
    node_id: "approval_1",
    node_type: "human_approval",
    executed_at: "2025-01-30T10:30:00Z",
    workflow_state: "paused_for_approval"
  }
}
```

### Start Node

```ruby
{
  output: {
    workflow_id: "wf_123",
    run_id: "run_456",
    triggered_at: "2025-01-30T10:30:00Z"
  },
  data: {
    input_variables: { topic: "AI in Healthcare" }
  },
  metadata: {
    node_id: "start_1",
    node_type: "start",
    trigger_type: "manual"  # or "scheduled", "webhook"
  }
}
```

### End Node

```ruby
{
  output: "Workflow completed successfully",
  result: {
    status: "completed",
    final_output: "Polished blog post content..."
  },
  data: {
    all_node_outputs: {
      research_1: {...},
      writer_1: {...}
    },
    execution_path: ["start_1", "research_1", "writer_1", "end_1"]
  },
  metadata: {
    node_id: "end_1",
    node_type: "end",
    completed_at: "2025-01-30T10:35:00Z",
    total_duration_ms: 180000,
    total_cost: 0.015,
    nodes_executed: 5
  }
}
```

---

## Data Flow Validation

### Auto-Wire Algorithm

The orchestrator automatically wires predecessor outputs to successor inputs:

```ruby
def auto_wire_predecessor_outputs
  incoming_edges = @workflow_run.ai_workflow.ai_workflow_edges.where(
    target_node_id: @node.node_id
  )

  predecessor_node_ids = incoming_edges.pluck(:source_node_id)
  auto_wired = {}

  predecessor_node_ids.each do |predecessor_id|
    result_data = @previous_results[predecessor_id]
    if result_data.present?
      if result_data[:output_data].present?
        auto_wired.merge!(result_data[:output_data])
      elsif result_data.is_a?(Hash)
        auto_wired.merge!(result_data)
      end
    end
  end

  auto_wired
end
```

### Validation Rules

1. All non-start nodes must have incoming edges
2. All nodes must be reachable from start node
3. All nodes must be able to reach end node
4. No disconnected subgraphs allowed

### Explicit Data Mapping (Optional)

Use when you need to rename keys or prevent collisions:

```ruby
edge.configuration = {
  data_mapping: {
    "{{research_1.output}}" => "research_findings",
    "{{research_1.data.agent_name}}" => "researcher",
    "{{input.topic}}" => "topic"
  }
}
```

---

## Error Format Specification

When a node fails, it should raise `Mcp::AiWorkflowOrchestrator::NodeExecutionError` or return an error structure:

### Error Output Structure

```ruby
{
  output: nil,
  data: {
    status_code: nil,
    attempts: 3
  },
  result: {
    success: false,
    error_message: "Detailed error description"
  },
  metadata: {
    node_id: @node.node_id,
    node_type: "api_call",
    executed_at: Time.current.iso8601,
    error: true
  }
}
```

### Error Handling in Base Executor

The base executor automatically catches errors and converts them:

```ruby
def execute
  start_time = Time.current
  begin
    result = perform_execution
    result.merge(success: true, execution_time_ms: execution_time_ms)
  rescue StandardError => e
    @logger.error "[NODE_EXECUTOR] #{node.node_type} execution failed: #{e.message}"
    raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
          "#{node.node_type} execution failed: #{e.message}"
  end
end
```

---

## Implementation Checklist

When implementing a new node executor:

- [ ] Inherit from `Mcp::NodeExecutors::Base`
- [ ] Implement `perform_execution` method
- [ ] Return hash with `output` key (required)
- [ ] Include `metadata` with `node_id`, `node_type`, `executed_at`
- [ ] Use `get_variable()` for reading variables (not orchestrator global)
- [ ] Use `set_variable()` for storing output variables
- [ ] Raise `NodeExecutionError` for recoverable errors
- [ ] Document expected input/output in class comments

---

**Document Status**: Complete
**Last Updated**: 2025-01-30
**Referenced By**: All node executors in `server/app/services/mcp/node_executors/`
