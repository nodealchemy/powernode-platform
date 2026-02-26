# WebSocket & Real-Time Architecture

**Single connection pattern, workflow execution updates, and testing procedures**

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Singleton Connection Pattern](#singleton-connection-pattern)
3. [Workflow WebSocket Integration](#workflow-websocket-integration)
4. [Event Types & Message Formats](#event-types--message-formats)
5. [Testing & Debugging](#testing--debugging)
6. [Troubleshooting Guide](#troubleshooting-guide)

---

## Architecture Overview

The Powernode frontend uses a **singleton WebSocket connection pattern** to share a single WebSocket connection across all components. This reduces resource usage by 70-80% and improves reliability.

### Core Components

1. **WebSocketManager** (`frontend/src/shared/services/WebSocketManager.ts`)
   - Singleton service managing the WebSocket connection
   - Handles connection lifecycle (connect, disconnect, reconnect)
   - Routes messages to appropriate subscribers

2. **useWebSocket Hook** (`frontend/src/shared/hooks/useWebSocket.ts`)
   - React hook providing WebSocket functionality
   - Uses WebSocketManager singleton internally
   - 100% backward compatible API

3. **Specialized Hooks** (all use `useWebSocket` internally)
   - `useSubscriptionWebSocket` - Subscription management
   - `useCustomerWebSocket` - Customer channel
   - `useAnalyticsWebSocket` - Analytics events
   - `useSettingsWebSocket` - Settings updates
   - `useWorkflowExecution` - Workflow execution updates

### Connection Flow

```
User Login
    ↓
First Component Mounts (calls useWebSocket)
    ↓
WebSocketManager.initialize()
  - Creates WebSocket connection
  - Authenticates with token
    ↓
Subsequent Components Mount
  - Reuses existing connection ✓
    ↓
Components Subscribe to Different Channels
  - All use same connection
```

### Performance Metrics

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Connections per user | 3-5 | 1 | 70-80% reduction |
| Memory per user | 6-10MB | 2MB | 70% reduction |
| Backend connections (500 users) | 1,500-2,500 | 500 | 75% reduction |

---

## Singleton Connection Pattern

### Basic Usage

```typescript
import { useWebSocket } from '@/shared/hooks/useWebSocket';

function MyComponent() {
  const { isConnected, subscribe, sendMessage } = useWebSocket();

  useEffect(() => {
    const unsubscribe = subscribe({
      channel: 'MyChannel',
      params: { user_id: userId },
      onMessage: (data) => {
        console.log('Received:', data);
      },
      onError: (error) => {
        console.error('Channel error:', error);
      }
    });

    return unsubscribe;
  }, [subscribe]);

  return <div>Status: {isConnected ? 'Connected' : 'Disconnected'}</div>;
}
```

### Subscription Management

The WebSocketManager maintains a map of channel subscriptions:

```typescript
// Internal structure
subscriptions: Map<string, Set<ChannelSubscription>>

// Key format: "channel::params"
// Example: "CustomerChannel::{"user_id":"123"}"
```

Multiple components can subscribe to the same channel, and each receives the same messages.

### Connection Lifecycle

**Initialization**:
- First component calls `wsManager.initialize(config)`
- Manager creates WebSocket connection
- Manager stores config for reconnections

**Reconnection**:
- Automatic exponential backoff (1s, 2s, 4s, 8s, ...)
- Maximum 10 reconnection attempts
- Resubscribes to all channels on reconnect

**Token Refresh**:
- Manager detects unauthorized (401) response
- Triggers token refresh via Redux
- Reconnects with new token (transparent to components)

**Cleanup**:
- User logs out → Manager calls `disconnect()`
- Closes connection cleanly
- Clears all subscriptions

---

## Workflow WebSocket Integration

### Channel Architecture

All workflow updates flow through the **AiOrchestrationChannel**:

```typescript
// Workflow-level subscription
subscribe({
  channel: 'AiOrchestrationChannel',
  params: { type: 'workflow', id: workflowId },
  onMessage: handleWorkflowUpdate
});

// Run-level subscription
subscribe({
  channel: 'AiOrchestrationChannel',
  params: { type: 'workflow_run', id: runId },
  onMessage: handleRunUpdate
});
```

### Multi-Stream Broadcasting

Single events broadcast to three streams simultaneously:

1. `ai_orchestration:workflow_run:{run_id}` - Run-specific updates
2. `ai_orchestration:workflow:{workflow_id}` - Workflow-level updates
3. `ai_orchestration:account:{account_id}` - Account-wide monitoring

### Key Backend Methods

**AiOrchestrationChannel** (`server/app/channels/ai_orchestration_channel.rb`):
```ruby
def serialize_node_execution(execution)
  {
    id: execution.id,  # CRITICAL: Must match API response format
    execution_id: execution.execution_id,
    status: execution.status,
    # ... rest of fields
  }
end
```

### Frontend Integration Points

**WorkflowDetailPage** (Lines 94-183):
```typescript
const unsubscribeFn = subscribe({
  channel: 'AiOrchestrationChannel',
  params: { type: 'workflow', id },
  onMessage: handleWorkflowUpdate
});
```

**WorkflowExecutionForm** (Lines 270-289):
```typescript
const unsubscribe = subscribe({
  channel: 'AiOrchestrationChannel',
  params: { type: 'workflow', id: workflow.id },
  onMessage: (message) => handleWorkflowRunUpdate(message)
});
```

**useWorkflowExecution Hook** (Lines 82-94):
```typescript
const unsubscribe = subscribe({
  channel: 'AiOrchestrationChannel',
  params: { type: 'workflow_run', id: workflowRunId },
  onMessage: handleExecutionMessage
});
```

---

## Event Types & Message Formats

### Standardized Event Types

```
workflow.run.created
workflow.run.status.changed
workflow.run.completed
workflow.node.execution.updated
```

### Unified Message Format

```json
{
  "event": "workflow.run.status.changed",
  "resource_type": "workflow_run",
  "resource_id": "run-id",
  "payload": {
    "workflow_run": { /* run data */ },
    "workflow_stats": { /* stats */ }
  },
  "timestamp": "2025-10-11T21:07:00Z"
}
```

### Node Execution Updates

```json
{
  "event": "workflow.node.execution.updated",
  "resource_type": "node_execution",
  "resource_id": "execution-id",
  "payload": {
    "id": "execution-id",
    "execution_id": "execution-id",
    "status": "completed",
    "node_name": "Start",
    "node_type": "start",
    "started_at": "2025-10-11T21:07:00Z",
    "completed_at": "2025-10-11T21:07:01Z",
    "duration_ms": 1000
  }
}
```

---

## Testing & Debugging

### Quick Test Procedure

**1. Start Backend Monitoring**:
```bash
journalctl -u powernode-backend@default -f | grep -E "Broadcasting|workflow.run|node.execution"
```

**2. Enable Browser Debugging** (DevTools Console):
```javascript
console.log('🔍 Monitoring WebSocket...');
const original = WebSocket.prototype.onmessage;
WebSocket.prototype.onmessage = function(event) {
  try {
    const data = JSON.parse(event.data);
    if (data.message?.event) {
      console.log('📡', data.message.event, data.message.payload);
    }
  } catch(e) {}
  return original?.call(this, event);
};
```

**3. Execute Workflow and Verify**:
- New run appears immediately in history
- Status badges update: `pending` → `running` → `completed`
- Node badges change: ⏳ → ▶️ → ✅
- Progress bar fills as nodes complete

### Expected Console Output

```
📊 WORKFLOW RUN UPDATE #1
  event: "workflow.run.status.changed"
  status: "running"
  progress: "0/5"

🔧 NODE EXECUTION UPDATE #1
  nodeId: "start_1"
  nodeName: "Start"
  status: "running"

🔧 NODE EXECUTION UPDATE #2
  nodeId: "start_1"
  status: "completed"
```

### Expected Backend Logs

```
[STATE_MACHINE] Broadcasting status change: pending -> initializing
[STATE_MACHINE] Broadcasting status change: initializing -> running
✅ BROADCASTING STATUS CHANGE: [execution-id] pending -> running
Broadcasting node status change: [node-id] -> running (Start)
[ActionCable] Broadcasting to ai_orchestration:workflow_run:[id]
[ActionCable] Broadcasting to ai_orchestration:workflow:[id]
```

### Debug Console Commands

```javascript
// Show WebSocket summary
wsDebugSummary()

// Check all connections
Array.from(document.querySelectorAll('*')).forEach(el => {
  if (el._websocket) console.log('WebSocket found:', el);
});

// Force reconnect
window.location.reload()
```

### Single Connection Verification

```javascript
// In browser console (before login)
window.wsConnectionCount = 0;

// Intercept WebSocket constructor
const OriginalWebSocket = window.WebSocket;
window.WebSocket = function(...args) {
  window.wsConnectionCount++;
  console.log('WebSocket connection #' + window.wsConnectionCount);
  return new OriginalWebSocket(...args);
};

// Login and navigate - should only see 1 connection!
```

---

## Troubleshooting Guide

### Node Badges Not Updating

1. **Check WebSocket Connection**:
   - Console: `wsDebugSummary()` should show `Active Connections: 1` with `🟢 OPEN`

2. **Verify Subscription**:
   - Look for `✅ SUBSCRIPTION CONFIRMED`
   - Channel: `AiOrchestrationChannel`
   - Params should include workflow ID

3. **Check Backend Broadcasts**:
   - Logs should show `Broadcasting node status change`
   - If missing, check `ai_workflow_node_execution.rb` callbacks

4. **Verify Frontend Handler**:
   - `WorkflowExecutionDetails.tsx` should handle `workflow.node.execution.updated`

### Execution History Not Updating

1. **Check Workflow-Level Subscription**:
   - Should use: `{ type: 'workflow', id: workflowId }`
   - NOT: `workflow_${id}` (old format)

2. **Verify Broadcast Stream**:
   - Backend should broadcast to: `ai_orchestration:workflow:[id]`

### Common Issues Reference

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| No WebSocket messages | Not subscribed | Refresh page, check subscription |
| Broadcasts sent but not received | Wrong channel/params | Verify AiOrchestrationChannel |
| Node badges static | Missing `id` in payload | Check serialize_node_execution |
| History list static | Wrong subscription format | Use AiOrchestrationChannel |
| "Connection lost unexpectedly" | Network issue | Check backend, CORS errors |
| "Session expired" | Token refresh failed | Re-login |
| Messages not received | Wrong channel name | Verify matches backend |

### Key Insights

**ActionCable Channel Architecture Critical Points**:

1. **Channel Class Requirement**: Clients MUST subscribe to actual channel classes (like `AiOrchestrationChannel`), not arbitrary stream names.

2. **Payload Consistency**: WebSocket payloads MUST match API response format exactly. Missing fields break frontend state management.

3. **Multi-Stream Strategy**: Broadcasting to multiple stream levels (run, workflow, account) ensures all UI components receive updates.

4. **Event Unification**: Consistent event names (`workflow.run.*`) reduces complexity.

5. **Manual Broadcast Requirement**: When using `update_columns` to bypass callbacks, manual broadcasting is essential.

---

## All 17 Channels

For detailed per-channel reference (subscription params, streams, events), see [ACTIONCABLE_CHANNELS_REFERENCE.md](ACTIONCABLE_CHANNELS_REFERENCE.md).

| Channel | Subscription Params | Purpose |
|---------|-------------------|---------|
| AiAgentExecutionChannel | `execution_id` | Agent execution monitoring |
| AiConversationChannel | `conversation_id` | AI chat messaging |
| AiOrchestrationChannel | `type`, `id` | Unified AI orchestration |
| AiStreamingChannel | `execution_id` / `conversation_id` | Token streaming |
| AiWorkflowMonitoringChannel | `workflow_id` | Workflow analytics |
| AiWorkflowOrchestrationChannel | — | Account workflow events |
| AnalyticsChannel | `account_id` | Real-time analytics |
| CodeFactoryChannel | `type`, `id` | Code Factory updates |
| CustomerChannel | `account_id` | Customer data (admin) |
| DevopsPipelineChannel | `account_id`, `pipeline_id` | CI/CD pipeline status |
| GitJobLogsChannel | `repository_id`, `pipeline_id`, `job_id` | Live log streaming |
| McpChannel | — | MCP protocol transport |
| MissionChannel | `type`, `id` | Mission progress |
| NotificationChannel | `account_id` | Notifications |
| SubscriptionChannel | `account_id` | Subscription changes |
| TeamChannelChannel | `channel_id` | Team messaging |
| TeamExecutionChannel | `team_id` | Team execution monitoring |

---

## Files Reference

### Backend
- `server/app/channels/` - 17 channel files + `application_cable/`
- `server/app/channels/ai_orchestration_channel.rb` - Main unified AI channel
- `server/app/services/mcp/workflow_state_machine.rb` - State broadcasts
- `server/app/services/concerns/base_workflow_service.rb` - Base broadcast methods

### Frontend
- `frontend/src/shared/services/WebSocketManager.ts` - Singleton manager
- `frontend/src/shared/hooks/useWebSocket.ts` - Main hook
- `frontend/src/shared/hooks/useWorkflowExecution.ts` - Workflow hook
- `frontend/src/pages/app/ai/WorkflowDetailPage.tsx` - Detail page subscriptions
- `frontend/src/features/ai-workflows/components/WorkflowExecutionForm.tsx` - Execution form
- `frontend/src/features/ai-workflows/components/WorkflowExecutionDetails.tsx` - Details display

---

**Document Status**: Complete (17 channels documented)
**Consolidates**: WEBSOCKET_ARCHITECTURE.md, WORKFLOW_WEBSOCKET_COMPREHENSIVE_FIX_2025_10_11.md, WORKFLOW_WEBSOCKET_TESTING_GUIDE.md

