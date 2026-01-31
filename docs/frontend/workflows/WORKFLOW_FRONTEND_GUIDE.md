# Workflow Frontend Guide

**UI components, optimizations, and feature implementations**

---

## Table of Contents

1. [Workflow Builder Optimizations](#workflow-builder-optimizations)
2. [Handle Orientation System](#handle-orientation-system)
3. [Node Actions Menu](#node-actions-menu)
4. [Output Preview Feature](#output-preview-feature)
5. [Inline Editing Modal](#inline-editing-modal)
6. [Best Practices](#best-practices)

---

## Workflow Builder Optimizations

### Overview

Comprehensive optimization of the workflow builder removes unnecessary complexity, eliminates artificial node positioning, and simplifies state management patterns.

### 1. Removed Artificial Node Staggering

**File**: `frontend/src/shared/utils/workflowLayout.ts`

**Problem**: Manual staggering alternated nodes left/right, creating visually messy layouts.

**Solution**: Removed 48 lines of staggering logic. Let dagre's algorithm handle layout naturally.

**Impact**:
- Cleaner, more professional-looking workflow layouts
- Nodes align in proper rows/columns
- More predictable positioning

### 2. Increased Node Spacing

Increased spacing parameters to prevent overlaps:

```typescript
// Small workflows (≤10 nodes)
nodesep: 100,     // +67% increase
ranksep: 120      // +71% increase

// Medium workflows (11-20 nodes)
nodesep: 80,      // +60% increase
ranksep: 100      // +67% increase

// Large workflows (>20 nodes)
nodesep: 70,      // +75% increase
ranksep: 90       // +80% increase
```

### 3. Simplified handleArrange Function

**File**: `frontend/src/shared/components/workflow/WorkflowBuilder.tsx`

**Before**: 4 nested setTimeout chains (25ms, 75ms, 250ms delays)

**After**: Single state update + fitView call

```typescript
// Simplified approach
setNodes(allNodesWithOrientation);
setHasChanges(true);

setTimeout(() => {
  reactFlowInstance.current?.fitView({
    padding: 0.2,
    duration: 800
  });
}, 100);
```

**Impact**: 88% code reduction in arrange logic

### 4. Simplified onUpdateNode Orientation Logic

**Before**: 67 lines of complex node remounting logic

**After**: Direct node data update - React Flow handles the rest

```typescript
setNodes((nds) =>
  nds.map((node) => {
    if (node.id === nodeId) {
      const updatedData = { ...node.data, ...updates };
      return { ...node, data: updatedData };
    }
    return node;
  })
);
```

### Summary of Changes

| Area | Lines Removed | Lines Added | Net Change |
|------|---------------|-------------|------------|
| Staggering logic | 48 | 0 | -48 |
| handleArrange complexity | 72 | 10 | -62 |
| onUpdateNode complexity | 67 | 19 | -48 |
| Duplicate edge rebuilding | 29 | 0 | -29 |
| Redundant safety calls | 10 | 0 | -10 |
| **Total** | **226** | **29** | **-197** |

---

## Handle Orientation System

### Problem

When changing a node's handle orientation (vertical ↔ horizontal), handles would visually update but edge connections remained attached to old positions. React Flow caches handle positions internally.

### Solution: Clean Node Remount Pattern

**File**: `WorkflowBuilder.tsx` (lines 661-733)

```typescript
const onUpdateNode = useCallback((nodeId: string, updates: Partial<Node['data']>) => {
  const currentNode = nodes.find(n => n.id === nodeId);
  const newOrientation = updates.metadata?.handleOrientation;
  const currentOrientation = currentNode?.data?.metadata?.handleOrientation ||
                           currentNode?.data?.handleOrientation;
  const orientationChanging = newOrientation && newOrientation !== currentOrientation;

  if (orientationChanging && currentNode) {
    // Step 1: Capture affected edges
    const affectedEdges = edges.filter(edge =>
      edge.source === nodeId || edge.target === nodeId
    );

    // Step 2: Prepare updated node
    const updatedNode = {
      ...currentNode,
      data: { ...currentNode.data, ...updates, handleOrientation: newOrientation }
    };

    // Step 3: Remove node and edges (clears React Flow cache)
    setNodes((nds) => nds.filter(n => n.id !== nodeId));
    setEdges((eds) => eds.filter(e => e.source !== nodeId && e.target !== nodeId));

    // Step 4: Re-add node after 50ms
    setTimeout(() => {
      setNodes((nds) => [...nds, updatedNode]);

      // Step 5: Re-add edges after 100ms
      setTimeout(() => {
        const rebuiltEdges = affectedEdges.map(edge => ({
          ...edge,
          id: generateUniqueEdgeId(`${edge.source}-${edge.target}`),
        }));
        setEdges((eds) => [...eds, ...rebuiltEdges]);
      }, 100);
    }, 50);
  } else {
    // Normal update without orientation change
    setNodes((nds) =>
      nds.map((node) => node.id === nodeId
        ? { ...node, data: { ...node.data, ...updates } }
        : node
      )
    );
  }
}, [nodes, edges, setNodes, setEdges]);
```

### Edge Properties Preserved

- `type` - Edge type (conditional, default, curved)
- `animated` - Animation state
- `style` - Colors, stroke width, custom styles
- `markerEnd` - Arrow markers and colors
- `label` - Edge labels and positioning
- `data` - Custom edge metadata

### Trade-offs

**Pros**:
- Reliable - Always works regardless of React Flow's internal state
- Complete - Fully rebuilds handle registry from scratch
- Preserves - All edge properties maintained

**Cons**:
- Brief visual flicker (150ms) during orientation change
- Requires two setTimeout calls for proper timing

---

## Node Actions Menu

### Menu Consolidation

**Before**: Two separate dropdown menus (AIToolsMenu + NodeToolsMenu)

**After**: Single unified `NodeActionsMenu` component

### Items Removed (22 non-functional stubs)

AI features (planned): AI Insights, Analyze Node, Optimize Node, Generate Variations, etc.

Node features (planned): Edit Node, Configure, Duplicate, Test Run, etc.

### Items Kept (3 functional)

1. **Chat Assistant** - Opens NodeOperationsChat with AI agent
2. **Copy Node ID** - Copies node ID to clipboard
3. **Delete Node** - Deletes node with confirmation

### Implementation

**File**: `frontend/src/shared/components/workflow/NodeActionsMenu.tsx`

```typescript
import { NodeActionsMenu } from '../NodeActionsMenu';
import { useWorkflowContext } from '../WorkflowContext';

const { onOpenChat } = useWorkflowContext();

<NodeActionsMenu
  nodeId={id}
  nodeType="ai_agent"
  nodeName={data.name}
  isSelected={selected}
  hasErrors={false}
  onOpenChat={onOpenChat}
/>
```

### Menu Layout

```
┌─────────────────────────┐
│ 💬 Chat Assistant       │  ← AI Action
├─────────────────────────┤
│ 🔗 Copy Node ID         │  ← Node Actions
│ 🗑️  Delete Node         │
└─────────────────────────┘
```

### Click-Outside Dismissal

Enhanced DropdownMenu to use event capture phase:

```typescript
// Capture phase ensures dropdowns close even with stopPropagation
document.addEventListener('mousedown', handleClickOutside, true);
document.addEventListener('click', handleClickOutside, true);
```

---

## Output Preview Feature

### Overview

Multi-format workflow output preview modal with real-time format switching and rendered markdown display.

### Features

- Support all download formats (JSON, Text, Markdown)
- Render markdown content visually in browser
- Format switching without closing modal
- Copy and download actions from preview

### Implementation

**File**: `/frontend/src/features/ai-workflows/components/WorkflowExecutionDetails.tsx`

#### State Management

```typescript
const [showPreviewModal, setShowPreviewModal] = useState(false);
const [previewFormat, setPreviewFormat] = useState<'json' | 'markdown' | 'text'>('json');
```

#### Output Extraction

```typescript
const getFormattedOutput = useCallback((format: 'json' | 'markdown' | 'text'): string => {
  const output = currentRun.output || currentRun.outputVariables || currentRun.output_variables ||
                 run.output || run.outputVariables || run.output_variables;

  if (!output) {
    return 'No output available.';
  }

  const extractContent = (data: any): string => {
    // Check nested End node structure (priority)
    if (data.result?.final_output) {
      // ... extraction logic
    }
    // ... field name checking
  };

  const content = extractContent(output);

  switch (format) {
    case 'json': return JSON.stringify(output, null, 2);
    case 'markdown': return content;
    case 'text': return stripMarkdownFormatting(content);
  }
}, [currentRun, run]);
```

#### Markdown Rendering

```typescript
const renderMarkdownAsHTML = useCallback((markdown: string): string => {
  let html = markdown
    .replace(/^######\s(.+)$/gm, '<h6>$1</h6>')
    .replace(/^#####\s(.+)$/gm, '<h5>$1</h5>')
    .replace(/\*\*\*(.+?)\*\*\*/g, '<strong><em>$1</em></strong>')
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
  return html;
}, []);
```

### Content Extraction Flow

```
User clicks Preview Button
       ↓
Modal opens with default format (JSON)
       ↓
getFormattedOutput(format) called
       ↓
Extract output from currentRun.output_variables
       ↓
Check nested End node structure (PRIORITY 1)
├─ result.final_output.result ✓
├─ result.final_output.output
└─ result.final_output.markdown
       ↓
If not found, check common field names (PRIORITY 2)
├─ final_markdown, markdown, output, result, content
       ↓
Apply format-specific processing
├─ JSON: JSON.stringify(output, null, 2)
├─ Markdown: Return content as-is
└─ Text: Strip markdown formatting
```

### Supported Output Structures

**End Node Format (Priority)**:
```javascript
{ result: { final_output: { result: "# Blog Post..." } } }
```

**Direct Field Format**:
```javascript
{ final_markdown: "# Blog Post..." }
```

---

## Inline Editing Modal

### Overview

Enhanced Workflow Detail Modal supports inline editing without separate edit page.

### Editable Fields

**Basic Information Tab**:
- Name (text input)
- Description (textarea)
- Status (dropdown: draft, active, inactive, archived, paused)
- Visibility (dropdown: private, account, public)
- Tags (comma-separated input)

**Configuration Tab**:
- Execution Mode (dropdown: sequential, parallel, conditional)
- Timeout (number input, in seconds)
- Advanced Configuration (JSON textarea with validation)

### Implementation

```typescript
const [isEditMode, setIsEditMode] = useState(false);
const [isSaving, setIsSaving] = useState(false);
const [editedWorkflow, setEditedWorkflow] = useState<Partial<AiWorkflow>>({});
```

### API Integration

```typescript
await workflowsApi.updateWorkflow(workflow.id, {
  name,
  description,
  status,
  visibility,
  tags,
  execution_mode,
  timeout_seconds,
  configuration
});
```

### Permission-Based Controls

- Edit button: `ai.workflows.update` permission
- Execute button: `ai.workflows.execute` permission
- Active workflows can be executed directly

### Benefits

1. **Streamlined UX**: No separate edit page navigation
2. **Context Preservation**: Users stay on same screen
3. **Better Mobile Experience**: Modal-based editing
4. **Faster Workflow**: Fewer clicks to view → edit → save

---

## Best Practices

### 1. React Flow State Updates

**Do**: Let React Flow handle edge updates automatically
```typescript
setNodes(updatedNodes);  // React Flow recalculates edges
```

**Don't**: Use complex setTimeout chains to force re-renders

### 2. Layout Algorithms

**Do**: Use dagre's natural layout with increased spacing
```typescript
nodesep: 100,
ranksep: 120
```

**Don't**: Apply manual staggering offsets

### 3. Handle Position Changes

**Do**: Use node remount pattern for orientation changes
```typescript
// Remove node → Re-add with new orientation → Reconnect edges
```

**Don't**: Expect data-only updates to refresh React Flow's handle cache

### 4. Content Extraction

**Do**: Check both state and props for data availability
```typescript
const output = currentRun.output || run.output;
```

**Don't**: Assume data is always in state after WebSocket updates

### 5. Format Switching

**Do**: Use memoized callbacks for format transformations
```typescript
const getFormattedOutput = useCallback((format) => { ... }, [deps]);
```

**Don't**: Recalculate entire output on every render

---

## Testing Recommendations

### Auto-Arrange
- Test with 3, 10, 25 node workflows
- Verify no overlaps occur
- Check horizontal vs vertical layouts
- Confirm nodes align in clean rows/columns

### Node Configuration
- Change handle orientation
- Verify edges update correctly
- Test with multiple connected edges

### Save/Load
- Save workflow, reload page
- Verify all nodes/edges preserved
- Check handle orientations maintained

### Preview Modal
- Test all three formats: JSON, Text, Markdown
- Verify copy to clipboard works
- Test download functionality

---

**Document Status**: ✅ Complete
**Consolidates**: WORKFLOW_BUILDER_OPTIMIZATIONS.md, WORKFLOW_BUILDER_HANDLE_ORIENTATION_FIX.md, WORKFLOW_NODE_MENU_CLEANUP.md, WORKFLOW_OUTPUT_PREVIEW_FEATURE.md, WORKFLOW_DETAIL_MODAL_INLINE_EDITING.md

