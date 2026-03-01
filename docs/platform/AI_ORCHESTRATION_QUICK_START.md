# AI Orchestration Quick Start

**Quick reference guide and implementation roadmap**

---

## Table of Contents

1. [Quick Start Guide](#quick-start-guide)
2. [Component Import Paths](#component-import-paths)
3. [Custom Hooks](#custom-hooks)
4. [WebSocket Events](#websocket-events)
5. [Common Patterns](#common-patterns)
6. [Backend Implementation Roadmap](#backend-implementation-roadmap)
7. [Troubleshooting](#troubleshooting)

---

## Quick Start Guide

### 1. Install Dependencies

```bash
cd frontend
npm install recharts lucide-react date-fns
```

### 2. Import Services

```typescript
// Consolidated import
import { agentsApi, workflowsApi, providersApi, monitoringApi } from '@/shared/services/ai';

// Or use the convenience object
import { aiApi } from '@/shared/services/ai';
```

### 3. Basic Workflow Execution

```typescript
// Execute workflow
const run = await workflowsApi.executeWorkflow('workflow-id', {
  input_variables: { key: 'value' },
  trigger_type: 'manual'
});

// Monitor progress via WebSocket
useWebSocket({
  channel: 'AiOrchestrationChannel',
  params: { type: 'workflow_run', id: run.id },
  onMessage: (msg) => updateProgress(msg.payload)
});
```

### 4. Check Permissions

```typescript
// Always use permission-based access control
const canExecute = currentUser?.permissions?.includes('ai.workflows.execute');

// Never use role-based checks
// ❌ const canExecute = currentUser?.roles?.includes('admin');
```

---

## Component Import Paths

### Batch Execution

```typescript
import { BatchExecutionModal } from '@/features/ai-workflows/components/batch/BatchExecutionModal';
import { BatchProgressPanel } from '@/features/ai-workflows/components/batch/BatchProgressPanel';
import { BatchResultsTable } from '@/features/ai-workflows/components/batch/BatchResultsTable';
import { useBatchExecution } from '@/features/ai-workflows/hooks/useBatchExecution';
```

### Streaming Execution

```typescript
import { StreamingExecutionPanel } from '@/features/ai-workflows/components/streaming/StreamingExecutionPanel';
import { StreamingExecutionModal } from '@/features/ai-workflows/components/streaming/StreamingExecutionModal';
import { useStreamingExecution } from '@/features/ai-workflows/hooks/useStreamingExecution';
```

### Circuit Breaker

```typescript
import { CircuitBreakerDashboard } from '@/features/ai-workflows/components/circuit-breaker/CircuitBreakerDashboard';
import { CircuitBreakerCard } from '@/features/ai-workflows/components/circuit-breaker/CircuitBreakerCard';
import { useCircuitBreaker } from '@/features/ai-workflows/hooks/useCircuitBreaker';
```

### Validation

```typescript
import { NodeValidationPanel } from '@/features/ai-workflows/components/validation/NodeValidationPanel';
import { WorkflowHealthScore } from '@/features/ai-workflows/components/validation/WorkflowHealthScore';
import { useWorkflowValidation } from '@/features/ai-workflows/hooks/useWorkflowValidation';
```

### MCP Browser

```typescript
import { McpServerCard } from '@/features/ai/components/McpServerCard';
import { McpToolExplorer } from '@/features/ai/components/McpToolExplorer';
```

### Cost Optimization

```typescript
import { CostOptimizationDashboard } from '@/features/ai-workflows/components/cost/CostOptimizationDashboard';
import { CostBreakdownChart } from '@/features/ai-workflows/components/cost/CostBreakdownChart';
import { ProviderCostComparison } from '@/features/ai-workflows/components/cost/ProviderCostComparison';
```

---

## Custom Hooks

### useBatchExecution

```typescript
const {
  batchStatus,
  isExecuting,
  error,
  startBatch,
  pauseBatch,
  resumeBatch,
  cancelBatch
} = useBatchExecution({
  onBatchComplete: (status) => console.log('Done!', status),
  onError: (error) => console.error(error)
});

// Start batch
await startBatch({
  workflow_ids: ['wf-1', 'wf-2'],
  concurrency: 2,
  execution_mode: 'parallel'
});
```

### useStreamingExecution

```typescript
const {
  executionState,
  isStreaming,
  startStreaming,
  pauseStreaming,
  resumeStreaming,
  stopStreaming,
  retryExecution
} = useStreamingExecution({
  maxMessages: 1000,
  onMessageReceived: (msg) => console.log(msg),
  onComplete: () => console.log('Complete')
});

await startStreaming('workflow-id', { input: 'value' });
```

### useCircuitBreaker

```typescript
const {
  breakers,
  isConnected,
  getBreakerById,
  getBreakersByService
} = useCircuitBreaker({
  autoConnect: true,
  onBreakerOpen: (breaker) => console.warn(`${breaker.name} opened!`)
});

const aiBreakers = getBreakersByService('ai_provider');
```

### useWorkflowValidation

```typescript
const {
  validationResult,
  isValidating,
  error,
  validate,
  clearResult
} = useWorkflowValidation({
  workflowId: 'workflow-id',
  autoValidate: true,
  validateOnChange: true,
  debounceMs: 1000
});
```

---

## WebSocket Events

### Subscribe to Events

```typescript
useWebSocket({
  channel: 'AiOrchestrationChannel',
  params: { type: 'account', id: accountId },
  onMessage: handleMessage
});
```

### Event Types

**Batch Execution**:
- `batch.execution.started`
- `batch.execution.progress`
- `batch.execution.completed`
- `batch.execution.failed`
- `batch.workflow.completed`

**Streaming**:
- `streaming.execution.started`
- `streaming.message.received`
- `streaming.node.changed`
- `streaming.execution.completed`

**Circuit Breaker**:
- `circuit_breaker.state_changed`
- `circuit_breaker.opened`
- `circuit_breaker.closed`
- `circuit_breaker.failure`

**Validation**:
- `validation.completed`
- `validation.issue_found`

---

## Common Patterns

### Permission Check Pattern

```typescript
const { currentUser } = useAuth();
const canManage = currentUser?.permissions?.includes('ai_orchestration.manage');

if (!canManage) {
  return <AccessDenied />;
}

return <ManagementPanel />;
```

### API Loading Pattern

```typescript
const [data, setData] = useState(null);
const [loading, setLoading] = useState(true);
const { addNotification } = useNotifications();

const loadData = useCallback(async () => {
  try {
    setLoading(true);
    const response = await apiService.getData();
    setData(response.data);
  } catch (error) {
    addNotification({ type: 'error', message: 'Load failed' });
  } finally {
    setLoading(false);
  }
}, [addNotification]);

useEffect(() => { loadData(); }, [loadData]);
```

### WebSocket Update Pattern

```typescript
const [items, setItems] = useState([]);

const handleMessage = useCallback((message) => {
  switch (message.event) {
    case 'item.created':
      setItems(prev => [...prev, message.payload.item]);
      break;
    case 'item.updated':
      setItems(prev => prev.map(item =>
        item.id === message.payload.item.id ? message.payload.item : item
      ));
      break;
    case 'item.deleted':
      setItems(prev => prev.filter(item => item.id !== message.payload.item_id));
      break;
  }
}, []);
```

---

## Backend Implementation Roadmap

### Sprint 1: Foundation (Week 1)

**Monday - Database Setup**:
```bash
cd server
rails generate migration CreateAiOrchestrationTables
rails db:migrate
```

**Required Tables**:
- `ai_workflows` - Workflow definitions
- `ai_workflow_nodes` - Workflow nodes
- `ai_workflow_edges` - Node connections
- `ai_workflow_runs` - Execution records
- `ai_workflow_node_executions` - Node execution records
- `batch_workflow_runs` - Batch execution records
- `circuit_breakers` - Circuit breaker state

**Tuesday - Core Models**:
```ruby
# Implement: AiWorkflow, AiWorkflowRun, AiWorkflowNode
# Include: Associations, Validations, Scopes, Callbacks
```

**Wednesday - Supporting Models**:
```ruby
# Implement: BatchWorkflowRun, CircuitBreaker, ValidationRule
```

**Thursday - Basic Controllers**:
```ruby
# Create: Api::V1::AiWorkflowsController (CRUD)
# Create: Api::V1::CircuitBreakersController (CRUD)
```

**Friday - Testing & Review**:
```bash
bundle exec rspec spec/models/
bundle exec rspec spec/requests/
```

### Sprint 2: Execution Engine (Week 2)

**Monday - Execution Services**:
```ruby
# Implement: WorkflowExecutionService, BatchExecutionService
```

**Tuesday - Background Jobs**:
```ruby
# Create: AiWorkflowExecutionJob, WorkflowBatchExecutionJob
# Pattern: Inherit from BaseJob, use execute method
```

**Wednesday - Execution Endpoints**:
```ruby
# Implement: POST /execute, POST /batch/execute
```

**Thursday - Batch Control**:
```ruby
# Implement: pause, resume, cancel endpoints
```

**Friday - Integration Testing**

### Sprint 3: Real-time & Monitoring (Week 3)

**Monday - WebSocket Channel**:
```ruby
# Implement: AiOrchestrationChannel
# Include: Subscription authorization, broadcasting
```

**Tuesday - Circuit Breakers**:
```ruby
# Implement: State management, event tracking
```

**Wednesday - Validation System**:
```ruby
# Implement: WorkflowValidationService, auto-fix
```

**Thursday - MCP Integration**:
```ruby
# Implement: MCP server management, tool execution
```

**Friday - Real-time Testing**

### Sprint 4: Polish & Production (Week 4)

**Monday - Performance Optimization**:
- Optimize N+1 queries
- Add database indexes
- Implement caching

**Tuesday - Testing**:
- Achieve 80%+ coverage
- Integration tests
- Load tests

**Wednesday - Monitoring**:
- Add StatsD metrics
- Configure alerts
- Create dashboards

**Thursday - Security & Documentation**

**Friday - Production Deployment**

---

## Troubleshooting

### WebSocket Not Connecting

**Symptoms**: Components not receiving real-time updates

**Solutions**:
1. Check WebSocket URL in environment variables
2. Verify user has required permissions
3. Check subscription params are correct

```typescript
// Debug WebSocket
const { isConnected, error } = useWebSocket({
  channel: 'AiOrchestrationChannel',
  params: { type: 'account', id: accountId },
  onMessage: (msg) => console.log('Received:', msg)
});
console.log('Connected:', isConnected, 'Error:', error);
```

### API Calls Failing

**Symptoms**: API service methods returning errors

**Solutions**:
1. Check authentication token is valid
2. Verify API endpoint is implemented
3. Check request/response format
4. Look for CORS issues

```typescript
try {
  const response = await apiService.getData();
} catch (error) {
  console.error('API Error:', error);
  console.error('Response:', error.response);
}
```

### Permission Denied Errors

**Symptoms**: User can't access features

**Solutions**:
1. Verify user has required permissions in database
2. Check permission strings match exactly
3. Ensure permissions array is populated

```typescript
console.log('Permissions:', currentUser?.permissions);
console.log('Has permission:',
  currentUser?.permissions?.includes('ai_orchestration.read'));
```

### Batch Execution Fails

**Symptoms**: Batch executions hang or fail

**Solutions**:
1. Check Sidekiq is running: `systemctl status powernode-worker@default`
2. Verify worker can communicate with backend API
3. Check concurrency settings
4. Review worker logs

```bash
# Check Sidekiq
systemctl status powernode-worker@default

# Monitor queue
redis-cli LLEN queue:ai_workflows
```

### Circuit Breakers Always Open

**Symptoms**: Circuit breakers immediately open

**Solutions**:
1. Check failure threshold configuration
2. Verify success threshold for recovery
3. Check underlying service is healthy

```ruby
# Reset circuit breaker
breaker = CircuitBreaker.find(id)
breaker.reset!
```

---

## Performance Tips

### Memoize Expensive Calculations

```typescript
const filteredItems = useMemo(() => {
  return items.filter(item => item.status === 'active');
}, [items]);
```

### Debounce Validation

```typescript
const debouncedValidate = useMemo(
  () => debounce(validate, 1000),
  [validate]
);
```

### Lazy Load Components

```typescript
const BatchExecutionModal = lazy(() =>
  import('@/features/ai-workflows/components/batch/BatchExecutionModal')
);

<Suspense fallback={<Loading />}>
  <BatchExecutionModal {...props} />
</Suspense>
```

### Limit WebSocket Updates

```typescript
const handleMessage = useCallback((message) => {
  const newData = message.payload.data;
  setData(prev => {
    if (JSON.stringify(prev) === JSON.stringify(newData)) {
      return prev; // No update needed
    }
    return newData;
  });
}, []);
```

---

## Quick Reference Tables

### Permission Requirements

| Feature | Read | Manage |
|---------|------|--------|
| Workflow Validation | `ai_orchestration.read` | `ai_orchestration.manage` |
| Batch Execution | `ai_orchestration.read` | `ai_orchestration.manage` |
| Streaming Execution | `ai_orchestration.read` | `ai_orchestration.manage` |
| Circuit Breaker | `ai_orchestration.read` | `system.admin` |
| MCP Browser | `ai_orchestration.read` | `ai_orchestration.manage` |
| Cost Dashboard | `analytics.read` | N/A |

### Development Commands

```bash
# Start services
sudo systemctl start powernode.target

# Run backend tests
cd server && bundle exec rspec

# Run frontend tests
cd frontend && npm test

# Type check
cd frontend && npm run typecheck

# Database migrations
cd server && rails db:migrate

# Check routes
cd server && rails routes | grep ai
```

### Key Files

| Purpose | Path |
|---------|------|
| Orchestration Service | `server/app/services/ai_agent_orchestration_service.rb` |
| MCP Orchestrator | `server/app/services/mcp/workflow_orchestrator.rb` |
| Workflows Controller | `server/app/controllers/api/v1/ai/workflows_controller.rb` |
| Frontend AI Services | `frontend/src/shared/services/ai/index.ts` |
| Workflow Types | `frontend/src/shared/types/workflow.ts` |
| Workflow Builder | `frontend/src/shared/components/workflow/WorkflowBuilder.tsx` |

---

**Document Status**: ✅ Complete
**Consolidates**: AI_ORCHESTRATION_QUICK_REFERENCE.md, AI_ORCHESTRATION_TEAM_HANDOFF.md, AI_ORCHESTRATION_REDESIGN.md, AI_ORCHESTRATION_BACKEND_ROADMAP.md
