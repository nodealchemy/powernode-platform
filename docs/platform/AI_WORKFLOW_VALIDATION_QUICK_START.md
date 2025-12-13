# AI Workflow Validation - Quick Start Guide

**Status:** ✅ Production Ready
**Version:** 1.0.0
**Last Updated:** December 2, 2025

---

## 🚀 Quick Start

### Backend API Usage

#### 1. Validate a Workflow

```bash
# Create validation
curl -X POST \
  http://localhost:3000/api/v1/ai/workflows/$WORKFLOW_ID/validations \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json"

# Response (201 Created):
{
  "success": true,
  "data": {
    "validation": {
      "id": "uuid",
      "workflow_id": "uuid",
      "overall_status": "valid",
      "health_score": 95,
      "total_nodes": 5,
      "validated_nodes": 5,
      "issues": [],
      "validation_duration_ms": 234
    }
  }
}
```

#### 2. Get Latest Validation

```bash
curl http://localhost:3000/api/v1/ai/workflows/$WORKFLOW_ID/validations/latest \
  -H "Authorization: Bearer $TOKEN"
```

#### 3. Auto-Fix Issues

```bash
# Preview fixes
curl http://localhost:3000/api/v1/ai/workflows/$WORKFLOW_ID/validations/preview_fixes \
  -H "Authorization: Bearer $TOKEN"

# Apply all fixes
curl -X POST \
  http://localhost:3000/api/v1/ai/workflows/$WORKFLOW_ID/validations/auto_fix \
  -H "Authorization: Bearer $TOKEN"

# Response:
{
  "success": true,
  "data": {
    "fixed_count": 3,
    "fixes_applied": [...],
    "health_score_improvement": 15,
    "validation": {...}
  }
}
```

#### 4. Get Platform Statistics

```bash
curl "http://localhost:3000/api/v1/ai/validation_statistics?time_range=30d" \
  -H "Authorization: Bearer $TOKEN"
```

---

## 💻 Frontend Integration

### Basic Validation

```typescript
import { useWorkflowValidation } from '@/features/ai-workflows/hooks/useWorkflowValidation';

function MyWorkflowComponent({ workflow }) {
  const { validate, validationResult, isValidating } = useWorkflowValidation({
    workflowId: workflow.id,
    autoValidate: false, // Set to true for auto-validation on mount
  });

  const handleValidate = async () => {
    const result = await validate();
    console.log('Health score:', result.health_score);
    console.log('Issues found:', result.issues.length);
  };

  return (
    <div>
      <button onClick={handleValidate} disabled={isValidating}>
        {isValidating ? 'Validating...' : 'Validate Workflow'}
      </button>

      {validationResult && (
        <div>
          <p>Health Score: {validationResult.health_score}/100</p>
          <p>Status: {validationResult.overall_status}</p>
        </div>
      )}
    </div>
  );
}
```

### Real-Time Updates

```typescript
import { useValidationWebSocket } from '@/features/ai-workflows/hooks/useValidationWebSocket';

function WorkflowMonitor({ workflowId }) {
  const {
    validationResult,
    isConnected,
    isValidating,
    validationProgress,
    healthAlerts,
  } = useValidationWebSocket({
    workflowId,
    enabled: true,
    onValidationUpdate: (validation) => {
      console.log('Validation updated:', validation);
    },
    onHealthAlert: (alert) => {
      console.warn('Health alert:', alert);
    },
  });

  return (
    <div>
      <div>Connection: {isConnected ? '✅ Connected' : '❌ Disconnected'}</div>

      {isValidating && (
        <div>
          <p>Validating... {validationProgress}%</p>
          <progress value={validationProgress} max={100} />
        </div>
      )}

      {healthAlerts.length > 0 && (
        <div>
          <h4>Health Alerts</h4>
          {healthAlerts.map((alert, i) => (
            <div key={i} className={`alert-${alert.severity}`}>
              {alert.message}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
```

### Statistics Dashboard

```typescript
import { ValidationStatisticsDashboard } from '@/features/ai-workflows/components/validation/ValidationStatisticsDashboard';

function AdminDashboard() {
  return (
    <div>
      <h1>Platform Validation Statistics</h1>
      <ValidationStatisticsDashboard />
    </div>
  );
}
```

### Validation History

```typescript
import { ValidationHistoryPanel } from '@/features/ai-workflows/components/validation/ValidationHistoryPanel';

function WorkflowHistory({ workflowId }) {
  const handleCompare = (validation1Id: string, validation2Id: string) => {
    // Open comparison modal
    console.log('Compare', validation1Id, 'vs', validation2Id);
  };

  return (
    <ValidationHistoryPanel
      workflowId={workflowId}
      onCompare={handleCompare}
    />
  );
}
```

### Auto-Fix Panel

```typescript
import { AutoFixPanel } from '@/features/ai-workflows/components/validation/AutoFixPanel';

function ValidationFixesPanel({ workflowId, issues }) {
  const handleFixComplete = () => {
    // Refresh validation
    console.log('Fixes applied, refreshing validation');
  };

  return (
    <AutoFixPanel
      workflowId={workflowId}
      issues={issues}
      onFixComplete={handleFixComplete}
    />
  );
}
```

---

## 🔧 Background Jobs Setup

### Sidekiq Scheduler Configuration

Add to `config/sidekiq.yml`:

```yaml
:schedule:
  # Validate workflows every 24 hours
  workflow_validation:
    cron: '0 */24 * * *'
    class: WorkflowScheduledValidationJob
    queue: default
    args:
      account_id: null  # null = all accounts
      batch_size: 50

  # Check validation health every 6 hours
  validation_health_check:
    cron: '0 */6 * * *'
    class: WorkflowValidationHealthCheckJob
    queue: default
```

### Manual Job Execution

```ruby
# Validate all stale workflows
WorkflowScheduledValidationJob.perform_later

# Validate specific account
WorkflowScheduledValidationJob.perform_later(account_id: 'uuid')

# Run health check
WorkflowValidationHealthCheckJob.perform_later

# Check specific account health
WorkflowValidationHealthCheckJob.perform_later(account_id: 'uuid')
```

---

## 📊 Validation Rules Reference

### Structural Validation

| Rule | Severity | Description |
|------|----------|-------------|
| `empty_workflow` | error | Workflow has no nodes |
| `missing_start_node` | error | No node marked as start |
| `missing_end_node` | warning | No explicit end node |
| `multiple_start_nodes` | error | Multiple start nodes defined |

### Connectivity Validation

| Rule | Severity | Description |
|------|----------|-------------|
| `orphaned_node` | warning | Node not connected to workflow |
| `unreachable_node` | warning | Node cannot be reached from start |
| `dead_end_node` | info | Node has no outgoing connections |

### Configuration Validation

**AI Agent Nodes:**
- `missing_agent` - No AI agent selected (error)
- `missing_prompt` - No prompt configured (error)
- `missing_timeout` - No timeout configured (warning, auto-fixable)

**API Call Nodes:**
- `missing_url` - No URL configured (error)
- `invalid_url` - Malformed URL (error)
- `missing_method` - No HTTP method (error)
- `missing_timeout` - No timeout (warning, auto-fixable)

**Loop Nodes:**
- `missing_iteration_source` - No iteration source (error)
- `missing_max_iterations` - No max iterations (warning, auto-fixable)
- `invalid_max_iterations` - Max iterations < 1 (error)

**Condition Nodes:**
- `missing_conditions` - No conditions defined (error)
- `invalid_condition` - Malformed condition (error)

**Human Approval Nodes:**
- `missing_approvers` - No approvers defined (error)
- `missing_approval_timeout` - No timeout (warning, auto-fixable)

### Data Flow Validation

| Rule | Severity | Description |
|------|----------|-------------|
| `missing_required_input` | error | Required input not provided |
| `type_mismatch` | warning | Input/output type incompatibility |
| `unmapped_output` | info | Node output not used downstream |

### Variable Validation

| Rule | Severity | Description |
|------|----------|-------------|
| `undefined_variable` | error | Variable referenced but not defined |
| `unused_variable` | info | Variable defined but never used |

---

## 🎯 Health Score Calculation

```ruby
base_score = 100
penalties = {
  error: 15 points per error,
  warning: 5 points per warning,
  info: 2 points per info
}
health_score = [base_score - sum(penalties), 0].max
```

**Health Score Ranges:**
- **90-100:** Excellent (green)
- **70-89:** Good (blue)
- **50-69:** Fair (yellow)
- **0-49:** Poor (red)

---

## 🔐 Required Permissions

### Read Validation
- `ai.workflows.read` - View validations

### Create Validation
- `ai.workflows.execute` - Run validation

### Auto-Fix
- `ai.workflows.execute` - Apply fixes
- `ai.workflows.update` - Modify workflow (implicit)

### Statistics
- `ai.workflows.read` - View statistics
- `system.admin` - View platform-wide stats (optional)

---

## 🐛 Troubleshooting

### "Validation returned no result"

**Cause:** API call failed or returned empty
**Fix:** Check network connection, verify workflow exists

```typescript
const { validate } = useWorkflowValidation({ workflowId });

try {
  const result = await validate();
} catch (error) {
  console.error('Validation failed:', error);
}
```

### "WebSocket not connecting"

**Cause:** ActionCable not initialized
**Fix:** Ensure ActionCable is available on window

```typescript
// Check ActionCable availability
if (!(window as any).ActionCable) {
  console.error('ActionCable not found');
}
```

### "Auto-fix not applying"

**Cause:** Issue not auto-fixable or permissions missing
**Fix:** Check `auto_fixable: true` and permissions

```typescript
const autoFixableIssues = issues.filter(i => i.auto_fixable);
console.log(`${autoFixableIssues.length} issues can be auto-fixed`);
```

### "Background jobs not running"

**Cause:** Sidekiq not configured or not running
**Fix:** Check Sidekiq status

```bash
# Check worker status
scripts/worker-manager.sh status

# Check job queue
bundle exec rails console
> Sidekiq::Queue.new('default').size
```

---

## 📚 API Response Examples

### Validation with Issues

```json
{
  "success": true,
  "data": {
    "validation": {
      "id": "uuid",
      "workflow_id": "uuid",
      "overall_status": "invalid",
      "health_score": 70,
      "total_nodes": 5,
      "validated_nodes": 5,
      "issues": [
        {
          "id": "issue-1",
          "node_id": "node-123",
          "node_name": "AI Agent",
          "node_type": "ai_agent",
          "severity": "error",
          "category": "configuration",
          "rule_id": "missing_agent",
          "rule_name": "AI Agent Configuration",
          "message": "No AI agent selected for this node",
          "suggestion": "Select an AI agent from the configuration panel",
          "auto_fixable": false
        },
        {
          "id": "issue-2",
          "node_id": "node-456",
          "node_name": "API Call",
          "node_type": "api_call",
          "severity": "warning",
          "category": "configuration",
          "rule_id": "missing_timeout",
          "rule_name": "Timeout Configuration",
          "message": "No timeout specified for HTTP request",
          "suggestion": "Set a reasonable timeout value (e.g., 30 seconds)",
          "auto_fixable": true
        }
      ],
      "validation_duration_ms": 456
    }
  }
}
```

### Statistics Response

```json
{
  "success": true,
  "data": {
    "statistics": {
      "overview": {
        "total_workflows": 50,
        "validated_workflows": 45,
        "average_health_score": 85,
        "valid_count": 30,
        "invalid_count": 10,
        "warning_count": 5
      },
      "health_distribution": {
        "healthy": 30,
        "moderate": 10,
        "unhealthy": 5
      },
      "issue_categories": {
        "configuration": 15,
        "connection": 8,
        "data_flow": 5
      },
      "top_issues": [
        {
          "code": "missing_timeout",
          "severity": "warning",
          "category": "configuration",
          "message": "Node timeout not configured",
          "count": 15
        }
      ]
    }
  }
}
```

---

## 🔗 Related Documentation

- [Complete Implementation Guide](./AI_WORKFLOW_VALIDATION_IMPLEMENTATION_COMPLETE.md)
- [Rails Architect Specialist](../backend/RAILS_ARCHITECT_SPECIALIST.md)
- [React Architect Specialist](../frontend/REACT_ARCHITECT_SPECIALIST.md)
- [Background Job Engineer](../backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md)

---

**Need Help?** Check the complete implementation guide or consult the specialist documentation for detailed architectural patterns and examples.
