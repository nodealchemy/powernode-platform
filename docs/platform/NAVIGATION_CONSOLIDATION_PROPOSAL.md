# Navigation Consolidation Proposal

## Executive Summary

The current navigation has four related categories (AI, AI Pipelines, CI/CD, Integrations) that overlap conceptually and create user confusion. This proposal consolidates them into a more intuitive structure based on **user intent** rather than implementation details.

---

## Current State Analysis

### Current Navigation Structure

| Section | Items | Purpose |
|---------|-------|---------|
| **AI** | 11 items | AI capabilities (agents, conversations, workflows, providers) |
| **AI Pipelines** | 6 items | AI-powered CI/CD automation |
| **CI/CD** | 6 items | Git-native CI/CD pipelines |
| **Integrations** | 2 items | Third-party integration management |
| **System** | 7 items | Includes Git Providers |

### Problems Identified

#### 1. Terminology Confusion: "Workflows" vs "Pipelines"
- **AI Workflows**: Visual flow builder with nodes/edges for complex AI orchestration
- **AI Pipelines**: Sequential step execution (CI/CD-style)
- **Git Pipelines**: Traditional git-triggered CI/CD

Users cannot distinguish between these without deep product knowledge.

#### 2. Duplicate Concepts
| Concept | AI Pipelines | CI/CD |
|---------|--------------|-------|
| Runners | ✅ Runners page | ✅ Runners page |
| Execution History | ✅ Runs page | ✅ (in Dashboard) |
| Schedules | ✅ (in Settings) | ✅ Schedules page |
| Triggers | Webhook/Schedule | Webhook/Schedule |

#### 3. Scattered Provider Configuration
- **AI Providers** (OpenAI, Anthropic) → AI section
- **Git Providers** (GitHub, GitLab, Gitea) → System section
- **Integration Templates** → Integrations section

Users must navigate to three different places to configure external connections.

#### 4. Section Size Imbalance
- AI section has 11 items (overwhelming)
- Integrations has only 2 items (too sparse)

---

## Proposed Structure

### Option A: Intent-Based Navigation (Recommended)

Organized around **what users want to accomplish**:

```
┌─────────────────────────────────────────────────────────────────┐
│  AUTOMATION                                                      │
│  "I want to automate tasks"                                      │
│  ├── Dashboard        - Unified automation overview              │
│  ├── Pipelines        - All pipelines (filterable by type)      │
│  ├── Runs             - All execution history                   │
│  ├── Triggers         - Webhooks, schedules, approvals          │
│  ├── Runners          - Self-hosted execution agents            │
│  └── Templates        - Pipeline & prompt templates             │
├─────────────────────────────────────────────────────────────────┤
│  AI                                                              │
│  "I want to use AI capabilities"                                 │
│  ├── Overview         - AI system dashboard                     │
│  ├── Agents           - AI personas and capabilities            │
│  ├── Conversations    - Chat with AI                            │
│  ├── Workflows        - Visual AI orchestration builder         │
│  ├── Knowledge        - Context & knowledge base (merged)       │
│  └── Analytics        - AI usage and performance                │
├─────────────────────────────────────────────────────────────────┤
│  CONNECTIONS                                                     │
│  "I want to connect external services"                           │
│  ├── Overview         - All connected services summary          │
│  ├── AI Services      - OpenAI, Anthropic, etc.                 │
│  ├── Git Services     - GitHub, GitLab, Gitea                   │
│  ├── Integrations     - Other third-party services              │
│  └── Credentials      - API keys and authentication             │
└─────────────────────────────────────────────────────────────────┘
```

#### Benefits
- **Clear user intent**: Each section answers "what do I want to do?"
- **Reduced duplication**: Single Runners page, single Runs page
- **Unified provider management**: All external connections in one place
- **Scalable**: Easy to add new automation or AI features

#### Detailed Item Mapping

| New Location | Old Location(s) | Notes |
|--------------|-----------------|-------|
| **Automation** | | |
| → Dashboard | AI Pipelines Dashboard + CI/CD Dashboard | Unified view with filters |
| → Pipelines | AI Pipelines + Git Pipelines | Type filter: AI-powered, Git-native |
| → Runs | AI Pipelines Runs + implicit CI/CD runs | Unified execution history |
| → Triggers | CI/CD Webhooks + Schedules + Approvals | Consolidated trigger management |
| → Runners | AI Pipelines Runners + CI/CD Runners | Single runners page |
| → Templates | AI Pipelines Prompts | Prompt & pipeline templates |
| **AI** | | |
| → Overview | AI Overview | No change |
| → Agents | AI Agents | No change |
| → Conversations | AI Conversations | No change |
| → Workflows | AI Workflows | Renamed from "Workflows" for clarity |
| → Knowledge | AI Knowledge Base + AI Contexts | Merged |
| → Analytics | AI Analytics + AI Monitoring | Merged |
| **Connections** | | |
| → Overview | New | Summary of all connections |
| → AI Services | AI Providers | Moved |
| → Git Services | System > Git Providers | Moved |
| → Integrations | Integrations > Installed | Moved |
| → Credentials | New (consolidates credentials) | From scattered locations |

---

### Option B: Simplified Two-Tier

If Option A feels too aggressive, here's a more conservative approach:

```
┌─────────────────────────────────────────────────────────────────┐
│  AI & AUTOMATION                                                 │
│  ├── AI Hub           - AI overview, agents, conversations      │
│  ├── Workflows        - Visual AI flow builder                  │
│  ├── Pipelines        - CI/CD automation (all types)           │
│  ├── Runs             - Execution history                       │
│  └── Knowledge        - Context and knowledge base              │
├─────────────────────────────────────────────────────────────────┤
│  INTEGRATIONS                                                    │
│  ├── Providers        - AI, Git, and other providers           │
│  ├── Runners          - Self-hosted execution agents           │
│  ├── Webhooks         - Incoming webhook management            │
│  └── Connected Apps   - Third-party integrations               │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation Approach

### Phase 1: Backend Unification (No UI Changes)
1. Ensure pipeline models can be filtered by type
2. Create unified runners abstraction
3. Add provider type categorization

### Phase 2: Navigation Restructure
1. Create new "Automation" section
2. Create new "Connections" section
3. Consolidate AI section
4. Update routes and permissions

### Phase 3: Page Consolidation
1. Create unified Pipelines page with type filter
2. Create unified Runners page
3. Create unified Connections overview
4. Merge Knowledge Base + Contexts

### Phase 4: Cleanup
1. Remove duplicate pages
2. Update documentation
3. Add redirects for old URLs

---

## Data Model Considerations

### Pipeline Unification

Both pipeline systems share similar concepts:

| Concept | CiCd::Pipeline | AiWorkflow (when used as pipeline) |
|---------|----------------|-------------------------------------|
| Definition | steps, triggers | nodes, edges, triggers |
| Execution | CiCd::PipelineRun | AiWorkflowRun |
| Schedule | CiCd::Schedule | AiWorkflowSchedule |

Consider adding a `pipeline_type` enum:
- `ai_powered` - Uses Claude/LLM for execution
- `git_native` - Traditional CI/CD from git events
- `hybrid` - Both AI and traditional steps

### Provider Unification

Create a unified `Provider` interface:

```ruby
# Conceptual - providers share:
# - name, type, credentials, status, health_check
#
# Types:
# - ai_service (openai, anthropic, etc.)
# - git_service (github, gitlab, gitea)
# - integration (slack, jira, etc.)
```

---

## Terminology Recommendations

### Clarify "Workflow" vs "Pipeline"

| Term | Definition | UI Label |
|------|------------|----------|
| **Workflow** | Visual DAG of AI nodes with complex branching | "AI Workflows" or "Flow Builder" |
| **Pipeline** | Sequential automation steps (CI/CD style) | "Pipelines" |

### User-Friendly Names

| Current | Proposed | Reasoning |
|---------|----------|-----------|
| AI Providers | AI Services | "Services" implies connection |
| Git Providers | Git Services | Consistency |
| MCP Browser | (Remove from nav) | Technical detail, move to AI Workflows as tool |
| Contexts | (Merge into Knowledge) | Reduce cognitive load |

---

## Permission Mapping

### New Permission Structure

```
automation.read          # View pipelines, runs
automation.manage        # Create/edit pipelines
automation.execute       # Trigger manual runs
automation.runners.read  # View runners
automation.runners.manage # Configure runners

ai.read                  # View AI features
ai.agents.manage         # Create/edit agents
ai.workflows.manage      # Create/edit workflows
ai.conversations.use     # Use chat

connections.read         # View connected services
connections.manage       # Configure connections
connections.credentials  # Manage credentials
```

---

## Migration Strategy

### URL Redirects

| Old URL | New URL |
|---------|---------|
| `/app/ai-pipelines` | `/app/automation` |
| `/app/ai-pipelines/pipelines` | `/app/automation/pipelines?type=ai` |
| `/app/ci-cd` | `/app/automation` |
| `/app/ci-cd/repositories` | `/app/automation/pipelines?type=git` |
| `/app/ci-cd/runners` | `/app/automation/runners` |
| `/app/ai-pipelines/runners` | `/app/automation/runners` |
| `/app/ai/providers` | `/app/connections/ai` |
| `/app/system/git-providers` | `/app/connections/git` |
| `/app/integrations` | `/app/connections/integrations` |

### Feature Flags

Implement progressive rollout:
1. `new_navigation_automation` - Shows consolidated Automation section
2. `new_navigation_connections` - Shows consolidated Connections section
3. `new_navigation_ai` - Shows streamlined AI section

---

## Summary

### Recommended Changes

1. **Merge AI Pipelines + CI/CD → Automation**
   - Single dashboard, single runs page, single runners page
   - Filter by pipeline type (AI-powered, Git-native)

2. **Create Connections section**
   - AI Services, Git Services, Integrations
   - Unified credential management

3. **Streamline AI section**
   - Remove MCP Browser from nav (technical detail)
   - Merge Knowledge Base + Contexts
   - Merge Analytics + Monitoring

4. **Remove Integrations as standalone section**
   - Move to Connections

### Items Removed from Navigation

| Item | Action |
|------|--------|
| MCP Browser | Move to AI Workflows as a tool/panel |
| Contexts (standalone) | Merge into Knowledge |
| AI Monitoring (standalone) | Merge into Analytics |
| AI Pipelines Settings | Move to Automation settings |
| CI/CD Dashboard | Merge into Automation Dashboard |

### Net Result

| Before | After |
|--------|-------|
| 4 sections, 25+ items | 3 sections, ~17 items |
| 2 Runners pages | 1 Runners page |
| 2 Pipeline sections | 1 Pipelines page with filter |
| 3 provider locations | 1 Connections section |
