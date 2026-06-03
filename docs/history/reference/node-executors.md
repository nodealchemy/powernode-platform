# Node Executor Reference

> Authoritative reference for workflow node executors used by the MCP workflow orchestrator.

## Table of Contents

- [Overview](#overview)
- [Base Executor](#base-executor)
- [Control Flow Nodes](#control-flow-nodes)
- [AI / Agent Nodes](#ai--agent-nodes)
- [Integration Nodes](#integration-nodes)
- [Content Nodes](#content-nodes)
- [DevOps Nodes](#devops-nodes)
- [MCP Nodes](#mcp-nodes)
- [Utility Nodes](#utility-nodes)
- [Error Handling](#error-handling)

## Overview

Node executors live under the MCP services tree. Each executor inherits from `Base` and implements `perform_execution`. Each node type has a paired validator alongside it.

### Directory Layout

```
server/app/services/mcp/node_executors/
├── base.rb                 # Base class for all executors
├── mcp_base.rb             # Extended base for MCP nodes
│
├── # Control Flow (8)
├── start.rb, end.rb, condition.rb, loop.rb, split.rb, merge.rb, delay.rb, scheduler.rb
│
├── # AI / Agent (2)
├── ai_agent.rb, sub_workflow.rb
│
├── # Integration (9)
├── api_call.rb, webhook.rb, notification.rb, email.rb, database.rb
├── file.rb, file_upload.rb, file_download.rb, file_transform.rb
│
├── # Content (9)
├── page_create.rb, page_read.rb, page_update.rb, page_publish.rb
├── kb_article_create.rb, kb_article_read.rb, kb_article_update.rb,
├── kb_article_publish.rb, kb_article_search.rb
│
├── # DevOps (13)
├── ci_trigger.rb, ci_wait_status.rb, ci_get_logs.rb, ci_cancel.rb
├── git_branch.rb, git_checkout.rb, git_commit_status.rb, git_create_check.rb,
├── git_comment.rb, git_pull_request.rb
├── deploy.rb, run_tests.rb, shell_command.rb
│
├── # MCP (4)
├── mcp_tool.rb, mcp_prompt.rb, mcp_resource.rb, integration_execute.rb
│
└── # Utility (3)
    transform.rb, human_approval.rb, validator.rb
```

### Validators

Each node type maps to a validator:

```
base_validator.rb
ai_agent_validator.rb
api_call_validator.rb
condition_validator.rb
delay_validator.rb
human_approval_validator.rb
loop_validator.rb
sub_workflow_validator.rb
transform_validator.rb
webhook_validator.rb
```

## Base Executor

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

### Output Contract

All executors return:

```ruby
{
  output: <primary_result>,    # REQUIRED
  data: { },                   # Optional
  result: { },                 # Optional
  metadata: {                  # REQUIRED
    node_id: @node.node_id,
    node_type: "<type>",
    executed_at: Time.current.iso8601
  }
}
```

## Control Flow Nodes

### Start Node — `start.rb`

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `input_variables` | Hash | No | Initial workflow variables |
| `trigger_type` | String | No | `manual`, `scheduled`, `webhook` |

### End Node — `end.rb`

Aggregates all node outputs into final result.

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `output_variable` | String | No | Variable for final result |

### Condition Node — `condition.rb`

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `condition_type` | String | No | `expression`, `comparison`, `exists` |
| `condition` | String | Yes\* | Expression to evaluate |
| `left_variable` / `right_variable` | String | Yes\* | Comparison operands |
| `operator` | String | No | `==`, `!=`, `>`, `<`, `>=`, `<=` |

### Loop Node — `loop.rb`

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `iteration_source` | String | Yes | Path to collection |
| `item_variable` | String | No | Current item var (default: `item`) |
| `max_iterations` | Integer | No | Max iterations (default: 1000) |
| `execution_mode` | String | No | `serial`, `parallel` |
| `break_on_error` | Boolean | No | Stop on first error (default: true) |

### Split / Merge / Delay / Scheduler

| Node | Key Config |
|------|-----------|
| Split | `branches` (Array), `wait_for_all` (Boolean) |
| Merge | `merge_strategy` (`wait_all`, `first_complete`) |
| Delay | `delay_seconds` (Integer), `delay_until` (ISO8601) |
| Scheduler | `schedule` (cron / ISO8601), `timezone` |

## AI / Agent Nodes

### AI Agent Node — `ai_agent.rb`

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `agent_id` | String | Yes | AI agent ID |
| `prompt_template` | String | No | Prompt with `{{variables}}` |
| `input_mapping` | Hash | No | Variable to agent param mapping |
| `output_variable` | String | No | Store result |

**Output includes:** agent response, model, cost, tokens, duration, execution ID.

### Sub-Workflow Node — `sub_workflow.rb`

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `workflow_id` | String | Yes | Sub-workflow ID |
| `input_mapping` | Hash | No | Variable mapping |
| `wait_for_completion` | Boolean | No | Wait for sub-workflow |

## Integration Nodes

### API Call Node — `api_call.rb`

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `url` | String | Yes | Target URL (supports `{{variables}}`) |
| `method` | String | No | `GET`, `POST`, `PUT`, `PATCH`, `DELETE` |
| `headers` | Hash | No | Request headers |
| `body` | Hash / String | No | Request body |
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
| File Upload / Download | `path`, `destination`, `transform_type` |

## Content Nodes

### Page Nodes

`page_create.rb`, `page_read.rb`, `page_update.rb`, `page_publish.rb`

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `page_id` | String | Yes\* | Page ID (read/update/publish) |
| `title` | String | Yes\* | Page title (create) |
| `content` | String | No | Page content |
| `status` | String | No | `draft`, `published` |

### KB Article Nodes

`kb_article_create.rb`, `kb_article_read.rb`, `kb_article_update.rb`, `kb_article_publish.rb`, `kb_article_search.rb`

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `article_id` | String | Yes\* | Article ID |
| `title` | String | Yes\* | Article title (create) |
| `query` | String | Yes\* | Search query (search) |
| `tags` | Array | No | Article tags |

## DevOps Nodes

### CI / CD Nodes

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
| Git Comment | `repository`, `pr_number` / `issue_number`, `comment` |
| Git Pull Request | `repository`, `title`, `source_branch`, `target_branch` |

### Deployment & Testing Nodes

| Node | Key Config |
|------|-----------|
| Deploy | `environment`, `service`, `version`, `strategy` (`rolling`, `blue_green`, `canary`) |
| Run Tests | `test_suite`, `filter`, `parallel` |
| Shell Command | `command`, `working_directory`, `environment`, `timeout_seconds` |

## MCP Nodes

| Node | Key Config |
|------|-----------|
| MCP Tool | `server_id`, `tool_name`, `arguments` |
| MCP Prompt | `server_id`, `prompt_name`, `arguments` |
| MCP Resource | `server_id`, `resource_uri` |
| Integration Execute | `integration_id`, `action`, `parameters` |

## Utility Nodes

### Transform Node — `transform.rb`

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `transform_type` | String | No | `map`, `filter`, `reduce`, `template` |
| `input_variable` | String | No | Source variable |
| `mapping` | Hash | No | Field mapping (for `map`) |
| `filter_conditions` | Hash | No | Filter conditions |
| `reducer_function` | String | No | `sum`, `count`, `first`, `last` |
| `template` | String | No | Template string |

### Human Approval Node — `human_approval.rb`

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `approvers` | Array | Yes | User IDs or role references |
| `approval_type` | String | No | `any`, `all`, `majority`, `quorum` |
| `timeout` | Integer | No | Seconds (default: 86400) |
| `timeout_action` | String | No | `reject`, `approve`, `escalate`, `skip` |
| `escalation_chain` | Array | No | Escalation user IDs |

### Validator Node — `validator.rb`

| Config | Type | Required | Description |
|--------|------|----------|-------------|
| `schema` | Hash | Yes | JSON Schema for validation |
| `data_path` | String | No | Path to data to validate |
| `strict_mode` | Boolean | No | Fail on extra properties |

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

## Related docs

- [plugin-system.md](plugin-system.md) — Custom node types via plugins
- [../concepts/agents-and-autonomy.md](../concepts/agents-and-autonomy.md) — Agent design
- [../guides/backend.md](../guides/backend.md) — Service patterns

## Materials previously at

- `docs/backend/NODE_EXECUTOR_REFERENCE.md`

_Last verified: 2026-05-17_
