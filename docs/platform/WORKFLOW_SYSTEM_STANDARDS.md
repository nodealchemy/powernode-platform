# Workflow System Standards

**Comprehensive data flow, I/O standards, and validation guidelines**

---

## Table of Contents

1. [Data Flow Standard](#data-flow-standard)
2. [I/O Standard](#io-standard)
3. [Node Output Structure](#node-output-structure)
4. [Data Preservation](#data-preservation)
5. [Real-Time Validation Checklist](#real-time-validation-checklist)

---

## Data Flow Standard

### Core Principles

1. **Data flows automatically** from predecessor nodes to successor nodes - always
2. **Industry-standard keys**: `input`, `output`, `data`, `result`, `metadata`
3. **Zero configuration** required for basic workflows

### Priority Order

When building node input data, values are merged in this priority order (later overrides earlier):

1. Workflow input variables (lowest priority)
2. Predecessor `output`, `data`, `result` keys (merged from all predecessors)
3. Explicit input mapping (if configured)
4. Static inputs (highest priority)

### Auto-Wire Algorithm

```ruby
def auto_wire_predecessor_outputs
  incoming_edges = @workflow_run.ai_workflow.ai_workflow_edges.where(
    target_node_id: @node.node_id
  )

  predecessor_node_ids = incoming_edges.pluck(:source_node_id)
  auto_wired = {}

  predecessor_node_ids.each do |predecessor_id|
    result_data = @previous_results[predecessor_id]
    if result_data.present?
      if result_data[:output_data].present?
        auto_wired.merge!(result_data[:output_data])
      elsif result_data.is_a?(Hash)
        auto_wired.merge!(result_data)
      end
    end
  end

  auto_wired
end
```

### Validation Rules

1. All non-start nodes must have incoming edges
2. All nodes reachable from start node
3. All nodes can reach end node
4. No disconnected subgraphs

### Explicit Data Mapping (Optional)

Use when you need to:
- Rename keys for clarity
- Select specific fields from large outputs
- Prevent key collisions

```ruby
edge.configuration = {
  data_mapping: {
    "{{research_1.output}}" => "research_findings",
    "{{research_1.data.agent_name}}" => "researcher",
    "{{input.topic}}" => "topic"
  }
}
```

---

## I/O Standard

### Industry Alignment

Based on analysis of major platforms (LangChain, n8n, Zapier, Make, Temporal):

| Platform | Primary Keys | Data Keys | Metadata Keys |
|----------|--------------|-----------|---------------|
| **LangChain** | `input`, `output` | `context`, `chat_history` | `intermediate_steps` |
| **n8n** | - | `json`, `binary` | `pairedItem` |
| **Zapier** | `input_data`, `output_data` | - | `meta` |
| **Make** | `input`, `output` | `data` | `metadata` |
| **Temporal** | `input`, `result` | `context` | `metadata` |

### Standard Keys

| Key | Required | Purpose | Example |
|-----|----------|---------|---------|
| `input` | No | Data provided to node | `{ topic: "AI" }` |
| `output` | Yes | Primary result | `"Generated content"` |
| `data` | No | Additional data | `{ word_count: 500 }` |
| `result` | No | Computed value | `{ success: true }` |
| `metadata` | Yes | Execution info | `{ node_id: "agent_1" }` |
| `context` | No | Contextual info | `{ session: {...} }` |
| `error` | No | Error details | `{ message: "..." }` |

### Key Definitions

#### `output` (Required)
Primary result produced by the node.
```json
{
  "output": "Generated blog post content..."
}
```

#### `data` (Optional)
Supporting data and structured results.
```json
{
  "data": {
    "agent_id": "agent_123",
    "agent_name": "Blog Writer",
    "model": "claude-3-5-sonnet-20241022"
  }
}
```

#### `metadata` (Required)
Execution information and context.
```json
{
  "metadata": {
    "node_id": "writer_1",
    "node_type": "ai_agent",
    "executed_at": "2025-10-12T10:31:00Z",
    "duration_ms": 1234,
    "cost": 0.002,
    "tokens_used": 150
  }
}
```

---

## Node Output Structure

### AI Agent Node

```json
{
  "input": {
    "prompt": "Write about {{topic}}",
    "topic": "AI in Healthcare"
  },
  "output": "Generated blog post content about AI in Healthcare...",
  "data": {
    "agent_id": "agent_123",
    "agent_name": "Blog Writer",
    "model": "claude-3-5-sonnet-20241022"
  },
  "metadata": {
    "node_id": "writer_1",
    "node_type": "ai_agent",
    "executed_at": "2025-10-12T10:31:00Z",
    "duration_ms": 1234,
    "cost": 0.002,
    "tokens_used": 150
  }
}
```

### Start Node

```json
{
  "output": {
    "workflow_id": "wf_123",
    "run_id": "run_456",
    "triggered_at": "2025-10-12T10:30:00Z"
  },
  "data": {
    "input_variables": { "topic": "AI in Healthcare" }
  },
  "metadata": {
    "node_id": "start_1",
    "node_type": "start",
    "trigger_type": "manual"
  }
}
```

### End Node

```json
{
  "output": "Workflow completed successfully",
  "result": {
    "status": "completed",
    "final_output": "Polished blog post content..."
  },
  "data": {
    "all_node_outputs": {
      "research_1": {...},
      "writer_1": {...}
    },
    "execution_path": ["start_1", "research_1", "writer_1", "end_1"]
  },
  "metadata": {
    "node_id": "end_1",
    "node_type": "end",
    "completed_at": "2025-10-12T10:35:00Z",
    "total_duration_ms": 180000,
    "total_cost": 0.015,
    "nodes_executed": 5
  }
}
```

### Transform Node

```json
{
  "input": { "raw_data": "original content" },
  "output": "transformed content",
  "result": {
    "transformation": "uppercase",
    "items_processed": 1
  },
  "metadata": {
    "node_id": "transform_1",
    "node_type": "transform"
  }
}
```

### API Call Node

```json
{
  "input": {
    "url": "https://api.example.com/data",
    "method": "GET"
  },
  "output": {
    "status": 200,
    "body": {...}
  },
  "data": {
    "headers": {...},
    "response_time_ms": 123
  },
  "metadata": {
    "node_id": "api_1",
    "node_type": "api_call"
  }
}
```

### Condition Node

```json
{
  "input": { "value": 42, "threshold": 50 },
  "output": false,
  "result": {
    "condition_met": false,
    "evaluated_branch": "else"
  },
  "metadata": {
    "node_id": "condition_1",
    "node_type": "condition"
  }
}
```

---

## Data Preservation

### Problem

Markdown formatter nodes can replace original structured data (SEO content, image suggestions) with just the formatted output.

### Solution

Changed markdown formatter from a **replacement node** to an **enrichment node**:

**Before**: Input → Nodes → **Markdown String Only** ❌

**After**: Input → Nodes → **Markdown + SEO Data + Images + Metadata** ✅

### New Output Structure

```json
{
  "markdown": "# Formatted Blog Post\n\nContent...",
  "blog_content": { "title": "...", "body": "..." },
  "seo_data": { "meta_description": "...", "keywords": [...] },
  "image_data": { "featured_image": "...", "suggestions": [...] },
  "metadata": { "formatted_at": "...", "format": "markdown" }
}
```

### Extraction Priority

Frontend, backend download, and preview all use same priority system:

1. **PRIORITY 1**: New `markdown` field (current format)
2. **PRIORITY 2**: Nested End node structure (`data.result.final_output`)
3. **PRIORITY 3**: Legacy field names (`output`, `final_markdown`, etc.)

### Backend Implementation

```ruby
# format_as_markdown() extraction
markdown_content = output_vars['markdown']

if markdown_content.blank? && output_vars['result'].is_a?(Hash)
  final_output = output_vars['result']['final_output']
  markdown_content = final_output['markdown'] || final_output['result']
end

if markdown_content.blank?
  markdown_content = output_vars['final_markdown'] ||
                    output_vars['markdown_formatter_output']
end
```

---

## Real-Time Validation Checklist

### Pre-Test Setup

```bash
# Ensure all services are running
sudo scripts/systemd/powernode-installer.sh status

# Enable WebSocket debug monitoring in browser console
console.log('🔍 WebSocket Monitoring Enabled');
const origOnMessage = WebSocket.prototype.onmessage;
WebSocket.prototype.onmessage = function(event) {
  try {
    const data = JSON.parse(event.data);
    if (data.message?.event?.includes('node.execution')) {
      console.log('📡 NODE UPDATE:', data.message.event, data.message.payload);
    }
  } catch(e) {}
  return origOnMessage?.call(this, event);
};
```

### Frontend Validation

**Subscription Timing**:
- [ ] Navigate to AI Tools → Workflows → [Any Workflow]
- [ ] Verify subscription happens immediately
- [ ] Check for message: "✅ SUBSCRIPTION CONFIRMED"

**Real-Time Node Updates**:
- [ ] Execute workflow
- [ ] Watch node badges: ⏳ (pending) → ▶️ (running) → ✅ (completed)
- [ ] Confirm no page refresh needed
- [ ] Check console for "📡 NODE UPDATE" messages

**Execution History Updates**:
- [ ] New runs appear without refresh
- [ ] Status badges update in real-time
- [ ] Progress percentage increases
- [ ] Duration updates continuously
- [ ] Cost accumulates as nodes complete

### Backend Validation

```bash
# Monitor backend broadcasts
journalctl -u powernode-backend@default -f | grep -E "BROADCASTING|workflow.node.execution"
```

**Expected output**:
```
[STATE_MACHINE] Broadcasting status change: pending -> running
✅ BROADCASTING STATUS CHANGE: [execution-id] pending -> running
Broadcasting node status change: [node-id] -> running (Node Name)
[ActionCable] Broadcasting to ai_orchestration:workflow_run:[id]
```

### Quick Health Check

```bash
#!/bin/bash
echo "🔍 Validating WebSocket Real-Time Updates..."

# Check services
echo "1. Service Status:"
sudo scripts/systemd/powernode-installer.sh status

# Check WorkflowExecutor
echo -e "\n2. WorkflowExecutor State Methods:"
grep -c "start_execution!\|complete_execution!\|fail_execution!" \
  $POWERNODE_ROOT/server/app/services/mcp/workflow_executor.rb

echo -e "\n✅ Validation complete!"
```

### Success Criteria

1. **Frontend**: Immediate subscription, real-time badge updates
2. **Backend**: Broadcasts logged for all state changes
3. **Integration**: Multiple workflows update simultaneously
4. **Performance**: Updates appear within 100-500ms
5. **Reliability**: No missed updates across 10+ executions

---

## Best Practices

### 1. Use `output` for Primary Results

**Good**:
```ruby
{ output: "Generated blog post..." }
```

**Bad**:
```ruby
{ output_data: { agent_output: "Generated blog post..." } }
```

### 2. Use `data` for Supporting Information

**Good**:
```ruby
{
  output: "Blog post...",
  data: { word_count: 500, keywords: ["AI", "Healthcare"] }
}
```

### 3. Keep `metadata` Consistent

**Good**:
```ruby
{
  metadata: {
    node_id: "agent_1",
    node_type: "ai_agent",
    executed_at: "2025-10-12T10:30:00Z",
    cost: 0.002
  }
}
```

### 4. Design for Automatic Flow

Design workflows assuming data flows automatically between connected nodes without explicit mapping.

### 5. Document Expected Keys

```ruby
# Expected input keys:
# - topic (string): Blog topic
# - research_data (string): Research findings from predecessor
#
# Output keys:
# - output (string): Generated blog post
# - data.word_count (integer): Number of words
```

---

## Troubleshooting

### Problem: Node not receiving expected data

**Check**:
1. Does predecessor node complete successfully?
2. Does predecessor node have `output_data` in its result?
3. Are there incoming edges to this node?
4. Is there explicit mapping overriding automatic flow?

**Debug**:
```ruby
node_execution = run.ai_workflow_node_executions.find_by(node_id: 'node_id')
puts "Input received: #{node_execution.input_data.inspect}"
```

### Problem: Key collision

**Symptom**: Node receives data from wrong predecessor

**Cause**: Multiple predecessors output the same key name

**Solution**: Use explicit data mapping:
```ruby
edge.configuration = {
  data_mapping: {
    "{{node1.agent_output}}" => "node1_output",
    "{{node2.agent_output}}" => "node2_output"
  }
}
```

### Problem: No updates received

**Check**:
1. WebSocket connected?
2. Subscription timing correct?
3. Backend logs show broadcasts?
4. Check WorkflowExecutor state methods

---

**Document Status**: ✅ Complete
**Consolidates**: WORKFLOW_DATA_FLOW_V1_STANDARD.md, WORKFLOW_IO_STANDARD.md, WORKFLOW_DATA_FLOW_AND_FAILURE_HANDLING_SUMMARY.md, WORKFLOW_DATA_PRESERVATION_SUMMARY.md, WORKFLOW_REALTIME_VALIDATION_CHECKLIST.md
