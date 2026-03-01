# ActionCable Channels Reference

17 WebSocket channels for real-time communication. All require JWT authentication via ActionCable connection.

---

## Connection

Frontend uses a singleton `WebSocketManager` — one connection per user, shared across all subscriptions.

```typescript
import { useWebSocket } from '@/shared/hooks/useWebSocket';

const { subscribe, isConnected } = useWebSocket();
const unsubscribe = subscribe({
  channel: 'ChannelName',
  params: { id: resourceId },
  onMessage: (data) => { /* handle */ }
});
```

---

## AI Channels

### AiAgentExecutionChannel

**File**: `server/app/channels/ai_agent_execution_channel.rb`

Monitors individual agent execution progress.

| Param | Required | Description |
|-------|----------|-------------|
| `execution_id` | Yes | Agent execution ID |

**Stream**: `ai_agent_execution:{execution_id}`

**Events**: Execution status changes, step completions, token streaming progress.

**Authorization**: Execution must belong to user's account.

---

### AiConversationChannel

**File**: `server/app/channels/ai_conversation_channel.rb`

Real-time messaging for AI chat conversations.

| Param | Required | Description |
|-------|----------|-------------|
| `conversation_id` | Yes | Conversation ID |

**Events**: User messages, AI responses, typing indicators.

**Authorization**: Conversation must belong to user's account.

---

### AiOrchestrationChannel

**File**: `server/app/channels/ai_orchestration_channel.rb`

Unified channel for all AI orchestration events. Replaces several legacy channels.

| Param | Required | Description |
|-------|----------|-------------|
| `type` | Yes | Resource type: `workflow`, `workflow_run`, `agent`, `account` |
| `id` | Yes | Resource ID |

**Streams**:
- `ai_orchestration:workflow_run:{id}` — Run-specific updates
- `ai_orchestration:workflow:{id}` — Workflow-level updates
- `ai_orchestration:account:{id}` — Account-wide monitoring

**Events**:
- `workflow.run.created` / `workflow.run.status.changed` / `workflow.run.completed`
- `workflow.node.execution.updated`

---

### AiStreamingChannel

**File**: `server/app/channels/ai_streaming_channel.rb`

Token-by-token streaming for AI provider responses.

| Param | Required | Description |
|-------|----------|-------------|
| `execution_id` | Conditional | Agent execution ID |
| `conversation_id` | Conditional | Conversation ID |

One of `execution_id` or `conversation_id` is required.

**Events**: Token chunks, completion signals.

---

### AiWorkflowMonitoringChannel

**File**: `server/app/channels/ai_workflow_monitoring_channel.rb`

Workflow monitoring and analytics. Specialized wrapper around AiOrchestrationChannel.

| Param | Required | Description |
|-------|----------|-------------|
| `workflow_id` | No | Specific workflow (omit for account-wide) |

**Authorization**: Requires monitoring permission.

---

### AiWorkflowOrchestrationChannel

**File**: `server/app/channels/ai_workflow_orchestration_channel.rb`

Account-level workflow orchestration events.

No required params — subscribes to account-level stream automatically.

**Stream**: `ai_orchestration:account:{account_id}`

---

## DevOps Channels

### CodeFactoryChannel

**File**: `server/app/channels/code_factory_channel.rb`

Code Factory run updates and code review state changes.

| Param | Required | Description |
|-------|----------|-------------|
| `type` | Yes | `run`, `contract`, `account`, or `review_state` |
| `id` | Yes | Resource ID |

**Authorization**: Resource must belong to user's account.

---

### DevopsPipelineChannel

**File**: `server/app/channels/devops_pipeline_channel.rb`

CI/CD pipeline execution status.

| Param | Required | Description |
|-------|----------|-------------|
| `account_id` | Yes | Account ID |
| `pipeline_id` | No | Specific pipeline (omit for all account pipelines) |

**Streams**:
- `devops_pipeline_{pipeline_id}` — Specific pipeline
- `devops_account_{account_id}` — All account pipelines

---

### GitJobLogsChannel

**File**: `server/app/channels/git_job_logs_channel.rb`

Live streaming of Git pipeline job logs.

| Param | Required | Description |
|-------|----------|-------------|
| `repository_id` | Yes | Git repository ID |
| `pipeline_id` | Yes | Pipeline ID |
| `job_id` | Yes | Job ID |

**Stream**: `git_job_logs:{job_id}`

**Events**: `log.chunk`, `log.complete`, `log.error`

---

### MissionChannel

**File**: `server/app/channels/mission_channel.rb`

Ralph mission progress updates.

| Param | Required | Description |
|-------|----------|-------------|
| `type` | Yes | `mission` or `account` |
| `id` | Yes | Resource ID |

---

## Platform Channels

### AnalyticsChannel

**File**: `server/app/channels/analytics_channel.rb`

Real-time analytics dashboard updates.

| Param | Required | Description |
|-------|----------|-------------|
| `account_id` | No | Account scope (omit for global, requires admin.access) |

**Events**: `analytics_connection_established`, metric updates.

---

### CustomerChannel

**File**: `server/app/channels/customer_channel.rb`

Customer data updates for admin users.

| Param | Required | Description |
|-------|----------|-------------|
| `account_id` | Yes | Account ID |

**Stream**: `customer_updates_{account_id}`

**Authorization**: Admin users only.

---

### McpChannel

**File**: `server/app/channels/mcp_channel.rb`

MCP protocol WebSocket transport. Unified channel replacing legacy AI orchestration channels.

No required params. Handles MCP protocol messages directly.

---

### NotificationChannel

**File**: `server/app/channels/notification_channel.rb`

Real-time notification delivery.

| Param | Required | Description |
|-------|----------|-------------|
| `account_id` | Yes | Account ID |

**Events**: `connection_established`, new notifications.

---

### SubscriptionChannel

**File**: `server/app/channels/subscription_channel.rb`

Subscription status changes and billing events.

| Param | Required | Description |
|-------|----------|-------------|
| `account_id` | Yes | Account ID |

**Events**: Subscription status changes, plan updates. Sends current subscription status on connect.

---

### TeamChannelChannel

**File**: `server/app/channels/team_channel_channel.rb`

Real-time team channel messaging (agent team communication).

| Param | Required | Description |
|-------|----------|-------------|
| `channel_id` | Yes | Team channel ID |

**Stream**: `team_channel:{channel_id}`

**Events**: `message_created`

**Authorization**: User's account must own the team.

---

### TeamExecutionChannel

**File**: `server/app/channels/team_execution_channel.rb`

Multi-agent team execution monitoring.

| Param | Required | Description |
|-------|----------|-------------|
| `team_id` | Yes | Agent team ID |

**Stream**: `team_execution:{team_id}`

**Events**: `execution_started`, `execution_progress`, `member_completed`, `execution_completed`, `execution_failed`

**Authorization**: Team must belong to user's account.

---

## Frontend Integration

### Specialized Hooks

| Hook | Channel | Purpose |
|------|---------|---------|
| `useWebSocket` | Any | Generic WebSocket subscription |
| `useSubscriptionWebSocket` | SubscriptionChannel | Subscription status |
| `useCustomerWebSocket` | CustomerChannel | Customer updates |
| `useAnalyticsWebSocket` | AnalyticsChannel | Analytics events |
| `useWorkflowExecution` | AiOrchestrationChannel | Workflow execution monitoring |

### Connection Lifecycle

- **Single connection**: WebSocketManager maintains one connection per user
- **Auto-reconnect**: Exponential backoff (1s, 2s, 4s, 8s..., max 10 attempts)
- **Token refresh**: Automatic on 401 response
- **Cleanup**: All subscriptions cleared on logout

See [WEBSOCKET_AND_REALTIME.md](WEBSOCKET_AND_REALTIME.md) for architecture details.
