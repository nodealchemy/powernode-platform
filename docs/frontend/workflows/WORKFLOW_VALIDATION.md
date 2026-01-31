# Workflow Frontend Validation & Debugging

**Debugging guides, fixes, and validation system implementation**

---

## Table of Contents

1. [Preview JSON Parsing Fix](#preview-json-parsing-fix)
2. [Preview Debugging Guide](#preview-debugging-guide)
3. [Validation System Implementation](#validation-system-implementation)
4. [Common Issues & Solutions](#common-issues--solutions)

---

## Preview JSON Parsing Fix

### Problem Summary

The workflow preview modal displayed "No output available" even though the markdown formatter successfully produced structured JSON output with markdown content.

**Root Cause**: Frontend extraction logic returned raw JSON **string** from `markdown_formatter.output` without parsing it first.

### Technical Analysis

**Backend Produces**:
```ruby
{
  "data": {
    "all_node_outputs": {
      "markdown_formatter": {
        "output": "{\"markdown\": \"# Blog...\", \"blog_content\": {...}, ...}"
        #          ^ This is a JSON STRING, not a parsed object
      }
    }
  }
}
```

**Frontend Expected**: Extraction logic checked for `data.markdown` field, but received a string instead.

### Solution Applied

**File**: `/frontend/src/features/ai-workflows/components/WorkflowExecutionDetails.tsx` (lines 1007-1064)

```typescript
// Try markdown_formatter first
if (nodeOutputs.markdown_formatter?.output) {
  const markdownOutput = nodeOutputs.markdown_formatter.output;
  if (typeof markdownOutput === 'string' && !markdownOutput.includes('error')) {
    // Try to parse JSON if it looks like JSON
    if (markdownOutput.trim().startsWith('{')) {
      try {
        const parsed = JSON.parse(markdownOutput);
        // Recursively extract content from parsed JSON
        return extractContent(parsed);  // ✅ Parses JSON, then extracts markdown field
      } catch (e) {
        return markdownOutput;  // Fallback to raw string
      }
    }
    return markdownOutput;
  }
}

// Same pattern applied to writer and editor fallbacks
```

### Data Flow Diagram

```
Backend Output
    ↓
"{\"markdown\": \"# Blog...\", ...}"  (JSON string)
    ↓
Detection: Starts with '{'
    ↓
JSON.parse()
    ↓
{markdown: "# Blog...", blog_content: {...}, ...}  (Object)
    ↓
extractContent(parsed)
    ↓
Check: data.markdown exists
    ↓
Return: "# Blog content..."  (Markdown text)
    ↓
Preview Modal Displays Content ✅
```

### Benefits

1. **Robust JSON Handling**: Automatically detects and parses JSON strings
2. **Backwards Compatibility**: Old workflows with plain text outputs still work
3. **Future-Proof**: Can handle additional nested structures

---

## Preview Debugging Guide

### Step 1: Clear All Browser Caches

**Force Reload**:
- Chrome/Edge: `Ctrl+Shift+R` (Windows/Linux) or `Cmd+Shift+R` (Mac)
- Firefox: `Ctrl+Shift+R` (Windows/Linux) or `Cmd+Shift+R` (Mac)
- Safari: `Cmd+Option+R`

**Clear Application Cache**:
1. Open DevTools (F12)
2. Go to "Application" tab
3. Click "Clear site data"
4. Refresh page

### Step 2: Check Browser Console for Errors

1. Open DevTools (F12)
2. Go to "Console" tab
3. Look for red errors when:
   - Page loads
   - You click the workflow execution
   - You click the "Preview" button

### Step 3: Inspect Network Request

1. Open DevTools → "Network" tab
2. Filter by "Fetch/XHR"
3. Click the Preview button in the UI
4. Find the API request to `/api/v1/workflows/.../runs/...`
5. Check if `output_variables` → `data` → `all_node_outputs` → `markdown_formatter` → `output` exists

### Step 4: Test Extraction Logic Manually

```javascript
// Paste in DevTools Console
const output = {
  data: {
    all_node_outputs: {
      markdown_formatter: {
        output: '{"markdown": "# Test Content", "blog_content": {}}'
      }
    }
  }
};

const extractContent = (data) => {
  if (typeof data === 'string') return data;
  if (!data) return '';

  if (data.markdown && typeof data.markdown === 'string') {
    console.log('✅ Found markdown field:', data.markdown);
    return data.markdown;
  }

  if (data.data?.all_node_outputs) {
    const nodeOutputs = data.data.all_node_outputs;
    if (nodeOutputs.markdown_formatter?.output) {
      const markdownOutput = nodeOutputs.markdown_formatter.output;
      if (typeof markdownOutput === 'string' && markdownOutput.trim().startsWith('{')) {
        try {
          const parsed = JSON.parse(markdownOutput);
          return extractContent(parsed);
        } catch (e) {
          return markdownOutput;
        }
      }
      return markdownOutput;
    }
  }

  return JSON.stringify(data, null, 2);
};

const result = extractContent(output);
console.log('Final result:', result);
```

### Common Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| "Output is undefined" | API response missing output | Check if workflow completed |
| "JSON.parse() throws error" | Output not valid JSON | Check backend output format |
| "markdown field not found" | Backend structure changed | Re-run input mapping fix |
| "Shows old message" | Cached JavaScript | Clear all caches, try incognito |

### Emergency Workaround

1. Click "Download JSON" instead of "Preview"
2. Open the downloaded JSON file
3. Search for `"markdown_formatter"`
4. Copy the `"output"` value
5. Paste into jsonformatter.org

---

## Validation System Implementation

### Current Backend Infrastructure

**WorkflowValidationsController** (`/api/v1/ai/workflows/:workflow_id/validations`):
- `GET /validations` - List validations with filtering
- `GET /validations/:id` - Get specific validation
- `POST /validations` - Create new validation
- `GET /validations/latest` - Get most recent validation

**WorkflowValidation Model**:
- Health score calculation (0-100)
- Issue severity tracking (error/warning/info)
- WebSocket broadcast on creation

### Frontend Infrastructure Status

| Component | Status | Notes |
|-----------|--------|-------|
| `ValidationApiService` | Exists | NOT exported from index.ts |
| `useWorkflowValidation` hook | Exists | Line 69 TODO - returns null |
| `NodeValidationPanel` | Exists | Uses mock data |
| `ValidationRuleCard` | Complete | Working |
| `WorkflowHealthScore` | Complete | Working |

### Implementation Plan

#### Phase 1: Type Consolidation

**Add to `/frontend/src/shared/types/workflow.ts`**:

```typescript
export interface ValidationIssue {
  id: string;
  node_id: string;
  node_name: string;
  node_type: string;
  severity: 'error' | 'warning' | 'info';
  category: ValidationCategory;
  rule_id: string;
  rule_name: string;
  message: string;
  description?: string;
  suggestion?: string;
  auto_fixable: boolean;
  metadata?: Record<string, unknown>;
}

export type ValidationCategory =
  | 'configuration'
  | 'connection'
  | 'data_flow'
  | 'performance'
  | 'security'
  | 'structure';

export interface WorkflowValidationResult {
  id?: string;
  workflow_id: string;
  overall_status: 'valid' | 'warnings' | 'errors' | 'invalid';
  health_score: number;
  total_nodes: number;
  validated_nodes: number;
  issues: ValidationIssue[];
  validation_timestamp?: string;
}

export interface ValidationRule {
  id: string;
  name: string;
  description: string;
  category: ValidationCategory;
  severity: 'error' | 'warning' | 'info';
  enabled: boolean;
  auto_fixable: boolean;
}
```

#### Phase 2: Export ValidationApiService

**Update `/frontend/src/shared/services/ai/index.ts`**:

```typescript
import { validationApi } from './ValidationApiService';

export { validationApi };

export const aiApi = {
  workflows: workflowsApi,
  agents: agentsApi,
  providers: providersApi,
  monitoring: monitoringApi,
  validation: validationApi,  // ADD THIS
} as const;
```

#### Phase 3: Fix useWorkflowValidation Hook

**Update `/frontend/src/features/ai-workflows/hooks/useWorkflowValidation.ts`**:

```typescript
import { validationApi } from '@/shared/services/ai';

const validate = useCallback(async (): Promise<WorkflowValidationResult | null> => {
  if (!workflowId) {
    setError('No workflow ID provided');
    return null;
  }

  try {
    setIsValidating(true);
    setError(null);

    // FIXED: Actually call the API
    const response = await validationApi.validateWorkflow(workflowId);
    setValidationResult(response.validation);
    return response.validation;
  } catch (err) {
    const errorMessage = err instanceof Error ? err.message : 'Validation failed';
    setError(errorMessage);
    return null;
  } finally {
    setIsValidating(false);
  }
}, [workflowId]);
```

#### Phase 4: New UI Components

**ValidationHistoryPanel**:
- Timeline view of past validations
- Health score trend visualization
- Filter by status (valid/warning/invalid)

**ValidationStatisticsDashboard**:
- Health score trend chart
- Most common issues bar chart
- Time range selector (7d/30d/90d)

**AutoFixPanel**:
- List of auto-fixable issues with checkboxes
- Preview of what will change
- Apply selected fixes button

**ValidationRulesManager**:
- List all rules with filters
- Enable/disable rules
- Admin interface for rule management

#### Phase 5: WebSocket Integration

**Create `/frontend/src/features/ai-workflows/hooks/useValidationWebSocket.ts`**:

```typescript
import { useEffect } from 'react';
import { useWebSocket } from '@/shared/hooks/useWebSocket';
import type { WorkflowValidationResult } from '@/shared/types/workflow';

interface UseValidationWebSocketOptions {
  workflowId: string;
  onValidationResult?: (validation: WorkflowValidationResult) => void;
}

export const useValidationWebSocket = (options: UseValidationWebSocketOptions) => {
  const { workflowId, onValidationResult } = options;
  const { isConnected, subscribe } = useWebSocket();

  useEffect(() => {
    if (!workflowId || !isConnected) return;

    const handleMessage = (message: any) => {
      if (message.type === 'validation_result' && message.validation) {
        onValidationResult?.(message.validation);
      }
    };

    const unsubscribe = subscribe({
      channel: 'AiOrchestrationChannel',
      params: { type: 'workflow', id: workflowId },
      onMessage: handleMessage
    });

    return unsubscribe;
  }, [workflowId, isConnected, subscribe, onValidationResult]);

  return { isConnected };
};
```

### Implementation Order

```
Phase 1 (Foundation) - MUST be completed first
├── 1.1 Type Consolidation
├── 1.2 Export ValidationApiService
└── 1.3 Fix useWorkflowValidation hook

Phase 2 (New Components) - After Phase 1
├── ValidationHistoryPanel
├── ValidationStatisticsDashboard
├── AutoFixPanel
└── ValidationRulesManager

Phase 3 (Integration) - After Phase 2
├── Update NodeValidationPanel
├── Update WorkflowDetailPage
└── WorkflowBuilder Toolbar

Phase 4 (WebSocket) - Parallel with Phase 2
├── useValidationWebSocket hook
└── Real-time updates integration
```

---

## Common Issues & Solutions

### Issue: Preview Shows "No output available"

**Symptoms**: Preview modal displays empty state despite workflow completion

**Checks**:
1. Is workflow actually completed? Check status
2. Does API response contain `output_variables`?
3. Is the output a JSON string that needs parsing?

**Fix**: See [Preview JSON Parsing Fix](#preview-json-parsing-fix)

### Issue: Validation Hook Returns Null

**Symptoms**: `useWorkflowValidation` always returns null

**Cause**: Line 69 in hook has TODO comment - doesn't call API

**Fix**: Update hook to call `validationApi.validateWorkflow()`

### Issue: Validation Types Not Found

**Symptoms**: TypeScript errors for validation interfaces

**Cause**: Types duplicated across 3+ files, some not exported

**Fix**: Consolidate types in `workflow.ts`, export from index

### Issue: WebSocket Updates Not Received

**Symptoms**: No real-time validation updates

**Checks**:
1. Is WebSocket connected?
2. Is subscription correct?
3. Does backend broadcast validation events?

**Fix**: Use `useValidationWebSocket` hook with correct channel params

### Issue: Auto-Fix Not Working

**Symptoms**: Auto-fix button doesn't apply changes

**Checks**:
1. Is backend auto-fix endpoint implemented?
2. Are issues marked as `auto_fixable: true`?
3. Does user have edit permission?

---

## Files Reference

### Modified Files
- `WorkflowExecutionDetails.tsx` - JSON parsing, preview modal
- `useWorkflowValidation.ts` - API integration fix
- `ValidationApiService.ts` - Type alignment
- `workflow.ts` - Type consolidation

### New Files to Create
- `useValidationWebSocket.ts`
- `ValidationHistoryPanel.tsx`
- `ValidationStatisticsDashboard.tsx`
- `AutoFixPanel.tsx`
- `ValidationRulesManager.tsx`
- `validation/index.ts`

---

**Document Status**: ✅ Complete
**Consolidates**: WORKFLOW_PREVIEW_JSON_PARSING_FIX.md, WORKFLOW_PREVIEW_DEBUGGING_GUIDE.md, AI_WORKFLOW_VALIDATION_IMPLEMENTATION_PLAN.md

