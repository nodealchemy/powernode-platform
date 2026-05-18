# WebSocket Channels (ActionCable)

> Authoritative reference for every ActionCable channel served by the Rails backend.

## Table of Contents

- [Overview](#overview)
- [Connection](#connection)
- [AI Channels](#ai-channels)
- [DevOps Channels](#devops-channels)
- [Platform Channels](#platform-channels)
- [Extension Channels](#extension-channels)
- [Frontend Integration](#frontend-integration)

## Overview

ActionCable channels provide real-time push from the Rails backend to subscribed clients. Every channel requires JWT authentication via the ActionCable connection and scopes data to the user's account unless explicitly noted. Channels live under `server/app/channels/`.

## Connection

The frontend uses a singleton `WebSocketManager` — one connection per user, shared across all subscriptions.

```typescript
import { useWebSocket } from '@/shared/hooks/useWebSocket';

const { subscribe, isConnected } = useWebSocket();
const unsubscribe = subscribe({
  channel: 'ChannelName',
  params: { id: resourceId },
  onMessage: (data) => { /* handle */ }
});
```

**Connection URL:** `ws[s]://{host}:3000/cable?token={jwt}`

## AI Channels

### AiAgentExecutionChannel

**File:** `server/app/channels/ai_agent_execution_channel.rb`

Monitors individual agent execution progress.

| Param | Required | Description |
|-------|----------|-------------|
| `execution_id` | Yes | Agent execution ID |

**Stream:** `ai_agent_execution:{execution_id}`

**Events:** Execution status changes, step completions, token streaming progress.

**Authorization:** Execution must belong to user's account.

### AiConversationChannel

**File:** `server/app/channels/ai_conversation_channel.rb`

Real-time messaging for AI chat conversations.

| Param | Required | Description |
|-------|----------|-------------|
| `conversation_id` | Yes | Conversation ID |

**Events:** User messages, AI responses, typing indicators.

**Authorization:** Conversation must belong to user's account.

### AiOrchestrationChannel

**File:** `server/app/channels/ai_orchestration_channel.rb`

Unified channel for agent executions, Ralph loops, worktree sessions, circuit breakers, and monitoring events.

| Param | Required | Description |
|-------|----------|-------------|
| `type` | Yes | `account`, `agent`, `monitoring`, `system`, `circuit_breaker`, `ralph_loop`, `worktree_session` |
| `id` | Yes | Resource ID |

**Streams:**
- `ai_orchestration:account:{id}` — account-wide monitoring
- `ai_orchestration:agent:{id}` — agent-scoped updates
- `ai_orchestration:ralph_loop:{id}` — Ralph loop lifecycle
- `ai_orchestration:worktree_session:{id}` — worktree session updates
- `ai_orchestration:circuit_breaker:{id}` — breaker state transitions
- `ai_orchestration:monitoring:{account_id}` — alerts and health events

**Events:**
- `agent.created` / `agent.updated` / `agent.deleted` / `agent.execution.started/completed/failed`
- `ralph_loop.started` / `progress` / `iteration_completed` / `task_status_changed` / `learning_added` / `completed` / `failed` / `paused` / `cancelled`
- `worktree_session.status_changed` / `provisioning` / `active` / `merging` / `completed` / `failed` / `cancelled` / `conflicts_detected`
- `circuit_breaker.state_changed` / `opened` / `closed` / `half_opened` / `failure` / `success` / `reset`
- `monitoring.alert.triggered` / `monitoring.metrics.updated` / `system.health.changed`

### AiStreamingChannel

**File:** `server/app/channels/ai_streaming_channel.rb`

Token-by-token streaming for AI provider responses.

| Param | Required | Description |
|-------|----------|-------------|
| `execution_id` | Conditional | Agent execution ID |
| `conversation_id` | Conditional | Conversation ID |

One of `execution_id` or `conversation_id` is required.

**Events:** Token chunks, completion signals.

## DevOps Channels

### CodeFactoryChannel

**File:** `server/app/channels/code_factory_channel.rb`

Code Factory run updates and code review state changes.

| Param | Required | Description |
|-------|----------|-------------|
| `type` | Yes | `run`, `contract`, `account`, or `review_state` |
| `id` | Yes | Resource ID |

**Authorization:** Resource must belong to user's account.

### DevopsPipelineChannel

**File:** `server/app/channels/devops_pipeline_channel.rb`

CI/CD pipeline execution status.

| Param | Required | Description |
|-------|----------|-------------|
| `account_id` | Yes | Account ID |
| `pipeline_id` | No | Specific pipeline (omit for all account pipelines) |

**Streams:**
- `devops_pipeline_{pipeline_id}` — specific pipeline
- `devops_account_{account_id}` — all account pipelines

### GitJobLogsChannel

**File:** `server/app/channels/git_job_logs_channel.rb`

Live streaming of Git pipeline job logs.

| Param | Required | Description |
|-------|----------|-------------|
| `repository_id` | Yes | Git repository ID |
| `pipeline_id` | Yes | Pipeline ID |
| `job_id` | Yes | Job ID |

**Stream:** `git_job_logs:{job_id}`

**Events:** `log.chunk`, `log.complete`, `log.error`

### MissionChannel

**File:** `server/app/channels/mission_channel.rb`

Mission lifecycle events: status/phase transitions, approval gates, and errors.

| Param | Required | Description |
|-------|----------|-------------|
| `type` | Yes | `mission` or `account` |
| `id` | Yes | Resource ID |

**Events:** `status_changed`, `phase_changed`, `approval_required`, `approval_resolved`, `error`.

## Platform Channels

### AnalyticsChannel

**File:** `server/app/channels/analytics_channel.rb`

Real-time analytics dashboard updates.

| Param | Required | Description |
|-------|----------|-------------|
| `account_id` | No | Account scope (omit for global, requires `admin.access`) |

**Events:** `analytics_connection_established`, metric updates.

### CustomerChannel

**File:** `server/app/channels/customer_channel.rb`

Customer data updates for admin users.

| Param | Required | Description |
|-------|----------|-------------|
| `account_id` | Yes | Account ID |

**Stream:** `customer_updates_{account_id}`

**Authorization:** Admin users only.

### McpChannel

**File:** `server/app/channels/mcp_channel.rb`

MCP protocol WebSocket transport. Unified channel handling MCP protocol messages directly. No required params.

### NotificationChannel

**File:** `server/app/channels/notification_channel.rb`

Real-time notification delivery.

| Param | Required | Description |
|-------|----------|-------------|
| `account_id` | Yes | Account ID |

**Events:** `connection_established`, new notifications.

### SubscriptionChannel

**File:** `server/app/channels/subscription_channel.rb`

Subscription status changes and billing events (active when the `business` extension is loaded).

| Param | Required | Description |
|-------|----------|-------------|
| `account_id` | Yes | Account ID |

**Events:** Subscription status changes, plan updates. Sends current subscription status on connect.

### TeamChannelChannel

**File:** `server/app/channels/team_channel_channel.rb`

Real-time team channel messaging (agent team communication).

| Param | Required | Description |
|-------|----------|-------------|
| `channel_id` | Yes | Team channel ID |

**Stream:** `team_channel:{channel_id}`

**Events:** `message_created`

**Authorization:** User's account must own the team.

### TeamExecutionChannel

**File:** `server/app/channels/team_execution_channel.rb`

Multi-agent team execution monitoring.

| Param | Required | Description |
|-------|----------|-------------|
| `team_id` | Yes | Agent team ID |

**Stream:** `team_execution:{team_id}`

**Events:** `execution_started`, `execution_progress`, `member_completed`, `execution_completed`, `execution_failed`

**Authorization:** Team must belong to user's account.

## Extension Channels

### SupplyChainChannel

**File:** `server/app/channels/supply_chain_channel.rb`

Supply chain extension events scoped to an account.

### TradingChannel

**File:** `server/app/channels/trading_channel.rb`

Trading extension events (strategy lifecycle, position updates, risk alerts) scoped to an account.

### TradingTrainingChannel

**File:** `server/app/channels/trading_training_channel.rb`

Trading training session events scoped to a session ID (live tick execution, learning extraction, phase transitions).

### WorkerDataChannel

**File:** `server/app/channels/worker_data_channel.rb`

Worker-to-server data streaming transport. Used by the standalone Sidekiq worker for bulk updates.

### WorkerToolDispatchChannel

**File:** `server/app/channels/worker_tool_dispatch_channel.rb`

Worker tool dispatch protocol channel. Used for pushing tool invocations from worker jobs to the server's tool registry.

## Frontend Integration

### Specialised Hooks

| Hook | Channel | Purpose |
|------|---------|---------|
| `useWebSocket` | Any | Generic WebSocket subscription |
| `useSubscriptionWebSocket` | `SubscriptionChannel` | Subscription status |
| `useCustomerWebSocket` | `CustomerChannel` | Customer updates |
| `useAnalyticsWebSocket` | `AnalyticsChannel` | Analytics events |
| `useMissionChannel` | `MissionChannel` | Mission lifecycle monitoring |
| `useRalphLoopChannel` | `AiOrchestrationChannel` | Ralph loop iteration monitoring |

### Connection Lifecycle

- **Single connection** — `WebSocketManager` maintains one connection per user.
- **Auto-reconnect** — exponential backoff (1s, 2s, 4s, 8s, …, max 10 attempts).
- **Token refresh** — automatic on 401 response.
- **Cleanup** — all subscriptions cleared on logout.

---

## Related docs

- [api/overview.md](overview.md) — HTTP API surface + auth
- [api/ai.md](ai.md) — AI orchestration controllers
- [../concepts/chat-and-realtime.md](../../concepts/chat-and-realtime.md) — Realtime design rationale
- [../guides/frontend.md](../../guides/frontend.md) — Frontend WebSocket patterns

## Materials previously at

- `docs/platform/ACTIONCABLE_CHANNELS_REFERENCE.md`

_Last verified: 2026-05-17_
