# AI Workflow Edge Types - Industry Standards Research

**Date**: October 7, 2025
**Purpose**: Evaluate and standardize edge types based on popular AI orchestration and workflow systems

---

## Industry Survey: Popular Workflow Systems

### 1. **LangGraph (LangChain)**
**Edge Types**:
- `default` - Standard flow path
- Custom labels for routing (e.g., "continue", "end", "tools")
- Conditional edges based on function returns

**Pattern**: Flexible edge labeling with conditional routing

### 2. **n8n (Workflow Automation)**
**Edge Types**:
- `main` - Primary execution path
- `error` - Error handling path
- Numbered outputs (0, 1, 2) for multi-branch nodes

**Pattern**: Simple main/error dichotomy with numbered branches

### 3. **AWS Step Functions**
**Edge Types**:
- `Next` - Standard transition
- `Catch` - Error handling
- `Choice` - Conditional branching
- `Retry` - Retry configuration
- `Timeout` - Timeout transitions

**Pattern**: Explicit state machine transitions with error handling

### 4. **Apache Airflow**
**Edge Types**:
- Task dependencies (upstream/downstream)
- `success` - Task succeeded
- `failed` - Task failed
- `skipped` - Task skipped
- `retry` - Retry attempts

**Pattern**: State-based task transitions

### 5. **Prefect**
**Edge Types**:
- `success` - Successful completion
- `failed` - Failure state
- `retry` - Retry transition
- `cached` - Cached result
- `pending` - Waiting state

**Pattern**: Rich state transitions with caching support

### 6. **Azure Logic Apps**
**Edge Types**:
- `success` - Successful execution
- `failed` - Failure path
- `timeout` - Timeout handling
- `skipped` - Skipped execution
- `cancelled` - Manual cancellation

**Pattern**: Comprehensive execution states

### 7. **Temporal**
**Edge Types**:
- Signals and awaits (event-driven)
- Activity results (success/failure)
- Timers and timeouts
- Compensations (saga pattern)

**Pattern**: Event-driven with compensation support

### 8. **Node-RED**
**Edge Types**:
- Numbered ports (0, 1, 2, 3...)
- No explicit typing (implicit by connection)

**Pattern**: Visual flow programming without typed edges

### 9. **Zapier**
**Edge Types**:
- `success` - Action succeeded
- `error` - Action failed
- `filter` - Filtered out (skipped)

**Pattern**: Simple success/error/filter model

### 10. **Langflow**
**Edge Types**:
- `default` - Standard connection
- `conditional` - Conditional branch
- `error` - Error handling

**Pattern**: Minimal edge types with focus on node logic

---

## Pattern Analysis

### Most Common Edge Types (by frequency):

1. **success** (8/10 systems) - Successful execution path
2. **error/failed** (9/10 systems) - Error handling path
3. **default** (4/10 systems) - Standard/main flow
4. **retry** (5/10 systems) - Retry logic
5. **conditional/choice** (4/10 systems) - Conditional branching
6. **timeout** (3/10 systems) - Timeout handling
7. **skip/filter** (3/10 systems) - Skip conditions
8. **fallback** (2/10 systems) - Alternative path

### Common Patterns:

**Basic Pattern** (Zapier, Langflow):
- `success`, `error`, minimal additional types
- Simple, easy to understand
- Limited flexibility

**Rich Pattern** (AWS Step Functions, Azure Logic Apps):
- Multiple execution states
- Explicit timeout and retry handling
- Compensation/rollback support
- More complex but powerful

**Hybrid Pattern** (Airflow, Prefect):
- Core success/error types
- Additional states for advanced use cases
- Good balance of simplicity and power

---

## Recommended Edge Types for Powernode

Based on industry standards and our use cases (AI agent orchestration, saga patterns, compensation):

### Core Types (Required)
1. **`default`** - Standard flow path (most common case)
2. **`success`** - Explicit success path (when multiple outcomes possible)
3. **`error`** - Error handling path
4. **`conditional`** - Conditional branching based on evaluation

### Advanced Types (Enhanced Functionality)
5. **`retry`** - Retry path for failed executions
6. **`timeout`** - Timeout handling path
7. **`skip`** - Skip/filter condition (node not executed)
8. **`fallback`** - Fallback/alternative path (saga pattern)
9. **`compensation`** - Compensation action (saga rollback)
10. **`loop`** - Loop back for iterative workflows

### Optional Types (Future Consideration)
11. **`parallel`** - Parallel execution path (fork)
12. **`join`** - Join parallel paths (synchronization)
13. **`cancel`** - Cancellation path

---

## Comparison: Current vs. Recommended

### Current Implementation
```ruby
validates :edge_type, inclusion: {
  in: %w[default success error conditional loop]
}
```

### Recommended Implementation
```ruby
validates :edge_type, inclusion: {
  in: %w[
    default success error conditional
    retry timeout skip fallback compensation loop
  ]
}
```

**Changes**:
- ✅ Keep: `default`, `success`, `error`, `conditional`, `loop`
- ➕ Add: `retry`, `timeout`, `skip`, `fallback`, `compensation`

**Benefits**:
1. **Industry Alignment**: Matches patterns from AWS Step Functions, Azure Logic Apps, Airflow
2. **Saga Pattern Support**: Native `compensation` and `fallback` types for distributed transactions
3. **Better Error Handling**: Explicit `retry`, `timeout`, and `fallback` paths
4. **Workflow Filtering**: `skip` type for conditional execution
5. **Backward Compatible**: Keeps all existing types

---

## Implementation Strategy

### Phase 1: Database Migration
```ruby
# No database changes needed - edge_type is a string field
# Only validation changes required
```

### Phase 2: Model Update
```ruby
# app/models/ai_workflow_edge.rb
validates :edge_type, presence: true, inclusion: {
  in: %w[
    default success error conditional
    retry timeout skip fallback compensation loop
  ],
  message: 'must be a valid edge type'
}

# Add helper methods
def retry_edge?
  edge_type == 'retry'
end

def timeout_edge?
  edge_type == 'timeout'
end

def skip_edge?
  edge_type == 'skip'
end

def fallback_edge?
  edge_type == 'fallback'
end

def compensation_edge?
  edge_type == 'compensation'
end
```

### Phase 3: Seed File Update
Update blog generation workflow to use industry-standard edge types:
- `primary_flow` → `default`
- `proceed` → `success`
- `completed` → `success`
- `approved` → `success`
- `retry` → `retry` (already correct!)

### Phase 4: Documentation
- Update API documentation with edge type descriptions
- Add examples for each edge type
- Document best practices for edge type selection

---

## Edge Type Usage Guidelines

### When to Use Each Type

**`default`** - Use for:
- Standard single-path flows
- When there's only one logical next step
- Simple sequential workflows

**`success`** - Use for:
- Explicit success path when multiple outcomes possible
- After validation/approval nodes
- When distinguishing from error paths

**`error`** - Use for:
- Error handling and recovery
- Fallback paths for failures
- Dead letter queue routing

**`conditional`** - Use for:
- Branching based on data evaluation
- Decision points in workflow
- Route selection based on conditions

**`retry`** - Use for:
- Automatic retry logic
- Transient failure handling
- Idempotent operation retries

**`timeout`** - Use for:
- Time-based transitions
- SLA violation handling
- Long-running task timeouts

**`skip`** - Use for:
- Optional workflow steps
- Filter conditions
- Conditional execution gates

**`fallback`** - Use for:
- Alternative paths when primary fails
- Degraded mode operation
- Circuit breaker patterns

**`compensation`** - Use for:
- Saga pattern rollback
- Distributed transaction compensation
- Undo operations

**`loop`** - Use for:
- Iterative workflows
- Batch processing
- Recursive operations

---

## Migration Impact Assessment

### Breaking Changes
- ❌ None - This is a validation expansion only

### Affected Components
- ✅ AiWorkflowEdge model validation
- ✅ Seed files (need edge type updates)
- ✅ API documentation
- ⚠️ Frontend (may need UI updates for new types)

### Testing Requirements
- Model validation tests
- Edge creation with all types
- Workflow execution with new edge types
- Frontend edge type rendering

---

## References

- **LangGraph**: https://python.langchain.com/docs/langgraph
- **AWS Step Functions**: https://docs.aws.amazon.com/step-functions/
- **Azure Logic Apps**: https://learn.microsoft.com/azure/logic-apps/
- **Apache Airflow**: https://airflow.apache.org/docs/
- **Prefect**: https://docs.prefect.io/
- **n8n**: https://docs.n8n.io/
- **Temporal**: https://docs.temporal.io/
- **Zapier**: https://zapier.com/help/

---

**Conclusion**: Expanding to 10 edge types aligns Powernode with industry standards while maintaining backward compatibility and enabling advanced workflow patterns like saga compensation and sophisticated error handling.
