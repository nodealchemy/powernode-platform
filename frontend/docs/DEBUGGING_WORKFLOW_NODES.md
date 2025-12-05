# Workflow Node Execution Debugging Guide

## Issue
Workflow nodes display as "Unknown" with "pending" status even after successful execution completion.

## Debug Logs Added

Comprehensive console logging has been added to trace the data flow:

### 1. API Response (workflowApi.ts)
```
[WorkflowAPI] Node executions response: { url, hasData, nodeExecutionsCount, sampleExecution }
[WorkflowAPI] getWorkflowRunDetails result: { hasWorkflowRun, nodeExecutionsCount }
```

### 2. Component Data Loading (WorkflowExecutionDetails.tsx)
```
[WorkflowExecution] API Response - node_executions: { count, sample, allStatuses }
[WorkflowExecution] Failed to load executions: { status, error }
```

### 3. Node Merging Logic (WorkflowExecutionDetails.tsx)
```
[WorkflowExecution] No workflow nodes, returning raw executions: <count>
[WorkflowExecution] Merging nodes: { workflowNodesCount, nodeExecutionsCount, executionMapSize, ... }
[WorkflowExecution] Found execution for <node_id>: { name, status }
[WorkflowExecution] No execution found for <node_id>, creating placeholder
[WorkflowExecution] Merged nodes result: { totalCount, completedCount, pendingCount, placeholderCount }
```

### 4. WebSocket Updates (WorkflowExecutionDetails.tsx)
```
[WorkflowExecution] WebSocket node update received: { execution_id, status, node_name, node_id }
[WorkflowExecution] Current nodeExecutions count: <count>
```

## How to Debug

1. **Open Browser Console** (F12 → Console tab)

2. **Navigate to Workflow Execution Page**
   - Go to the workflow run that shows "Unknown" nodes
   - Expand the execution details

3. **Check Console Output** - Look for the debug logs in order:

### Expected Flow:
```
1. [WorkflowAPI] Node executions response: { nodeExecutionsCount: 11, ... }
   ✓ Should show 11 executions with complete data

2. [WorkflowExecution] API Response - node_executions: { count: 11, sample: {...}, ... }
   ✓ Sample should have: { execution_id, status: 'completed', node: { name: '...', node_id: '...' } }

3. [WorkflowExecution] Merging nodes: { workflowNodesCount: 11, nodeExecutionsCount: 11, executionMapSize: 11 }
   ✓ executionMapSize should equal nodeExecutionsCount
   ✓ executionMapKeys should match workflowNodeIds

4. [WorkflowExecution] Found execution for trigger_1: { name: 'Blog Topic Input', status: 'completed' }
   ✓ Should see this for each node (11 times total)

5. [WorkflowExecution] Merged nodes result: { totalCount: 11, completedCount: 11, pendingCount: 0, placeholderCount: 0 }
   ✓ completedCount should be 11, pendingCount should be 0
```

### Common Issues to Check:

**Issue 1: API Returns Empty Executions**
```
[WorkflowAPI] Node executions response: { nodeExecutionsCount: 0 }
```
→ Backend not returning execution data (authentication or serialization issue)

**Issue 2: Node ID Mismatch**
```
[WorkflowExecution] Merging nodes: { executionMapKeys: ['trigger_1', 'research_1'], workflowNodeIds: ['node_1', 'node_2'] }
```
→ Execution node_ids don't match workflow node_ids

**Issue 3: All Placeholders**
```
[WorkflowExecution] Merged nodes result: { placeholderCount: 11, completedCount: 0 }
```
→ No executions found in map (likely node ID mismatch)

**Issue 4: WebSocket Overwriting Data**
```
[WorkflowExecution] WebSocket node update received: { node_name: undefined, status: 'pending' }
```
→ WebSocket sending incomplete data that overwrites correct API data

## Quick Test

Run a new workflow execution and watch console logs in real-time:

1. Open Console (F12)
2. Execute the Blog Generation Pipeline workflow
3. Watch for debug logs as nodes execute
4. Compare expected vs actual log output

## Clean Up Logs

Once debugging is complete, remove console.log statements by searching for:
```
grep -r "console.log.*WorkflowExecution" frontend/src/
grep -r "console.log.*WorkflowAPI" frontend/src/
```

## Next Steps

Based on console output, the issue will be one of:
1. **API not returning data** → Check backend authentication/serialization
2. **Node ID mismatch** → Verify node_id mapping between workflow definition and executions
3. **WebSocket override** → Fix WebSocket message structure
4. **State timing** → Fix component state update order
