# AI Orchestration API Reference

**Complete API endpoints, service patterns, and component examples**

---

## Table of Contents

1. [API Overview](#api-overview)
2. [Workflow Endpoints](#workflow-endpoints)
3. [Batch Execution Endpoints](#batch-execution-endpoints)
4. [Streaming Execution Endpoints](#streaming-execution-endpoints)
5. [Circuit Breaker Endpoints](#circuit-breaker-endpoints)
6. [MCP Endpoints](#mcp-endpoints)
7. [Validation Endpoints](#validation-endpoints)
8. [Cost Optimization Endpoints](#cost-optimization-endpoints)
9. [Frontend Service Patterns](#frontend-service-patterns)
10. [Component Examples](#component-examples)

---

## API Overview

**Base Path**: `/api/v1`
**Authentication**: JWT Bearer token required
**Authorization**: Permission-based (see permissions per endpoint)
**Total Endpoints**: 55+

### Response Format

All endpoints return structured JSON:

```json
{
  "success": true,
  "data": { ... },
  "message": "Optional message"
}
```

Error responses:
```json
{
  "success": false,
  "error": "Error message",
  "errors": ["Detailed error 1", "Detailed error 2"]
}
```

---

## Workflow Endpoints

### List Workflows
```http
GET /api/v1/ai/workflows
```

**Query Parameters**: `status`, `visibility`, `tags`, `page`, `per_page`, `sort_by`, `sort_order`

**Response**:
```json
{
  "workflows": [...],
  "pagination": { "total": 100, "page": 1, "per_page": 25 }
}
```
**Permission**: `ai.workflows.read`

### Get Workflow
```http
GET /api/v1/ai/workflows/:id
```
**Permission**: `ai.workflows.read`

### Create Workflow
```http
POST /api/v1/ai/workflows
```
**Permission**: `ai.workflows.create`

### Update Workflow
```http
PATCH /api/v1/ai/workflows/:id
```
**Permission**: `ai.workflows.update`

### Delete Workflow
```http
DELETE /api/v1/ai/workflows/:id
```
**Permission**: `ai.workflows.delete`

### Execute Workflow
```http
POST /api/v1/ai/workflows/:id/execute
```

**Request Body**:
```json
{
  "input_variables": { "key": "value" },
  "trigger_type": "manual"
}
```

**Response**:
```json
{
  "workflow_run": {
    "id": "uuid",
    "status": "running",
    "run_id": "uuid"
  }
}
```
**Permission**: `ai.workflows.execute`

### Get Workflow Runs
```http
GET /api/v1/ai/workflows/:id/runs
```
**Permission**: `ai.workflows.read`

### Cancel Run
```http
POST /api/v1/ai/workflows/:id/runs/:run_id/cancel
```
**Permission**: `ai.workflows.execute`

---

## Batch Execution Endpoints

### Start Batch Execution
```http
POST /api/v1/ai_workflows/batch/execute
```

**Request Body**:
```json
{
  "workflow_ids": ["uuid1", "uuid2", "uuid3"],
  "concurrency": 3,
  "execution_mode": "parallel",
  "stop_on_error": false,
  "input_variables": { "key": "value" },
  "priority": "normal"
}
```

**Response**:
```json
{
  "batch_id": "uuid",
  "status": "pending",
  "total_workflows": 3
}
```
**Permission**: `ai_orchestration.manage`

### Get Batch Status
```http
GET /api/v1/ai_workflows/batch/:batch_id
```

**Response**:
```json
{
  "batch_execution": {
    "id": "uuid",
    "status": "running",
    "progress": 45.5,
    "total_workflows": 10,
    "completed_workflows": 4,
    "failed_workflows": 1,
    "workflow_results": [...]
  }
}
```
**Permission**: `ai_orchestration.read`

### Pause Batch
```http
POST /api/v1/ai_workflows/batch/:batch_id/pause
```
**Permission**: `ai_orchestration.manage`

### Resume Batch
```http
POST /api/v1/ai_workflows/batch/:batch_id/resume
```
**Permission**: `ai_orchestration.manage`

### Cancel Batch
```http
POST /api/v1/ai_workflows/batch/:batch_id/cancel
```
**Permission**: `ai_orchestration.manage`

### Get Batch History
```http
GET /api/v1/ai_workflows/batch/history?limit=50&status=completed
```
**Permission**: `ai_orchestration.read`

---

## Streaming Execution Endpoints

### Start Streaming
```http
POST /api/v1/ai_workflows/:workflow_id/stream/start
```

**Request Body**:
```json
{
  "input_variables": { "key": "value" },
  "stream_config": {
    "buffer_size": 100,
    "flush_interval_ms": 500
  }
}
```

**Response**:
```json
{
  "run_id": "uuid",
  "status": "streaming",
  "websocket_channel": "AiOrchestrationChannel",
  "stream_id": "stream-uuid"
}
```
**Permission**: `ai_orchestration.manage`

### Pause Streaming
```http
POST /api/v1/ai_workflows/stream/:run_id/pause
```
**Permission**: `ai_orchestration.manage`

### Resume Streaming
```http
POST /api/v1/ai_workflows/stream/:run_id/resume
```
**Permission**: `ai_orchestration.manage`

### Stop Streaming
```http
POST /api/v1/ai_workflows/stream/:run_id/stop
```
**Permission**: `ai_orchestration.manage`

### Retry Streaming
```http
POST /api/v1/ai_workflows/stream/:run_id/retry
```
**Permission**: `ai_orchestration.manage`

---

## Circuit Breaker Endpoints

### Get All Circuit Breakers
```http
GET /api/v1/circuit_breakers?service=ai_provider&state=open
```

**Response**:
```json
{
  "metrics": {
    "total_breakers": 15,
    "open_breakers": 2,
    "half_open_breakers": 1,
    "closed_breakers": 12
  },
  "breakers": [
    {
      "id": "uuid",
      "name": "OpenAI GPT-4",
      "service": "ai_provider",
      "state": "closed",
      "failure_count": 0,
      "failure_threshold": 5,
      "metrics": {
        "success_rate": 96.67,
        "avg_response_time_ms": 850
      }
    }
  ]
}
```
**Permission**: `ai_orchestration.read`

### Get Circuit Breaker by ID
```http
GET /api/v1/circuit_breakers/:id
```
**Permission**: `ai_orchestration.read`

### Reset Circuit Breaker
```http
POST /api/v1/circuit_breakers/:id/reset
```
**Permission**: `system.admin`

### Get Circuit Breaker History
```http
GET /api/v1/circuit_breakers/:id/history?time_range=24h&event_type=failure
```
**Permission**: `ai_orchestration.read`

### Update Circuit Breaker Configuration
```http
PATCH /api/v1/circuit_breakers/:id
```
**Permission**: `system.admin`

---

## MCP Endpoints

### Get All MCP Servers
```http
GET /api/v1/mcp/servers?status=connected
```

**Response**:
```json
{
  "servers": [
    {
      "id": "uuid",
      "name": "Filesystem MCP",
      "status": "connected",
      "connection_type": "stdio",
      "capabilities": { "tools": true, "resources": true },
      "tools_count": 8
    }
  ],
  "tools": [...]
}
```
**Permission**: `ai_orchestration.read`

### Get MCP Server by ID
```http
GET /api/v1/mcp/servers/:id
```
**Permission**: `ai_orchestration.read`

### Test MCP Server Connection
```http
POST /api/v1/mcp/servers/:id/test
```
**Permission**: `ai_orchestration.manage`

### Execute MCP Tool
```http
POST /api/v1/mcp/tools/:tool_id/execute
```

**Request Body**:
```json
{
  "parameters": {
    "path": "/workspace/README.md",
    "encoding": "utf-8"
  }
}
```

**Response**:
```json
{
  "tool_id": "uuid",
  "tool_name": "read_file",
  "status": "success",
  "result": { "content": "...", "size_bytes": 1024 },
  "execution_time_ms": 25
}
```
**Permission**: `ai_orchestration.manage`

### Get MCP Resources
```http
GET /api/v1/mcp/resources?server_id=uuid
```
**Permission**: `ai_orchestration.read`

### Read MCP Resource
```http
POST /api/v1/mcp/resources/:resource_id/read
```
**Permission**: `ai_orchestration.read`

---

## Validation Endpoints

### Validate Workflow
```http
POST /api/v1/ai_workflows/:workflow_id/validate
```

**Response**:
```json
{
  "validation_result": {
    "workflow_id": "uuid",
    "overall_status": "warnings",
    "health_score": 85,
    "total_nodes": 10,
    "issues": [
      {
        "id": "uuid",
        "node_id": "uuid",
        "severity": "warning",
        "category": "performance",
        "message": "Request timeout of 60s exceeds recommended 30s",
        "auto_fixable": true
      }
    ]
  }
}
```
**Permission**: `ai_orchestration.read`

### Validate Specific Nodes
```http
POST /api/v1/ai_workflows/:workflow_id/validate_nodes
```
**Permission**: `ai_orchestration.read`

### Auto-Fix Validation Issues
```http
POST /api/v1/ai_workflows/:workflow_id/auto_fix
```

**Request Body**:
```json
{
  "issue_ids": ["uuid1", "uuid2"]
}
```
**Permission**: `ai_orchestration.manage`

### Get Validation Rules
```http
GET /api/v1/validation_rules?category=performance&enabled=true
```
**Permission**: `ai_orchestration.read`

### Update Validation Rule
```http
PATCH /api/v1/validation_rules/:rule_id
```
**Permission**: `system.admin`

### Get Validation History
```http
GET /api/v1/ai_workflows/:workflow_id/validation_history?limit=10
```
**Permission**: `ai_orchestration.read`

---

## Cost Optimization Endpoints

### Get Cost Analysis
```http
GET /api/v1/ai_workflows/cost/analysis?time_range=30d
```

**Response**:
```json
{
  "cost_analysis": {
    "total_cost": 1250.50,
    "by_provider": {
      "openai": 850.25,
      "anthropic": 300.15
    },
    "by_workflow": [...],
    "optimization_suggestions": [...]
  }
}
```
**Permission**: `analytics.read`

### Get Provider Cost Comparison
```http
GET /api/v1/ai_workflows/cost/compare_providers?workflow_id=uuid
```
**Permission**: `analytics.read`

### Get Efficiency Metrics
```http
GET /api/v1/ai_workflows/cost/efficiency?time_range=30d
```
**Permission**: `analytics.read`

---

## Frontend Service Patterns

### Import API Services

```typescript
import {
  agentsApi,
  workflowsApi,
  providersApi,
  monitoringApi,
  analyticsApi
} from '@/shared/services/ai';
```

### Batch Execution Service Usage

```typescript
// Start batch execution
const { batch_id } = await workflowsApi.executeBatch({
  workflow_ids: ['wf-1', 'wf-2', 'wf-3'],
  concurrency: 3,
  execution_mode: 'parallel',
  stop_on_error: false,
  input_variables: { key: 'value' }
});

// Get batch status
const { batch_execution } = await workflowsApi.getBatchStatus(batch_id);

// Control batch
await workflowsApi.pauseBatch(batch_id);
await workflowsApi.resumeBatch(batch_id);
await workflowsApi.cancelBatch(batch_id);
```

### Circuit Breaker Service Usage

```typescript
// Get all metrics
const { metrics } = await circuitBreakerApi.getMetrics();

// Get specific breaker
const { breaker } = await circuitBreakerApi.getBreaker('breaker-id');

// Reset breaker (admin only)
await circuitBreakerApi.resetBreaker('breaker-id');

// Get history
const { events } = await circuitBreakerApi.getBreakerHistory('breaker-id', {
  time_range: '24h',
  event_type: 'failure'
});
```

### MCP Service Usage

```typescript
// Get all servers
const { servers, tools } = await mcpApi.getServers();

// Execute tool
const result = await mcpApi.executeTool('tool-id', {
  param1: 'value1',
  param2: 'value2'
});

// Test server connection
const { success, latency_ms } = await mcpApi.testServerConnection('server-id');
```

### Validation Service Usage

```typescript
// Validate workflow
const { validation_result } = await validationApi.validateWorkflow('workflow-id');

// Auto-fix issues
const { fixed_issues } = await validationApi.autoFix('workflow-id', ['issue-1']);

// Get validation history
const { validations } = await validationApi.getValidationHistory('workflow-id', 10);
```

---

## Component Examples

### Batch Execution Modal

```typescript
import { BatchExecutionModal } from '@/features/ai-workflows/components/batch/BatchExecutionModal';
import { useBatchExecution } from '@/features/ai-workflows/hooks/useBatchExecution';

const MyComponent = () => {
  const [showModal, setShowModal] = useState(false);
  const { startBatch, batchStatus, isExecuting } = useBatchExecution({
    onBatchComplete: (status) => console.log('Done!', status)
  });

  const handleExecute = async (config) => {
    await startBatch(config);
    setShowModal(false);
  };

  return (
    <>
      <Button onClick={() => setShowModal(true)}>Batch Execute</Button>
      <BatchExecutionModal
        isOpen={showModal}
        onClose={() => setShowModal(false)}
        onExecute={handleExecute}
      />
    </>
  );
};
```

### Circuit Breaker Dashboard

```typescript
import { CircuitBreakerDashboard } from '@/features/ai-workflows/components/circuit-breaker/CircuitBreakerDashboard';
import { useCircuitBreaker } from '@/features/ai-workflows/hooks/useCircuitBreaker';

const MonitoringPage = () => {
  const { breakers, isConnected, getBreakersByService } = useCircuitBreaker({
    autoConnect: true,
    onBreakerOpen: (breaker) => {
      console.warn(`Circuit breaker ${breaker.name} opened!`);
    }
  });

  const aiBreakers = getBreakersByService('ai_provider');

  return <CircuitBreakerDashboard breakers={aiBreakers} />;
};
```

### Workflow Validation Panel

```typescript
import { NodeValidationPanel } from '@/features/ai-workflows/components/validation/NodeValidationPanel';
import { useWorkflowValidation } from '@/features/ai-workflows/hooks/useWorkflowValidation';

const WorkflowEditor = ({ workflowId }) => {
  const { validationResult, isValidating, validate } = useWorkflowValidation({
    workflowId,
    autoValidate: true,
    validateOnChange: true,
    debounceMs: 1000
  });

  return (
    <div>
      <WorkflowCanvas />
      <NodeValidationPanel
        result={validationResult}
        isValidating={isValidating}
        onValidate={validate}
      />
    </div>
  );
};
```

### WebSocket Integration

```typescript
import { useWebSocket } from '@/shared/hooks/useWebSocket';

const RealtimeComponent = () => {
  const { isConnected } = useWebSocket({
    channel: 'AiOrchestrationChannel',
    params: {
      type: 'account',
      id: currentUser.account_id
    },
    onMessage: (message) => {
      switch (message.event) {
        case 'batch.execution.progress':
          updateBatchProgress(message.payload);
          break;
        case 'circuit_breaker.state_changed':
          updateBreakerState(message.payload);
          break;
      }
    }
  });

  return <div>Connected: {isConnected ? 'Yes' : 'No'}</div>;
};
```

---

## Permission Requirements Summary

| Feature | Read Permission | Manage Permission |
|---------|----------------|-------------------|
| Workflow CRUD | `ai.workflows.read` | `ai.workflows.create/update/delete` |
| Workflow Execution | `ai.workflows.read` | `ai.workflows.execute` |
| Batch Execution | `ai_orchestration.read` | `ai_orchestration.manage` |
| Streaming Execution | `ai_orchestration.read` | `ai_orchestration.manage` |
| Circuit Breakers | `ai_orchestration.read` | `system.admin` |
| MCP Browser | `ai_orchestration.read` | `ai_orchestration.manage` |
| Validation | `ai_orchestration.read` | `ai_orchestration.manage` |
| Cost Dashboard | `analytics.read` | N/A |

---

**Document Status**: ✅ Complete
**Consolidates**: AI_ORCHESTRATION_API_ENDPOINTS.md, AI_ORCHESTRATION_COMPONENT_EXAMPLES.md, AI_ORCHESTRATION_SERVICES_QUICK_REFERENCE.md
