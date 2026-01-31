# Node Executor Reference

**Complete reference for all workflow node executors**

---

## Table of Contents

1. [Overview](#overview)
2. [Base Executor](#base-executor)
3. [Control Flow Nodes](#control-flow-nodes)
4. [AI/Agent Nodes](#aiagent-nodes)
5. [Integration Nodes](#integration-nodes)
6. [Content Nodes](#content-nodes)
7. [DevOps Nodes](#devops-nodes)
8. [MCP Nodes](#mcp-nodes)
9. [Utility Nodes](#utility-nodes)

---

## Overview

Node executors are located in `server/app/services/mcp/node_executors/`. Each executor inherits from `Base` and implements the `perform_execution` method.

### Directory Structure

```
server/app/services/mcp/node_executors/
├── base.rb                 # Base class for all executors
├── mcp_base.rb            # Extended base for MCP nodes
│
├── # Control Flow (8)
├── start.rb               # Workflow entry point
├── end.rb                 # Workflow completion
├── condition.rb           # Conditional branching
├── loop.rb                # Collection iteration
├── split.rb               # Parallel execution
├── merge.rb               # Parallel join
├── delay.rb               # Timed delay
├── scheduler.rb           # Scheduled execution
│
├── # AI/Agent (2)
├── ai_agent.rb            # AI agent execution
├── sub_workflow.rb        # Nested workflow execution
│
├── # Integration (9)
├── api_call.rb            # HTTP API requests
├── webhook.rb             # Webhook handling
├── notification.rb        # Notification dispatch
├── email.rb               # Email sending
├── database.rb            # Database operations
├── file.rb                # File operations
├── file_upload.rb         # File upload
├── file_download.rb       # File download
├── file_transform.rb      # File transformation
│
├── # Content (9)
├── page_create.rb         # Create CMS page
├── page_read.rb           # Read CMS page
├── page_update.rb         # Update CMS page
├── page_publish.rb        # Publish CMS page
├── kb_article_create.rb   # Create KB article
├── kb_article_read.rb     # Read KB article
├── kb_article_update.rb   # Update KB article
├── kb_article_publish.rb  # Publish KB article
├── kb_article_search.rb   # Search KB articles
│
├── # DevOps (10)
├── ci_trigger.rb          # Trigger CI pipeline
├── ci_wait_status.rb      # Wait for CI status
├── ci_get_logs.rb         # Get CI logs
├── ci_cancel.rb           # Cancel CI run
├── git_branch.rb          # Git branch operations
├── git_checkout.rb        # Git checkout
├── git_commit_status.rb   # Git commit status
├── git_create_check.rb    # Create GitHub check
├── git_comment.rb         # Git comment
├── git_pull_request.rb    # Pull request operations
├── deploy.rb              # Deployment execution
├── run_tests.rb           # Test execution
├── shell_command.rb       # Shell command execution
│
├── # MCP (4)
├── mcp_tool.rb            # MCP tool execution
├── mcp_prompt.rb          # MCP prompt execution
├── mcp_resource.rb        # MCP resource access
├── integration_execute.rb # Integration execution
│
├── # Utility (3)
├── transform.rb           # Data transformation
├── human_approval.rb      # Human approval workflow
└── validator.rb           # Data validation
```

---

## Base Executor

**File**: `server/app/services/mcp/node_executors/base.rb`

All node executors inherit from this base class.

### Interface

```ruby
class Base
  attr_reader :node, :node_execution, :node_context, :orchestrator

  def initialize(node:, node_execution:, node_context:, orchestrator:)
  def execute                    # Main entry point

  protected
  def perform_execution          # Override in subclass
  def input_data                 # Get input data for this node
  def get_variable(name)         # Get variable from context
  def set_variable(name, value)  # Set variable in context
  def previous_results           # Get previous node results
  def configuration              # Get node configuration
  def log_info(message)          # Log info message
  def log_debug(message)         # Log debug message
  def log_error(message)         # Log error message
end
```

### Output Format

All executors must return this structure:

```ruby
{
  output: <primary_result>,    # REQUIRED
  data: { ... },               # Optional
  result: { ... },             # Optional
  metadata: {                  # REQUIRED
    node_id: @node.node_id,
    node_type: "<type>",
    executed_at: Time.current.iso8601
  }
}
```

---

## Control Flow Nodes

### Start Node

**File**: `start.rb`

Entry point for workflow execution.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `input_variables` | Hash | No | Initial workflow variables |
| `trigger_type` | String | No | manual, scheduled, webhook |

**Output**:
```ruby
{ output: { workflow_id, run_id, triggered_at }, metadata: { trigger_type } }
```

### End Node

**File**: `end.rb`

Completion point that aggregates all node outputs.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `output_variable` | String | No | Variable to store final result |

**Output**:
```ruby
{ output: final_message, result: { status, final_output }, data: { all_node_outputs, execution_path } }
```

### Condition Node

**File**: `condition.rb`

Conditional branching based on expression evaluation.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `condition_type` | String | No | expression, comparison, exists |
| `condition` | String | Yes* | Expression to evaluate |
| `left_variable` | String | Yes* | Left operand (comparison) |
| `right_variable` | String | Yes* | Right operand (comparison) |
| `operator` | String | No | ==, !=, >, <, >=, <= |
| `output_variable` | String | No | Store result |

**Output**:
```ruby
{ output: true/false, result: { condition_met, evaluated_branch: "then"/"else" } }
```

### Loop Node

**File**: `loop.rb`

Iterates over collections.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `iteration_source` | String | Yes | Path to collection |
| `item_variable` | String | No | Variable for current item (default: "item") |
| `index_variable` | String | No | Variable for index (default: "index") |
| `max_iterations` | Integer | No | Maximum iterations (default: 1000) |
| `execution_mode` | String | No | serial, parallel |
| `break_on_error` | Boolean | No | Stop on first error (default: true) |
| `transform_expression` | String | No | Transform each item |

**Output**:
```ruby
{ output: [results], result: { iterations_completed, iterations_successful, iterations_failed, loop_status } }
```

### Split Node

**File**: `split.rb`

Splits execution into parallel branches.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `branches` | Array | Yes | Branch configurations |
| `wait_for_all` | Boolean | No | Wait for all branches |

### Merge Node

**File**: `merge.rb`

Joins parallel branches back together.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `merge_strategy` | String | No | wait_all, first_complete |

### Delay Node

**File**: `delay.rb`

Pauses execution for specified duration.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `delay_seconds` | Integer | Yes | Delay duration in seconds |
| `delay_until` | String | No | ISO8601 timestamp to wait until |

### Scheduler Node

**File**: `scheduler.rb`

Schedules future execution.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `schedule` | String | Yes | Cron expression or ISO8601 |
| `timezone` | String | No | Timezone for schedule |

---

## AI/Agent Nodes

### AI Agent Node

**File**: `ai_agent.rb`

Executes AI agents via MCP.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `agent_id` | String | Yes | AI agent ID |
| `prompt_template` | String | No | Prompt with {{variables}} |
| `input_mapping` | Hash | No | Map variables to agent params |
| `input` | Hash | No | Direct input parameters |
| `context` | Hash | No | Additional context |
| `output_variable` | String | No | Store result |

**Output**:
```ruby
{
  output: "Agent response...",
  data: { agent_id, agent_name, agent_type, model },
  metadata: { cost, tokens_used, duration_ms, agent_execution_id }
}
```

### Sub-Workflow Node

**File**: `sub_workflow.rb`

Executes nested workflow.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `workflow_id` | String | Yes | Sub-workflow ID |
| `input_mapping` | Hash | No | Map variables to sub-workflow |
| `wait_for_completion` | Boolean | No | Wait for sub-workflow |

---

## Integration Nodes

### API Call Node

**File**: `api_call.rb`

Makes HTTP requests to external APIs.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `url` | String | Yes | Target URL (supports {{variables}}) |
| `method` | String | No | GET, POST, PUT, PATCH, DELETE (default: GET) |
| `headers` | Hash | No | Request headers |
| `body` | Hash/String | No | Request body |
| `body_type` | String | No | json, form, raw |
| `timeout_seconds` | Integer | No | Timeout (default: 30) |
| `response_mapping` | String | No | Dot notation to extract value |
| `retry_count` | Integer | No | Retry attempts (max: 5) |
| `retry_delay_seconds` | Float | No | Delay between retries |
| `output_variable` | String | No | Store result |

**Output**:
```ruby
{
  output: parsed_response,
  data: { status_code, headers, response_time_ms, content_type, attempts },
  result: { success, status, response_size_bytes }
}
```

### Webhook Node

**File**: `webhook.rb`

Handles webhook events.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `webhook_url` | String | No | URL to send webhook |
| `event_type` | String | No | Event type filter |
| `payload_template` | Hash | No | Payload structure |

### Notification Node

**File**: `notification.rb`

Sends notifications via multiple channels.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `channels` | Array | Yes | email, slack, sms, push |
| `recipients` | Array | Yes | Recipient identifiers |
| `subject` | String | No | Notification subject |
| `message` | String | Yes | Notification body |
| `template_id` | String | No | Use notification template |

### Email Node

**File**: `email.rb`

Sends emails.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `to` | Array | Yes | Recipient emails |
| `subject` | String | Yes | Email subject |
| `body` | String | Yes | Email body |
| `html_body` | String | No | HTML email body |
| `from` | String | No | Sender email |
| `attachments` | Array | No | File attachments |

### Database Node

**File**: `database.rb`

Executes database operations.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `operation` | String | Yes | query, insert, update, delete |
| `table` | String | Yes | Table name |
| `query` | String | No | Raw SQL query |
| `conditions` | Hash | No | WHERE conditions |
| `data` | Hash | No | Data for insert/update |

### File Nodes

**Files**: `file.rb`, `file_upload.rb`, `file_download.rb`, `file_transform.rb`

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `operation` | String | Yes | read, write, delete, copy |
| `path` | String | Yes | File path |
| `content` | String | No | File content for write |
| `transform_type` | String | No | csv_to_json, json_to_csv |

---

## Content Nodes

### Page Nodes

**Files**: `page_create.rb`, `page_read.rb`, `page_update.rb`, `page_publish.rb`

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `page_id` | String | Yes* | Page ID (for read/update/publish) |
| `title` | String | Yes* | Page title (for create) |
| `content` | String | No | Page content |
| `status` | String | No | draft, published |
| `metadata` | Hash | No | Page metadata |

### Knowledge Base Article Nodes

**Files**: `kb_article_create.rb`, `kb_article_read.rb`, `kb_article_update.rb`, `kb_article_publish.rb`, `kb_article_search.rb`

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `article_id` | String | Yes* | Article ID |
| `category_id` | String | No | Category ID |
| `title` | String | Yes* | Article title |
| `content` | String | No | Article content |
| `query` | String | Yes* | Search query (for search) |
| `tags` | Array | No | Article tags |

---

## DevOps Nodes

### CI/CD Nodes

**Files**: `ci_trigger.rb`, `ci_wait_status.rb`, `ci_get_logs.rb`, `ci_cancel.rb`

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `provider` | String | Yes | github, gitlab, jenkins |
| `repository` | String | Yes | Repository identifier |
| `workflow_id` | String | Yes | CI workflow/pipeline ID |
| `ref` | String | No | Branch/tag reference |
| `run_id` | String | Yes* | CI run ID (for status/logs/cancel) |
| `timeout_seconds` | Integer | No | Wait timeout |

### Git Nodes

**Files**: `git_branch.rb`, `git_checkout.rb`, `git_commit_status.rb`, `git_create_check.rb`, `git_comment.rb`, `git_pull_request.rb`

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `repository` | String | Yes | Repository identifier |
| `branch` | String | Yes* | Branch name |
| `commit_sha` | String | Yes* | Commit SHA |
| `status` | String | No | pending, success, failure |
| `comment` | String | Yes* | Comment body |
| `pr_number` | Integer | Yes* | Pull request number |

### Deploy Node

**File**: `deploy.rb`

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `environment` | String | Yes | Target environment |
| `service` | String | Yes | Service to deploy |
| `version` | String | No | Version to deploy |
| `strategy` | String | No | rolling, blue_green, canary |

### Run Tests Node

**File**: `run_tests.rb`

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `test_suite` | String | Yes | Test suite identifier |
| `filter` | String | No | Test filter pattern |
| `parallel` | Boolean | No | Run tests in parallel |

### Shell Command Node

**File**: `shell_command.rb`

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `command` | String | Yes | Shell command |
| `working_directory` | String | No | Working directory |
| `environment` | Hash | No | Environment variables |
| `timeout_seconds` | Integer | No | Command timeout |

---

## MCP Nodes

### MCP Tool Node

**File**: `mcp_tool.rb`

Executes MCP server tools.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `server_id` | String | Yes | MCP server ID |
| `tool_name` | String | Yes | Tool to execute |
| `arguments` | Hash | No | Tool arguments |

### MCP Prompt Node

**File**: `mcp_prompt.rb`

Executes MCP prompts.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `server_id` | String | Yes | MCP server ID |
| `prompt_name` | String | Yes | Prompt name |
| `arguments` | Hash | No | Prompt arguments |

### MCP Resource Node

**File**: `mcp_resource.rb`

Accesses MCP resources.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `server_id` | String | Yes | MCP server ID |
| `resource_uri` | String | Yes | Resource URI |

### Integration Execute Node

**File**: `integration_execute.rb`

Executes configured integrations.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `integration_id` | String | Yes | Integration ID |
| `action` | String | Yes | Action to perform |
| `parameters` | Hash | No | Action parameters |

---

## Utility Nodes

### Transform Node

**File**: `transform.rb`

Transforms data using configured rules.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `transform_type` | String | No | map, filter, reduce, template |
| `input_variable` | String | No | Source variable |
| `output_variable` | String | No | Destination variable |
| `mapping` | Hash | No | Field mapping (for map) |
| `filter_conditions` | Hash | No | Filter conditions |
| `reducer_function` | String | No | sum, count, first, last |
| `template` | String | No | Template string |

**Output**:
```ruby
{
  output: transformed_data,
  result: { transformation: "map", items_processed: 10 }
}
```

### Human Approval Node

**File**: `human_approval.rb`

Creates approval requests and pauses workflow.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `approvers` | Array | Yes | User IDs or role references |
| `approval_type` | String | No | any, all, majority, quorum |
| `quorum_size` | Integer | No | Required for quorum type |
| `timeout` | Integer | No | Seconds before timeout (default: 86400) |
| `timeout_action` | String | No | reject, approve, escalate, skip |
| `escalation_chain` | Array | No | Escalation user IDs |
| `notification_channels` | Array | No | email, slack, sms |
| `context_data` | Hash | No | Data to show approvers |
| `approval_form` | Hash | No | Form for approvers |
| `instructions` | String | No | Approval instructions |

**Output**:
```ruby
{
  output: { approval_requested: true, approval_id, status: "pending" },
  data: { approval_type, required_approvals, deadline, workflow_paused: true },
  result: { approved: false, approval_status: "pending", requires_action: true }
}
```

### Validator Node

**File**: `validator.rb`

Validates data against schemas.

| Config Key | Type | Required | Description |
|------------|------|----------|-------------|
| `schema` | Hash | Yes | JSON Schema for validation |
| `data_path` | String | No | Path to data to validate |
| `strict_mode` | Boolean | No | Fail on extra properties |

---

## Error Handling

All nodes should handle errors gracefully:

```ruby
def perform_execution
  # ... execution logic ...
rescue StandardError => e
  log_error "Execution failed: #{e.message}"
  raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
        "#{node.node_type} execution failed: #{e.message}"
end
```

For non-fatal errors, return an error structure:

```ruby
{
  output: nil,
  result: { success: false, error_message: "Description" },
  metadata: { node_id: @node.node_id, node_type: "type", error: true }
}
```

---

**Document Status**: Complete
**Last Updated**: 2025-01-30
**Source**: `server/app/services/mcp/node_executors/`
