# AI Functionality Frontend Manual Testing Plan

## Overview

Comprehensive manual testing plan for all AI components with **frontend-first approach**. All tests are executable through the UI at `/app/ai/*` routes with real AI execution via Ollama.

**Scope**: 26 phases, 100+ test cases, 20 AI navigation items

---

## Phase 0: Prerequisites

### 0.1 Environment Setup
```bash
# Start all services
sudo systemctl start powernode.target
```

**Note**: Ollama is pre-configured as a remote provider in the admin account. Use the provider URL and credentials provided for your development environment.

### 0.2 Test User Requirements
- Full AI permissions: `ai.providers.*`, `ai.agents.*`, `ai.workflows.*`, `ai.conversations.*`, `ai.context.*`, `ai.analytics.*`
- Login at `https://dev.powernode.org` or `http://localhost:3000`

---

## Phase 1: Providers (`/app/ai/providers`)

| Test | Steps | Expected |
|------|-------|----------|
| **1.1 Verify Ollama Provider** | Navigate to providers → Locate pre-configured Ollama provider | Provider card visible with configured URL |
| **1.2 Check Credentials** | Click provider → Credentials tab | Credential configured with default checkmark |
| **1.3 Test Connection** | Click "Test Connection" on provider card | Green success, response time shown |
| **1.4 Sync Models** | Click "Sync Models" in provider detail | Model list populated (llama3:8b, etc.) |

---

## Phase 2: Agents (`/app/ai/agents`)

| Test | Steps | Expected |
|------|-------|----------|
| **2.1 Create Agent** | Click "Create Agent" → Name: "Test Agent" → Provider: Ollama → Model: llama3:8b → System prompt: "You are helpful." → Save | Agent card appears |
| **2.2 Execute Agent** | Click "Execute" on agent → Enter: "What is 2+2?" → Submit | Streaming response: "4" with token count |
| **2.3 View History** | Click agent → History tab | Execution record with timestamp, duration |
| **2.4 Edit Agent** | Click edit → Change temperature → Save | Changes reflected |

---

## Phase 3: Conversations (`/app/ai/conversations`)

| Test | Steps | Expected |
|------|-------|----------|
| **3.1 Start Conversation** | Click "Start Conversation" → Select agent → Title: "Test Chat" → Create | Conversation created, detail view opens |
| **3.2 Send Message** | Click "Continue" → Enter: "My name is Test User" → Send | AI response with greeting |
| **3.3 Context Retention** | Send: "What is my name?" | AI responds with "Test User" (remembers context) |
| **3.4 Multi-turn** | Continue conversation with 3+ messages | Full history visible, scrollable |

---

## Phase 4: Workflows (`/app/ai/workflows`)

| Test | Steps | Expected |
|------|-------|----------|
| **4.1 Create Workflow** | Click "Create Workflow" → Name: "Simple AI Flow" → Save | Workflow in list |
| **4.2 Add Nodes** | Open workflow → Add Start node → Add AI Agent node (select test agent) → Add End node → Connect | Visual connections on canvas |
| **4.3 Execute Workflow** | Click play → Enter input → Execute | Execution runs, node-by-node progress |
| **4.4 View Results** | Wait for completion → Check results | Output from AI agent displayed |

---

## Phase 5: Agent Teams (`/app/ai/agent-teams`)

| Test | Steps | Expected |
|------|-------|----------|
| **5.1 Create Team** | Click "Create Team" → Name: "Test Team" → Type: Sequential → Add 2 agents | Team card with member count |
| **5.2 Execute Team** | Click "Execute" on team card → Enter task | Sequential agent execution, live updates |
| **5.3 Monitor Progress** | Watch TeamExecutionMonitor during execution | Real-time agent-by-agent status |

---

## Phase 6: Ralph Loops (`/app/ai/ralph-loops`)

| Test | Steps | Expected |
|------|-------|----------|
| **6.1 Create Loop** | Click "Create Loop" → Name, AI tool: Ollama → Save | Loop in list with Pending status |
| **6.2 Add Tasks** | Click loop → Tasks tab → Add task with description | Task appears in list |
| **6.3 Start Loop** | Click "Start Loop" | Status → Running, WebSocket indicator "Live" |
| **6.4 Monitor Iterations** | Watch Iterations tab | Iteration count increases, progress updates |
| **6.5 Pause/Resume** | Click "Pause" → Click "Resume" | Status transitions correctly |

---

## Phase 7: Contexts/Memory (`/app/ai/contexts`)

| Test | Steps | Expected |
|------|-------|----------|
| **7.1 Create Context** | Click "Create New" tab → Name: "Test Memory" → Type: agent_memory → Save | Context created, detail view |
| **7.2 Add Factual Entry** | Click "Add Entry" → Key: "user_name" → Type: factual → Value: {"name": "Test"} → Save | Entry in list |
| **7.3 Add Experiential Entry** | Add entry → Type: experiential → Content about past interaction | Entry with importance score |
| **7.4 Search Entries** | Click "Search" tab → Query: "name" | Relevant entries with scores |
| **7.5 Archive Context** | Click archive icon on context | Status changes to Archived |

---

## Phase 8: A2A Tasks (`/app/ai/a2a-tasks`)

| Test | Steps | Expected |
|------|-------|----------|
| **8.1 View Tasks** | Navigate to page | Task list (may be empty initially) |
| **8.2 Task Detail** | Click any task row (if exists) | TaskDetail with event stream |
| **8.3 Event Stream** | For active task, observe events | Real-time event flow |

---

## Phase 9: Agent Cards (`/app/ai/agent-cards`)

| Test | Steps | Expected |
|------|-------|----------|
| **9.1 Create Card** | Click "Create Agent Card" → Fill agent info, capabilities → Save | Card in list |
| **9.2 View Card** | Click card row | Detail view with JSON, capabilities |
| **9.3 Edit Capabilities** | Edit card → Add/remove capabilities → Save | CapabilityBadges updated |

---

## Phase 10: Monitoring (`/app/ai/monitoring`)

| Test | Steps | Expected |
|------|-------|----------|
| **10.1 Dashboard** | Navigate to page | Overview cards, status indicators |
| **10.2 Providers Tab** | Click "Providers" tab | Provider health grid with status colors |
| **10.3 Agents Tab** | Click "Agents" tab | Agent performance metrics |
| **10.4 Alerts Tab** | Click "Alerts" tab | Alert list (badge shows count) |
| **10.5 Real-time Toggle** | Enable real-time updates | Live data refresh without manual action |

---

## Phase 11: Analytics (`/app/ai/analytics`)

| Test | Steps | Expected |
|------|-------|----------|
| **11.1 View Dashboard** | Navigate to page | Charts, metrics cards |
| **11.2 Time Range** | Select different time ranges (24h, 7d, 30d) | Data updates for period |

---

## Phase 12: Governance (`/app/ai/governance`)

| Test | Steps | Expected |
|------|-------|----------|
| **12.1 Summary View** | Navigate to page | Stats cards: policies, violations, approvals |
| **12.2 Policies Tab** | Click "Policies" | Policy list with enforcement levels |
| **12.3 Approvals Tab** | Click "Approvals" | Pending approvals with action buttons |

---

## Phase 13: Sandbox (`/app/ai/sandbox`)

| Test | Steps | Expected |
|------|-------|----------|
| **13.1 Create Sandbox** | Click "Create Sandbox" | New sandbox card, auto-selected |
| **13.2 Test Scenarios** | Click "Test Scenarios" tab → Create scenario | Scenario in list |
| **13.3 Run Tests** | Click "Run Tests" | Test execution with progress |

---

## Phase 14: MCP Browser (`/app/ai/mcp`)

| Test | Steps | Expected |
|------|-------|----------|
| **14.1 View Servers** | Navigate to page | Server cards with status |
| **14.2 Add Server** | Click "Add Server" → Configure → Save | New server card |
| **14.3 Connect** | Click "Connect" on server | Status → Connected, tools loaded |
| **14.4 Explore Tools** | Expand server → Click tool → Test | Tool execution result |

---

## Phase 15: WebSocket Real-Time Testing

| Test | Setup | Action | Expected |
|------|-------|--------|----------|
| **15.1 Agent Execution** | Open agents page in 2 tabs | Execute agent in Tab A | Tab B updates without refresh |
| **15.2 Conversation** | Open conversation in 2 tabs | Send message in Tab A | Message appears in Tab B |
| **15.3 Monitoring** | Open monitoring page | Trigger AI activity elsewhere | Dashboard updates live |

---

## Phase 16: Permission Testing

| Test | User Config | Expected |
|------|-------------|----------|
| **16.1 No Create** | Remove `ai.agents.create` | "Create Agent" button hidden |
| **16.2 No Execute** | Remove `ai.agents.execute` | "Execute" button hidden |
| **16.3 No Delete** | Remove `ai.workflows.delete` | Delete icon hidden |

---

## Phase 17: Message Management Features (`/app/ai/conversations`)

| Test | Steps | Expected |
|------|-------|----------|
| **17.1 Rate Message - Thumbs Up** | Open conversation → Click thumbs up on AI message | Notification "Feedback Recorded", icon highlighted |
| **17.2 Rate Message - Thumbs Down** | Click thumbs down on AI message | Notification, icon highlighted |
| **17.3 Copy Message Content** | Click copy icon on message | Notification "Copied", content in clipboard |
| **17.4 Regenerate AI Response** | Click "..." menu → "Regenerate" | Spinner shown, new response replaces old |
| **17.5 View Message Metadata** | Expand AI message details | Token count, response time, model displayed |

---

## Phase 18: Advanced Workflow Validation (`/app/ai/workflows/:id`)

| Test | Steps | Expected |
|------|-------|----------|
| **18.1 View Workflow Health Score** | Open workflow → Validation section | Health score (0-100) with grade and color |
| **18.2 Validation Rules Display** | Create workflow with issues → View validation | ValidationRuleCard shows severity, category |
| **18.3 Auto-Fixable Issues** | View auto-fixable issues | "Auto-fixable" badge, selection checkbox |
| **18.4 Navigate to Node** | Click "Go to node" on issue | Canvas scrolls to problematic node |
| **18.5 Validation Suggestions** | View warnings | Suggestion with lightbulb icon |

---

## Phase 19: Circuit Breaker Monitoring (`/app/ai/monitoring/workflows`)

| Test | Steps | Expected |
|------|-------|----------|
| **19.1 View Circuit Breaker States** | Navigate to circuit breaker section | Cards with state, success rate, response time |
| **19.2 Closed State Display** | View healthy breaker | Green "Healthy" badge, CheckCircle2 icon |
| **19.3 Open State Display** | Trigger failures | Red "Failed" badge, countdown shown |
| **19.4 Half-Open State Display** | Wait for recovery attempt | Yellow "Testing" badge, progress bar |
| **19.5 Reset Circuit Breaker** | Click "Reset" on open breaker | Transitions to closed, notification |

---

## Phase 20: Context Import/Export (`/app/ai/contexts/:id`)

| Test | Steps | Expected |
|------|-------|----------|
| **20.1 Export as JSON** | Import/Export → Export → JSON | Download link, file with entries |
| **20.2 Export as CSV** | Export → CSV | CSV file downloaded |
| **20.3 Import from JSON** | Import → Upload file | Progress shown, success count |
| **20.4 Import with Duplicates** | Import file with existing keys | Skipped count shown |
| **20.5 Import Error Handling** | Import malformed file | Error count, messages listed |

---

## Phase 21: Publisher/Marketplace (`/app/ai/agent-marketplace`)

| Test | Steps | Expected |
|------|-------|----------|
| **21.1 Create Publisher Profile** | "Become a Publisher" → Fill form | Profile created, dashboard accessible |
| **21.2 View Publisher Dashboard** | Access dashboard | Stats: templates, installs, earnings |
| **21.3 View Earnings Chart** | Earnings tab | Revenue chart displayed |
| **21.4 View Template Performance** | Templates tab | Downloads, ratings, revenue |
| **21.5 Request Payout** | Payouts tab → Request | Transaction logged |

---

## Phase 22: Container Management (`/app/devops/containers`)

| Test | Steps | Expected |
|------|-------|----------|
| **22.1 View Container List** | Executions tab | Containers with status, duration |
| **22.2 Filter by Status** | Select "Running" filter | Only running containers shown |
| **22.3 View Quota Display** | Quotas tab | CPU, memory limits, usage bars |
| **22.4 View Template List** | Templates tab | Available templates with specs |
| **22.5 Cancel Running Container** | Click Cancel | Status → "Cancelled" |

---

## Phase 23: Analytics Insights (`/app/ai/analytics/system`)

| Test | Steps | Expected |
|------|-------|----------|
| **23.1 View Insights Section** | Navigate to analytics | Insights with severity icons |
| **23.2 Insight Details** | View entry | Title, description, impact |
| **23.3 View Recommendations** | Scroll to Recommendations | Actionable suggestions |
| **23.4 Recommendation Priority** | View entries | Priority sorted |
| **23.5 Optimization Badge** | Cost analytics section | Savings potential badge |

---

## Phase 24: MCP OAuth Flow (`/app/ai/mcp`)

| Test | Steps | Expected |
|------|-------|----------|
| **24.1 Configure OAuth Server** | Edit server → OAuth 2.1 | Form validates required fields |
| **24.2 Initiate OAuth** | "Connect with OAuth" | Authorization popup opens |
| **24.3 View Connected Status** | After connection | "Connected" badge, token expiry |
| **24.4 Refresh Token** | Click "Refresh Token" | New expiry, notification |
| **24.5 Disconnect OAuth** | Click "Disconnect" | Status → "Not connected" |

---

## Phase 25: Prompt Templates (`/app/ai/prompts`)

| Test | Steps | Expected |
|------|-------|----------|
| **25.1 Create Template** | "Create Template" → Fill form | Template in list, usage count 0 |
| **25.2 Use Liquid Variables** | Add `{{ variable }}` syntax | Variables detected in preview |
| **25.3 Preview with Variables** | Fill values → "Render" | Variables replaced |
| **25.4 Duplicate Template** | Menu → "Duplicate" | New template with "(Copy)" |
| **25.5 Filter by Category** | Click category tabs | Filtered list |

---

## Phase 26: WebSocket Edge Cases

| Test | Steps | Expected |
|------|-------|----------|
| **26.1 Connection Lost** | Disable network | Warning indicator, "Connection lost" |
| **26.2 Auto-Reconnection** | Re-enable network | "Reconnecting..." then connected |
| **26.3 Subscription Recovery** | Reconnect on conversation page | Messages continue flowing |
| **26.4 Message During Disconnect** | Send while disconnected | Error or queued indicator |
| **26.5 Streaming Interruption** | Disconnect during AI generation | Error state, retry option |

---

## Critical Files

| Area | File |
|------|------|
| Providers | `frontend/src/features/ai/providers/components/AiProvidersPage.tsx` |
| Agents | `frontend/src/features/ai/agents/AiAgentDashboard.tsx` |
| Conversations | `frontend/src/pages/app/ai/AIConversationsPage.tsx` |
| Workflows | `frontend/src/pages/app/ai/WorkflowsPage.tsx` |
| Teams | `frontend/src/pages/app/ai/AgentTeamsPage.tsx` |
| Ralph Loops | `frontend/src/features/ai/ralph-loops/pages/RalphLoopsPage.tsx` |
| Contexts | `frontend/src/pages/app/ai/ContextsPage.tsx` |
| Monitoring | `frontend/src/pages/app/ai/AIMonitoringPage.tsx` |
| Memory API | `frontend/src/shared/services/ai/MemoryApiService.ts` |
| Message Actions | `frontend/src/features/ai/conversations/components/MessageActions.tsx` |
| Workflow Validation | `frontend/src/features/ai/workflows/components/validation/ValidationPanel.tsx` |
| Circuit Breaker | `frontend/src/features/ai/monitoring/components/CircuitBreakerCard.tsx` |
| Context Import/Export | `frontend/src/features/ai/contexts/components/ImportExportPanel.tsx` |
| Publisher Dashboard | `frontend/src/features/ai/marketplace/components/PublisherDashboard.tsx` |
| Container Management | `frontend/src/features/devops/containers/components/ContainerList.tsx` |
| Analytics Insights | `frontend/src/features/ai/analytics/components/InsightsPanel.tsx` |
| MCP OAuth | `frontend/src/features/ai/mcp/components/OAuthConfigForm.tsx` |
| Prompt Templates | `frontend/src/features/ai/prompts/components/PromptTemplateEditor.tsx` |
| WebSocket Hook | `frontend/src/shared/hooks/useWebSocket.ts` |

---

## Verification Checklist

### Pre-Test
- [ ] `sudo scripts/systemd/powernode-installer.sh status` shows all services running
- [ ] `ollama serve` running with `llama3:8b` model
- [ ] Logged in with full AI permissions

### Critical Path (Must Pass)
- [ ] Phase 1.3 - Remote Ollama provider connection successful
- [ ] Phase 2.2 - Agent executes with real AI response
- [ ] Phase 3.3 - Conversation maintains context
- [ ] Phase 4.3 - Workflow executes end-to-end
- [ ] Phase 7.2-7.4 - Memory CRUD and search work
- [ ] Phase 17.3 - Message copy functionality works
- [ ] Phase 18.1 - Workflow validation displays health score
- [ ] Phase 19.1 - Circuit breaker states visible
- [ ] Phase 20.1 - Context export produces valid file
- [ ] Phase 26.2 - WebSocket auto-reconnection works

### Data Persistence
After each create/update:
- [ ] Page refresh - data persists
- [ ] Logout/login - data persists

### WebSocket
- [ ] Connection indicator shows "Connected" (green)
- [ ] Real-time updates work without manual refresh

---

## Execution Approach

1. **Execute phases sequentially** (dependencies exist)
2. **Document any failures** with screenshots
3. **Test both happy path and edge cases**
4. **Verify WebSocket updates throughout**
5. **Check permission gating on each feature**
