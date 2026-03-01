# Node Executor Reference

**Complete reference for 45+ workflow node executors**

**Version**: 3.0 | **Last Updated**: February 2026

---

## Overview

Node executors are located in `server/app/services/mcp/node_executors/`. Each executor inherits from `Base` and implements the `perform_execution` method. There are 45+ executors across 8 categories.

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
├── sub_workflow.rb         # Nested workflow execution
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
├── # DevOps (13)
├── ci_trigger.rb          # Trigger CI pipeline
├── ci_wait_status.rb      # Wait for CI status
├── ci_get_logs.rb         # Get CI logs
├── ci_cancel.rb           # Cancel CI run
├── git_branch.rb          # Git branch operations
├── git_checkout.rb        # Git checkout
├── git_commit_status.rb   # Git commit status
├── git_create_check.rb    # Create GitHub/Gitea check
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

### Validators (10)

Each node type has a corresponding validator in `server/app/services/ai/workflow_validators/`:

```
├── base_validator.rb
├── ai_agent_validator.rb
├── api_call_validator.rb
├── condition_validator.rb
├── delay_validator.rb
├── human_approval_validator.rb
├── loop_validator.rb
├── sub_workflow_validator.rb
├── transform_validator.rb
└── webhook_validator.rb
```

---

## Base Executor

**File**: `server/app/services/mcp/node_executors/base.rb`

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
  def log_info(message)
  def log_debug(message)
  def log_error(message)
end
```

### Output Format

All executors return:

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

## Control Flow Nodes (8)

### Start Node (`start.rb`)

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `input_variables` | Hash | No | Initial workflow variables |
| `trigger_type` | String | No | manual, scheduled, webhook |

### End Node (`end.rb`)

Aggregates all node outputs into final result.

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `output_variable` | String | No | Variable for final result |

### Condition Node (`condition.rb`)

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `condition_type` | String | No | expression, comparison, exists |
| `condition` | String | Yes* | Expression to evaluate |
| `left_variable` / `right_variable` | String | Yes* | Comparison operands |
| `operator` | String | No | ==, !=, >, <, >=, <= |

### Loop Node (`loop.rb`)

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `iteration_source` | String | Yes | Path to collection |
| `item_variable` | String | No | Current item var (default: "item") |
| `max_iterations` | Integer | No | Max iterations (default: 1000) |
| `execution_mode` | String | No | serial, parallel |
| `break_on_error` | Boolean | No | Stop on first error (default: true) |

### Split / Merge / Delay / Scheduler

| Node | Key Config |
|------|-----------|
| Split | `branches` (Array), `wait_for_all` (Boolean) |
| Merge | `merge_strategy` (wait_all, first_complete) |
| Delay | `delay_seconds` (Integer), `delay_until` (ISO8601) |
| Scheduler | `schedule` (cron/ISO8601), `timezone` |

---

## AI/Agent Nodes (2)

### AI Agent Node (`ai_agent.rb`)

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `agent_id` | String | Yes | AI agent ID |
| `prompt_template` | String | No | Prompt with `{{variables}}` |
| `input_mapping` | Hash | No | Variable to agent param mapping |
| `output_variable` | String | No | Store result |

**Output includes:** agent response, model, cost, tokens, duration, execution ID.

### Sub-Workflow Node (`sub_workflow.rb`)

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `workflow_id` | String | Yes | Sub-workflow ID |
| `input_mapping` | Hash | No | Variable mapping |
| `wait_for_completion` | Boolean | No | Wait for sub-workflow |

---

## Integration Nodes (9)

### API Call Node (`api_call.rb`)

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `url` | String | Yes | Target URL (supports `{{variables}}`) |
| `method` | String | No | GET, POST, PUT, PATCH, DELETE |
| `headers` | Hash | No | Request headers |
| `body` | Hash/String | No | Request body |
| `timeout_seconds` | Integer | No | Timeout (default: 30) |
| `retry_count` | Integer | No | Retries (max: 5) |
| `response_mapping` | String | No | Dot notation to extract value |

### Other Integration Nodes

| Node | Key Config |
|------|-----------|
| Webhook | `webhook_url`, `event_type`, `payload_template` |
| Notification | `channels` (email/slack/sms/push), `recipients`, `message` |
| Email | `to`, `subject`, `body`, `html_body`, `attachments` |
| Database | `operation` (query/insert/update/delete), `table`, `conditions` |
| File | `operation` (read/write/delete/copy), `path`, `content` |
| File Upload/Download | `path`, `destination`, `transform_type` |

---

## Content Nodes (9)

### Page Nodes

`page_create.rb`, `page_read.rb`, `page_update.rb`, `page_publish.rb`

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `page_id` | String | Yes* | Page ID (read/update/publish) |
| `title` | String | Yes* | Page title (create) |
| `content` | String | No | Page content |
| `status` | String | No | draft, published |

### KB Article Nodes

`kb_article_create.rb`, `kb_article_read.rb`, `kb_article_update.rb`, `kb_article_publish.rb`, `kb_article_search.rb`

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `article_id` | String | Yes* | Article ID |
| `title` | String | Yes* | Article title (create) |
| `query` | String | Yes* | Search query (search) |
| `tags` | Array | No | Article tags |

---

## DevOps Nodes (13)

### CI/CD Nodes

| Node | Key Config |
|------|-----------|
| CI Trigger | `provider`, `repository`, `workflow_id`, `ref` |
| CI Wait Status | `run_id`, `timeout_seconds` |
| CI Get Logs | `run_id` |
| CI Cancel | `run_id` |

### Git Nodes

| Node | Key Config |
|------|-----------|
| Git Branch | `repository`, `branch`, `base_branch` |
| Git Checkout | `repository`, `ref` |
| Git Commit Status | `repository`, `commit_sha`, `status` |
| Git Create Check | `repository`, `commit_sha`, `check_name` |
| Git Comment | `repository`, `pr_number`/`issue_number`, `comment` |
| Git Pull Request | `repository`, `title`, `source_branch`, `target_branch` |

### Deployment & Testing Nodes

| Node | Key Config |
|------|-----------|
| Deploy | `environment`, `service`, `version`, `strategy` (rolling/blue_green/canary) |
| Run Tests | `test_suite`, `filter`, `parallel` |
| Shell Command | `command`, `working_directory`, `environment`, `timeout_seconds` |

---

## MCP Nodes (4)

| Node | Key Config |
|------|-----------|
| MCP Tool | `server_id`, `tool_name`, `arguments` |
| MCP Prompt | `server_id`, `prompt_name`, `arguments` |
| MCP Resource | `server_id`, `resource_uri` |
| Integration Execute | `integration_id`, `action`, `parameters` |

---

## Utility Nodes (3)

### Transform Node (`transform.rb`)

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `transform_type` | String | No | map, filter, reduce, template |
| `input_variable` | String | No | Source variable |
| `mapping` | Hash | No | Field mapping (for map) |
| `filter_conditions` | Hash | No | Filter conditions |
| `reducer_function` | String | No | sum, count, first, last |
| `template` | String | No | Template string |

### Human Approval Node (`human_approval.rb`)

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `approvers` | Array | Yes | User IDs or role references |
| `approval_type` | String | No | any, all, majority, quorum |
| `timeout` | Integer | No | Seconds (default: 86400) |
| `timeout_action` | String | No | reject, approve, escalate, skip |
| `escalation_chain` | Array | No | Escalation user IDs |

### Validator Node (`validator.rb`)

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `schema` | Hash | Yes | JSON Schema for validation |
| `data_path` | String | No | Path to data to validate |
| `strict_mode` | Boolean | No | Fail on extra properties |

---

## Error Handling

```ruby
# Fatal errors — raise to fail the node
raise Mcp::AiWorkflowOrchestrator::NodeExecutionError,
      "#{node.node_type} execution failed: #{e.message}"

# Non-fatal errors — return error structure
{
  output: nil,
  result: { success: false, error_message: "Description" },
  metadata: { node_id: @node.node_id, node_type: "type", error: true }
}
```

---

**Document Status**: Complete
**Source**: `server/app/services/mcp/node_executors/`
