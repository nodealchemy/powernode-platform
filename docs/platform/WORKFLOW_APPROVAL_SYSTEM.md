# Workflow Approval System

**Human-in-the-loop approval workflows**

---

## Table of Contents

1. [Overview](#overview)
2. [Approval Types](#approval-types)
3. [Configuration](#configuration)
4. [Execution Flow](#execution-flow)
5. [Notification Channels](#notification-channels)
6. [Timeout Handling](#timeout-handling)
7. [API Reference](#api-reference)

---

## Overview

The Workflow Approval System enables human-in-the-loop workflows where execution pauses at designated points for human approval before continuing.

### Key Features

- **Multiple approval types**: Any, all, majority, quorum
- **Configurable timeouts**: Auto-actions on timeout
- **Escalation chains**: Escalate to next approver on timeout
- **Multi-channel notifications**: Email, Slack, SMS, push
- **Approval forms**: Collect additional data during approval
- **Audit trail**: Complete approval history

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Workflow Execution                       │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│              Human Approval Node                            │
│  - Creates approval request                                 │
│  - Pauses workflow execution                                │
│  - Sends notifications                                      │
└──────────────────────────┬──────────────────────────────────┘
                           │
                    ┌──────▼──────┐
                    │   PAUSED    │
                    │  (waiting)  │
                    └──────┬──────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
    ┌────▼────┐       ┌────▼────┐       ┌────▼────┐
    │ Approved │       │ Rejected │       │ Timeout │
    └────┬────┘       └────┬────┘       └────┬────┘
         │                 │                 │
    ┌────▼────┐       ┌────▼────┐       ┌────▼────┐
    │ Continue │       │  Fail   │       │ Timeout │
    │ Workflow │       │ Workflow│       │ Action  │
    └─────────┘       └─────────┘       └─────────┘
```

---

## Approval Types

### Any (Default)

Workflow continues when **any one** approver approves:

```ruby
{
  approval_type: "any",
  approvers: ["user_1", "user_2", "user_3"]
}
# Workflow continues when 1 approval received
```

### All

Workflow continues when **all** approvers approve:

```ruby
{
  approval_type: "all",
  approvers: ["user_1", "user_2", "user_3"]
}
# Workflow continues when 3 approvals received
```

### Majority

Workflow continues when **more than half** approve:

```ruby
{
  approval_type: "majority",
  approvers: ["user_1", "user_2", "user_3", "user_4", "user_5"]
}
# Workflow continues when 3+ approvals received
```

### Quorum

Workflow continues when **specified number** approve:

```ruby
{
  approval_type: "quorum",
  quorum_size: 2,
  approvers: ["user_1", "user_2", "user_3", "user_4"]
}
# Workflow continues when 2 approvals received
```

---

## Configuration

### Node Configuration Options

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `approvers` | Array | Yes | - | User IDs or role references |
| `approval_type` | String | No | "any" | any, all, majority, quorum |
| `quorum_size` | Integer | No | 1 | Required for quorum type |
| `timeout` | Integer | No | 86400 | Seconds before timeout (24h default) |
| `timeout_action` | String | No | "reject" | reject, approve, escalate, skip |
| `escalation_chain` | Array | No | [] | User IDs for escalation |
| `notification_channels` | Array | No | ["email"] | email, slack, sms, push |
| `context_data` | Hash | No | {} | Data to show approvers |
| `approval_form` | Hash | No | null | Form schema for additional input |
| `instructions` | String | No | "" | Instructions for approvers |

### Example Configuration

```json
{
  "node_type": "human_approval",
  "configuration": {
    "approvers": ["user_123", "user_456"],
    "approval_type": "any",
    "timeout": 3600,
    "timeout_action": "escalate",
    "escalation_chain": ["manager_789"],
    "notification_channels": ["email", "slack"],
    "context_data": {
      "request_type": "Expense Approval",
      "amount": "$1,500",
      "requestor": "John Doe"
    },
    "instructions": "Please review the expense request and approve if within policy.",
    "approval_form": {
      "fields": [
        {
          "name": "notes",
          "type": "textarea",
          "label": "Approval Notes",
          "required": false
        },
        {
          "name": "expense_code",
          "type": "select",
          "label": "Expense Code",
          "options": ["TRAVEL", "SUPPLIES", "OTHER"]
        }
      ]
    }
  }
}
```

---

## Execution Flow

### Node Execution

```ruby
class Mcp::NodeExecutors::HumanApproval < Base
  APPROVAL_TYPES = %w[any all majority quorum].freeze
  TIMEOUT_ACTIONS = %w[reject approve escalate skip].freeze

  def perform_execution
    approvers = resolve_approvers(configuration["approvers"])
    approval_type = configuration["approval_type"] || "any"

    # Validate configuration
    validate_configuration!(approvers, approval_type, timeout_action)

    # Create approval request
    result = create_approval_request(approval_context)

    # Send notifications
    send_approval_notifications(approval_context, result[:approval_id])

    # Return paused state
    {
      output: {
        approval_requested: true,
        approval_id: result[:approval_id],
        status: "pending"
      },
      data: {
        approval_type: approval_type,
        required_approvals: result[:required_approvals],
        deadline: result[:deadline],
        workflow_paused: true
      },
      metadata: {
        workflow_state: "paused_for_approval"
      }
    }
  end
end
```

### Approval Request Creation

```ruby
def create_approval_request(context)
  approval_id = "apr_#{SecureRandom.hex(16)}"

  required_approvals = case context[:approval_type]
  when "any" then 1
  when "all" then context[:approvers].length
  when "majority" then (context[:approvers].length / 2.0).ceil
  when "quorum" then [context[:quorum_size], context[:approvers].length].min
  end

  deadline = Time.current + context[:timeout].seconds

  # Create database record
  ApprovalRequest.create!(
    id: approval_id,
    workflow_run_id: @workflow_run.id,
    node_id: @node.node_id,
    status: "pending",
    required_approvals: required_approvals,
    deadline: deadline,
    approvers: context[:approvers].map { |id| { id: id, status: "pending" } },
    context_data: context[:context_data],
    form_schema: context[:approval_form]
  )

  {
    approval_id: approval_id,
    status: "pending",
    required_approvals: required_approvals,
    deadline: deadline.iso8601
  }
end
```

---

## Notification Channels

### Email Notifications

```ruby
def send_email_notification(approver, approval_request)
  ApprovalMailer.approval_requested(
    to: approver.email,
    approval_id: approval_request.id,
    workflow_name: @workflow.name,
    context_data: approval_request.context_data,
    deadline: approval_request.deadline,
    approve_url: approval_url(approval_request, action: "approve"),
    reject_url: approval_url(approval_request, action: "reject")
  ).deliver_later
end
```

### Slack Notifications

```ruby
def send_slack_notification(approver, approval_request)
  SlackNotifier.post(
    channel: approver.slack_channel,
    blocks: [
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: "*Approval Required*: #{@workflow.name}"
        }
      },
      {
        type: "section",
        fields: approval_request.context_data.map do |k, v|
          { type: "mrkdwn", text: "*#{k}*: #{v}" }
        end
      },
      {
        type: "actions",
        elements: [
          {
            type: "button",
            text: { type: "plain_text", text: "Approve" },
            style: "primary",
            action_id: "approve_#{approval_request.id}"
          },
          {
            type: "button",
            text: { type: "plain_text", text: "Reject" },
            style: "danger",
            action_id: "reject_#{approval_request.id}"
          }
        ]
      }
    ]
  )
end
```

---

## Timeout Handling

### Timeout Actions

| Action | Behavior |
|--------|----------|
| `reject` | Mark approval as rejected, fail workflow |
| `approve` | Auto-approve and continue workflow |
| `escalate` | Escalate to next user in chain |
| `skip` | Skip approval step, continue workflow |

### Timeout Processing Job

```ruby
class ApprovalTimeoutJob < ApplicationJob
  def perform(approval_request_id)
    request = ApprovalRequest.find(approval_request_id)
    return if request.completed?

    case request.timeout_action
    when "reject"
      request.update!(status: "timeout_rejected")
      WorkflowResumer.fail(request.workflow_run, "Approval timed out")

    when "approve"
      request.update!(status: "timeout_approved")
      WorkflowResumer.continue(request.workflow_run, approved: true)

    when "escalate"
      escalate_approval(request)

    when "skip"
      request.update!(status: "skipped")
      WorkflowResumer.continue(request.workflow_run, skipped: true)
    end
  end

  def escalate_approval(request)
    next_approver = request.escalation_chain.shift
    return timeout_reject(request) unless next_approver

    request.update!(
      approvers: request.approvers + [{ id: next_approver, status: "pending" }],
      deadline: Time.current + request.timeout.seconds
    )

    send_escalation_notifications(request, next_approver)
  end
end
```

---

## API Reference

### Submit Approval

```http
POST /api/v1/approvals/:id/submit
```

**Request Body:**
```json
{
  "action": "approve",
  "notes": "Approved per policy",
  "form_data": {
    "expense_code": "TRAVEL"
  }
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "approval_id": "apr_abc123",
    "status": "approved",
    "submitted_by": "user_123",
    "submitted_at": "2025-01-30T10:30:00Z",
    "workflow_resumed": true
  }
}
```

### Get Approval Status

```http
GET /api/v1/approvals/:id
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "apr_abc123",
    "status": "pending",
    "approval_type": "any",
    "required_approvals": 1,
    "current_approvals": 0,
    "current_rejections": 0,
    "deadline": "2025-01-31T10:30:00Z",
    "approvers": [
      { "id": "user_123", "status": "pending" },
      { "id": "user_456", "status": "pending" }
    ],
    "context_data": {
      "request_type": "Expense Approval",
      "amount": "$1,500"
    },
    "form_schema": { ... },
    "workflow": {
      "id": "wf_xyz",
      "name": "Expense Approval Workflow"
    }
  }
}
```

### List Pending Approvals

```http
GET /api/v1/approvals/pending
```

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "apr_abc123",
      "workflow_name": "Expense Approval",
      "deadline": "2025-01-31T10:30:00Z",
      "context_data": { ... }
    }
  ],
  "meta": {
    "pagination": {
      "total_count": 5,
      "current_page": 1
    }
  }
}
```

---

## Output Structure

When the Human Approval node executes:

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
    approval_type: "any",
    required_approvals: 1,
    current_approvals: 0,
    approvers_count: 3,
    deadline: "2025-01-31T10:30:00Z",
    timeout_action: "reject",
    has_form: true,
    notification_channels: ["email", "slack"],
    created_at: "2025-01-30T10:30:00Z",
    workflow_paused: true
  },
  result: {
    approved: false,
    approval_status: "pending",
    approval_id: "apr_abc123",
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

When approval is submitted, the workflow resumes with:

```ruby
{
  output: {
    approved: true,
    approval_id: "apr_abc123",
    approved_by: "user_123",
    form_data: { expense_code: "TRAVEL" }
  },
  data: {
    total_approvals: 1,
    total_rejections: 0,
    approval_duration_seconds: 3600
  },
  metadata: {
    node_id: "approval_1",
    node_type: "human_approval",
    completed_at: "2025-01-30T11:30:00Z"
  }
}
```

---

**Document Status**: Complete
**Last Updated**: 2025-01-30
**Source**: `server/app/services/mcp/node_executors/human_approval.rb`
