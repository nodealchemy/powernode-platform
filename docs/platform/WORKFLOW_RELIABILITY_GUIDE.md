# Workflow Reliability Guide

**State management, error recovery, and reliability improvements**

---

## Table of Contents

1. [State Management](#state-management)
2. [Frontend Reliability](#frontend-reliability)
3. [Backend Error Handling](#backend-error-handling)
4. [Stuck Run Detection](#stuck-run-detection)
5. [Validation & Testing](#validation--testing)
6. [Troubleshooting](#troubleshooting)

---

## State Management

### Problem Statement

Frontend can show "phantom" workflow runs that appear active but don't exist or have already completed. This occurs when:
- WebSocket completion broadcasts not received
- Browser page remains open with stale state
- Network interruptions prevent status updates
- Backend execution fails silently

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Frontend State                           │
│  workflowRuns: AiWorkflowRun[]                             │
│  - Optimistically updated on execution                      │
│  - Updated via WebSocket broadcasts                         │
│  - Periodically reconciled with backend (30s)               │
└─────────────────────────────────────────────────────────────┘
                          ↕
┌─────────────────────────────────────────────────────────────┐
│                    WebSocket Layer                          │
│  - Real-time status updates                                 │
│  - Error handling with exponential backoff                  │
│  - Automatic fallback to polling                            │
└─────────────────────────────────────────────────────────────┘
                          ↕
┌─────────────────────────────────────────────────────────────┐
│                    Backend Database                         │
│  ai_workflow_runs                                           │
│  - Ground truth for workflow status                         │
│  - Automatically broadcasts status changes                  │
│  - Stale run detection (>30min)                             │
└─────────────────────────────────────────────────────────────┘
```

### Synchronization Mechanisms

| Mechanism | Trigger | Frequency | Purpose |
|-----------|---------|-----------|---------|
| **WebSocket Broadcast** | Status change | Real-time | Primary update mechanism |
| **Auto-reconciliation** | Timer | Every 30s | Catch missed broadcasts |
| **Stale Detection** | useEffect | On render | Remove stuck runs |
| **Error Recovery** | WebSocket failure | 2s, 4s, 6s, 10s | Graceful degradation |
| **Manual Refresh** | User action | On demand | User-initiated sync |

---

## Frontend Reliability

### 1. UUID Query Helper (Backend)

**Location**: `server/app/models/ai_workflow_run.rb`

```ruby
# Find workflow runs stuck for >30 minutes
scope :stale, -> {
  where(status: %w[initializing running])
    .where('created_at < ?', 30.minutes.ago)
}

# Search by partial UUID (handles PostgreSQL UUID type casting)
scope :find_by_partial_id, ->(partial_id) {
  where("id::text LIKE ?", "%#{sanitize_sql_like(partial_id)}%")
}
```

**Usage**:
```ruby
AiWorkflowRun.stale                        # Find all stale runs
AiWorkflowRun.find_by_partial_id("bd3ca9f5")  # Search by partial ID
```

### 2. Automatic State Reconciliation

**Location**: `WorkflowExecutionForm.tsx`

```typescript
// Auto-sync with backend every 30 seconds when active runs exist
useEffect(() => {
  if (!isOpen || !workflow.id) return;

  const reconciliationInterval = setInterval(() => {
    const hasActiveRuns = workflowRuns.some(run =>
      run.status === 'running' || run.status === 'initializing'
    );

    if (activeTab === 'history' && hasActiveRuns) {
      console.log('[WorkflowExecutionForm] Auto-reconciling state with backend');
      loadWorkflowRuns();
    }
  }, 30000);

  return () => clearInterval(reconciliationInterval);
}, [isOpen, workflow.id, activeTab, workflowRuns, loadWorkflowRuns]);
```

**Behavior**:
- Only reconciles when modal is open and history tab is active
- Checks for active runs (`running` or `initializing` status)
- Fetches latest data from backend
- Minimal performance impact

### 3. Stale Data Detection & Cleanup

**Location**: `WorkflowExecutionForm.tsx`

```typescript
// Remove workflow runs stuck in "running" for >30 minutes
useEffect(() => {
  if (!isOpen || workflowRuns.length === 0) return;

  const STALE_THRESHOLD = 30 * 60 * 1000; // 30 minutes
  const now = Date.now();

  const staleRuns = workflowRuns.filter(run => {
    if (run.status !== 'running' && run.status !== 'initializing') return false;
    const createdAt = new Date(run.created_at || run.started_at).getTime();
    return (now - createdAt) > STALE_THRESHOLD;
  });

  if (staleRuns.length > 0) {
    // Mark as failed locally
    setWorkflowRuns(prevRuns =>
      prevRuns.map(run => {
        if (staleRuns.find(stale => stale.id === run.id)) {
          return {
            ...run,
            status: 'failed',
            error_details: {
              error_message: 'Workflow execution timed out or connection lost.',
              stale_detection: true
            }
          };
        }
        return run;
      })
    );

    showNotification(`Detected ${staleRuns.length} stale workflow run(s). Refreshing...`, 'warning');
    setTimeout(() => loadWorkflowRuns(), 1000);
  }
}, [isOpen, workflowRuns, showNotification, loadWorkflowRuns]);
```

### 4. Enhanced WebSocket Error Handling

**Location**: `WorkflowExecutionForm.tsx`

```typescript
useEffect(() => {
  if (!isOpen || !workflow.id || !isConnected) return;

  let reconnectAttempts = 0;
  const MAX_RECONNECT_ATTEMPTS = 3;
  let reconnectTimeout: NodeJS.Timeout | null = null;

  const unsubscribeMcp = subscribe({
    channel: 'McpChannel',
    params: {},
    onMessage: (data) => {
      reconnectAttempts = 0; // Reset on success
      if (data?.params?.workflow_id === workflow.id) {
        handleWorkflowRunUpdate(data.params || data);
      }
    },
    onError: (error) => {
      console.error('[WorkflowExecutionForm] WebSocket error:', error);

      if (reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
        reconnectAttempts++;
        // Exponential backoff: 2s, 4s, 6s
        reconnectTimeout = setTimeout(() => {
          loadWorkflowRuns();
        }, 2000 * reconnectAttempts);
      } else {
        showNotification(
          'Live updates temporarily unavailable. Data will refresh automatically.',
          'warning'
        );
        // Fall back to polling every 10 seconds
        reconnectTimeout = setTimeout(() => {
          loadWorkflowRuns();
          reconnectAttempts = 0;
        }, 10000);
      }
    }
  });

  return () => {
    unsubscribeMcp();
    if (reconnectTimeout) clearTimeout(reconnectTimeout);
  };
}, [isOpen, workflow.id, isConnected, subscribe, handleWorkflowRunUpdate]);
```

**Recovery Strategy**:
1. Attempt 1: Retry after 2 seconds
2. Attempt 2: Retry after 4 seconds
3. Attempt 3: Retry after 6 seconds
4. Fallback: Poll every 10 seconds, notify user

---

## Backend Error Handling

### Provider Error Detection

**Location**: `server/app/services/mcp_agent_executor.rb`

```ruby
unless result[:success]
  error_message = result.dig(:error, 'message') || 'Unknown provider error'
  error_type = result.dig(:error, 'type') || 'unknown_error'
  status_code = result[:status_code] || 500

  case error_type.to_s
  when 'not_found_error', 'invalid_request_error'
    raise ValidationError, "Provider rejected request: #{error_message}"
  when 'authentication_error', 'permission_denied_error'
    raise ProviderError, "Provider authentication failed: #{error_message}"
  # ... other error types
  end
end
```

### MCP Error Response Detection

**Location**: `server/app/services/mcp/node_executors/ai_agent.rb`

```ruby
if execution_result['error'] || execution_result[:error]
  error_info = execution_result['error'] || execution_result[:error]
  error_message = error_info['message'] || 'Unknown MCP error'

  raise Mcp::WorkflowOrchestrator::NodeExecutionError,
        "AI Agent execution failed: #{error_message}"
end
```

### Multi-Layer Error Handling

1. **Provider Layer**: Checks `result[:success]` and raises typed exceptions
2. **MCP Executor Layer**: Checks for `'error'` key in MCP responses
3. **Orchestrator Layer**: Catches execution errors and coordinates failure handling

---

## Stuck Run Detection

### Problem

Workflow runs can get stuck in `initializing` status when:
- Job was never enqueued to Sidekiq
- Transient Redis connection issue
- Worker service restart during enqueue
- Backend server issue

### Detection

```ruby
# Find runs stuck in initializing for more than 5 minutes
stuck_runs = AiWorkflowRun.where(status: 'initializing')
                          .where('created_at < ?', 5.minutes.ago)
                          .where(started_at: nil)
```

### Resolution

**Manual Re-queue**:
```ruby
WorkerJobService.enqueue_ai_workflow_execution(
  run.run_id,
  { 'realtime' => true, 'channel_id' => "ai_workflow_execution_#{run.run_id}" }
)
```

### Recommended Cleanup Job

**File**: `worker/app/jobs/workflow_stuck_run_cleanup_job.rb`

```ruby
class WorkflowStuckRunCleanupJob < BaseJob
  def execute
    stuck_runs = AiWorkflowRun.where(status: 'initializing')
                              .where('created_at < ?', 5.minutes.ago)
                              .where(started_at: nil)

    stuck_runs.find_each do |run|
      Rails.logger.warn "Detected stuck workflow run: #{run.run_id}"

      begin
        WorkerJobService.enqueue_ai_workflow_execution(
          run.run_id,
          { 'realtime' => true, 'channel_id' => "ai_workflow_execution_#{run.run_id}" }
        )
        Rails.logger.info "Re-queued stuck workflow run: #{run.run_id}"
      rescue => e
        run.update!(
          status: 'failed',
          error_details: {
            error_type: 'stuck_in_initializing',
            error_message: "Run stuck in initializing status: #{e.message}",
            failed_at: Time.current.iso8601
          }
        )
      end
    end
  end
end
```

### Enhanced Enqueue Error Handling

```ruby
begin
  job_id = WorkerJobService.enqueue_ai_workflow_execution(
    run.run_id,
    { 'realtime' => true, 'channel_id' => "ai_workflow_execution_#{run.run_id}" }
  )
  run.update!(metadata: run.metadata.merge('sidekiq_job_id' => job_id))
rescue WorkerJobService::WorkerServiceError => e
  run.update!(
    status: 'failed',
    error_details: {
      error_type: 'job_enqueue_failed',
      error_message: "Failed to enqueue workflow execution job: #{e.message}",
      failed_at: Time.current.iso8601
    }
  )
  raise
end
```

---

## Validation & Testing

### Backend Validation

```bash
# Access Rails console
cd $POWERNODE_ROOT/server && bundle exec rails console

# Test partial ID search
run_id = AiWorkflowRun.last.id.to_s
partial_id = run_id[0..7]
found = AiWorkflowRun.find_by_partial_id(partial_id)
puts "✅ Partial ID search works" if found.any?

# Test stale scope
stale_runs = AiWorkflowRun.stale
puts "Found #{stale_runs.count} stale runs"
```

### Frontend Validation

**Auto-Reconciliation Test**:
1. Open DevTools Console
2. Navigate to AI Workflows page
3. Execute workflow
4. Switch to "Execution History" tab
5. Wait 30 seconds, watch for: `[WorkflowExecutionForm] Auto-reconciling state with backend`

**Stale Detection Test**:
1. Execute a workflow
2. Stop worker service
3. Leave browser open for 31 minutes
4. Watch for stale detection notification

**WebSocket Recovery Test**:
1. Open workflow execution modal
2. Execute a workflow
3. Set network to "Offline" for 10 seconds
4. Switch back to "Online"
5. Monitor console for reconnection attempts

### Integration Test Scenarios

**Scenario 1: Normal Operation**
- Execute workflow, let complete normally
- Status updates via WebSocket

**Scenario 2: WebSocket Connection Loss**
- Disconnect network during execution
- Verify auto-recovery and polling fallback

**Scenario 3: Stale Run Detection**
- Keep browser open with "running" workflow for 31 minutes
- Verify stale detection marks as failed

**Scenario 4: Browser Refresh**
- Execute workflow, refresh browser before completion
- Verify state loads from server correctly

---

## Troubleshooting

### Issue: Reconciliation not triggering

**Symptoms**: No console logs showing reconciliation

**Checks**:
1. Is modal open? → Must be `isOpen === true`
2. Is history tab active? → Must be `activeTab === 'history'`
3. Are there active runs? → At least one run with status `running` or `initializing`

### Issue: Stale detection too aggressive/passive

**Symptoms**: Runs marked as stale too soon or too late

**Fix**: Adjust `STALE_THRESHOLD`:
```typescript
const STALE_THRESHOLD = 45 * 60 * 1000; // 45 minutes instead of 30
```

### Issue: WebSocket reconnection failing

**Symptoms**: Max reconnect attempts reached, connection never restores

**Checks**:
1. Backend WebSocket server running?
2. ActionCable connection established?
3. Network firewall blocking WebSocket?

**Fix**:
1. Verify backend: `systemctl status powernode-backend@default`
2. Check polling fallback is working

### Issue: PostgreSQL UUID type error

**Symptoms**: Error: `operator does not exist: uuid ~~ unknown`

**Fix**: Ensure scope uses `id::text LIKE` pattern:
```ruby
scope :find_by_partial_id, ->(partial_id) {
  where("id::text LIKE ?", "%#{sanitize_sql_like(partial_id)}%")
}
```

### Issue: Workflow stuck in initializing

**Symptoms**: Workflow run stays in "initializing" with no progress

**Check**:
1. Job was never enqueued
2. Worker service not running
3. Redis connection issue

**Fix**: Re-queue manually:
```ruby
WorkerJobService.enqueue_ai_workflow_execution(
  run.run_id,
  { 'realtime' => true, 'channel_id' => "ai_workflow_execution_#{run.run_id}" }
)
```

---

## Configuration Constants

### Frontend

```typescript
const RECONCILIATION_INTERVAL = 30000;      // 30 seconds
const STALE_THRESHOLD = 30 * 60 * 1000;    // 30 minutes
const MAX_RECONNECT_ATTEMPTS = 3;          // 3 attempts
const FALLBACK_POLL_INTERVAL = 10000;      // 10 seconds
```

### Backend

```ruby
scope :stale, -> { where('created_at < ?', 30.minutes.ago) }
```

---

## Monitoring Recommendations

### Metrics to Track

- `workflow_runs_stuck_initializing` (count)
- `workflow_job_enqueue_failures` (count)
- `workflow_execution_start_latency` (time from created_at to started_at)

### Alerts

```
Alert: Workflow runs stuck > 5 minutes
Condition: workflow_runs_stuck_initializing > 0
Action: Send notification to ops team

Alert: High enqueue failure rate
Condition: workflow_job_enqueue_failures > 5 in 10 minutes
Action: Page on-call engineer
```

---

## Success Criteria

### Minimum Requirements

- ✅ Backend scopes available and functional
- ✅ Auto-reconciliation triggers every 30 seconds when conditions met
- ✅ Stale detection marks runs as failed after 30 minutes
- ✅ WebSocket errors handled with exponential backoff
- ✅ No memory leaks from intervals/subscriptions

### Optimal Requirements

- Performance impact <5% additional API calls during normal operation
- Network failure recovery within 15 seconds
- No phantom workflow runs after 24-hour stress test
- Graceful degradation under adverse network conditions

---

**Document Status**: ✅ Complete
**Consolidates**: WORKFLOW_STATE_RELIABILITY_IMPROVEMENTS.md, WORKFLOW_RELIABILITY_VALIDATION_PLAN.md, WORKFLOW_STUCK_INITIALIZING_FIX_2025_10_10.md
