# AI Orchestration Quick Start

**Quick reference guide for the Missions / Ralph Loops / Agents architecture**

**Version**: 4.0 | **Last Updated**: April 2026

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Component Import Paths](#component-import-paths)
3. [Custom Hooks](#custom-hooks)
4. [WebSocket Events](#websocket-events)
5. [Common Patterns](#common-patterns)
6. [Troubleshooting](#troubleshooting)
7. [Performance Tips](#performance-tips)
8. [Quick Reference Tables](#quick-reference-tables)

---

## Getting Started

### 1. Install Dependencies

```bash
cd frontend
npm install
```

### 2. Import Services

```typescript
// Consolidated imports
import {
  agentsApi, teamsApi, missionsApi,
  providersApi, monitoringApi, analyticsApi
} from '@/shared/services/ai';

// Or use the convenience object
import { aiApi } from '@/shared/services/ai';
```

### 3. Create and Start a Mission

```typescript
// Create a mission (inherits from a repository + objective)
const mission = await missionsApi.createMission({
  name: 'Add daily summaries feature',
  objective: 'Implement admin UI and scheduled job for daily operational summaries',
  mission_type: 'development',
  repository_id: repoId,
});

// Start it — dispatches the first phase job (analyzing)
await missionsApi.startMission(mission.id);

// Monitor progress via MissionChannel
useWebSocket({
  channel: 'MissionChannel',
  params: { type: 'mission', id: mission.id },
  onMessage: (msg) => {
    // msg.event: status_changed | phase_changed | approval_required | error
    updateMissionState(msg.payload);
  }
});
```

### 4. Handle an Approval Gate

```typescript
// When MissionChannel emits `approval_required`
await missionsApi.approveMission(mission.id, {
  gate: 'prd_review',
  feedback: 'Looks good'
});

// Or reject to route back to earlier phase
await missionsApi.rejectMission(mission.id, {
  gate: 'code_review',
  feedback: 'Needs more tests'
});
```

### 5. Check Permissions

```typescript
// Always use permission-based access control
const canManage = currentUser?.permissions?.includes('ai.missions.manage');

// ❌ Never use role-based checks
// const canManage = currentUser?.roles?.includes('admin');
```

---

## Component Import Paths

### Missions

```typescript
import { MissionsPage } from '@/features/missions/pages/MissionsPage';
import { MissionDetailModal } from '@/features/missions/components/MissionDetailModal';
import { MissionsIndexTable } from '@/features/missions/components/MissionsIndexTable';
import { useMissions } from '@/features/missions/hooks/useMissions';
import { useMissionModal } from '@/shared/hooks/useMissionModal';
```

### Autonomy

```typescript
import { AutonomyDashboardPage } from '@/features/ai/autonomy/pages/AutonomyDashboardPage';
import { KillSwitchPanel } from '@/features/ai/autonomy/components/KillSwitchPanel';
import { GoalsPanel } from '@/features/ai/autonomy/components/GoalsPanel';
import { ProposalsPanel } from '@/features/ai/autonomy/components/ProposalsPanel';
import { InterventionPoliciesPanel } from '@/features/ai/autonomy/components/InterventionPoliciesPanel';
import { TrustScoreCard } from '@/features/ai/autonomy/components/TrustScoreCard';
import { BudgetRegimeIndicator } from '@/features/ai/autonomy/components/BudgetRegimeIndicator';
import { CircuitBreakerStatusPanel } from '@/features/ai/autonomy/components/CircuitBreakerStatusPanel';
import { ShadowModeResultsPanel } from '@/features/ai/autonomy/components/ShadowModeResultsPanel';
```

### Compound Learning

```typescript
import { LearningsList } from '@/features/ai/learning/components/LearningsList';
import { CompoundMetricsDashboard } from '@/features/ai/learning/components/CompoundMetricsDashboard';
import { compoundLearningApi } from '@/features/ai/learning/services/compoundLearningApi';
```

### Content Linking

```typescript
import { BacklinksPanel } from '@/features/content/pages/components/BacklinksPanel';
import { DailySummariesPanel } from '@/features/content/pages/components/DailySummariesPanel';
```

### Monitoring

```typescript
import { CircuitBreakerStatus } from '@/features/ai/monitoring/components/CircuitBreakerStatus';
```

---

## Custom Hooks

### useMissions

```typescript
// frontend/src/features/missions/hooks/useMissions.ts
const {
  missions,
  isLoading,
  error,
  refetch,
  createMission,
  startMission,
  approveGate,
  rejectGate,
} = useMissions({
  statusFilter: 'active',
  typeFilter: 'development',
});
```

### useMissionModal

```typescript
// frontend/src/shared/hooks/useMissionModal.ts
const { openMissionModal, closeMissionModal, missionId } = useMissionModal();

// From any component
openMissionModal(mission.id);
```

### Generic useWebSocket

```typescript
// frontend/src/shared/hooks/useWebSocket.ts
const { isConnected, error, subscribe } = useWebSocket({
  channel: 'MissionChannel',
  params: { type: 'mission', id: missionId },
  onMessage: handleMessage,
});
```

### compoundLearningApi

```typescript
// frontend/src/features/ai/learning/services/compoundLearningApi.ts
// Pagination + filtering + sorting handled by the API client.
const response = await compoundLearningApi.list({
  category: 'pattern',
  status: 'verified',
  page: 1,
  per_page: 25,
  sort: 'created_at:desc',
});
```

---

## WebSocket Events

### Subscribe to Mission Events

```typescript
useWebSocket({
  channel: 'MissionChannel',
  params: { type: 'mission', id: missionId },
  onMessage: handleMessage
});
```

### Subscribe to Orchestration Events (Unified)

```typescript
useWebSocket({
  channel: 'AiOrchestrationChannel',
  params: { type: 'account', id: accountId },
  onMessage: handleMessage
});
```

### Event Types

**Mission lifecycle** (on `MissionChannel`):
- `status_changed`
- `phase_changed`
- `approval_required`
- `approval_resolved`
- `error`

**Agent execution** (on `AiOrchestrationChannel` or `AiAgentExecutionChannel`):
- `agent.created` / `agent.updated` / `agent.deleted`
- `agent.execution.started`
- `agent.execution.completed`
- `agent.execution.failed`

**Ralph Loop** (on `AiOrchestrationChannel`):
- `ralph_loop.started`
- `ralph_loop.progress`
- `ralph_loop.iteration_completed`
- `ralph_loop.task_status_changed`
- `ralph_loop.learning_added`
- `ralph_loop.completed` / `failed` / `paused` / `cancelled`

**Circuit Breaker**:
- `circuit_breaker.state_changed`
- `circuit_breaker.opened` / `closed` / `half_opened`
- `circuit_breaker.failure` / `success` / `reset`

**Monitoring / System**:
- `monitoring.alert.triggered`
- `monitoring.metrics.updated`
- `system.health.changed`

**Worktree session** (Code Factory / Ralph):
- `worktree_session.status_changed` / `provisioning` / `active` / `merging` / `completed` / `failed` / `cancelled` / `conflicts_detected`
- `worktree.created` / `ready` / `task_started` / `completed` / `failed`
- `merge.started` / `completed` / `conflict` / `resolved` / `failed`

---

## Common Patterns

### Permission Check Pattern

```typescript
const { currentUser } = useAuth();
const canManage = currentUser?.permissions?.includes('ai.missions.manage');

if (!canManage) {
  return <AccessDenied />;
}

return <MissionsPage />;
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

### Global Modal Pattern (Missions/Teams/Agents)

The UI uses full-width index pages with a global detail modal. Deep links (`/missions/:id`) open the modal over any page.

```typescript
import { useMissionModal } from '@/shared/hooks/useMissionModal';

const { openMissionModal } = useMissionModal();

// From any component
openMissionModal(missionId);
```

---

## Troubleshooting

### WebSocket Not Connecting

**Symptoms**: Components not receiving real-time updates

**Solutions**:
1. Check WebSocket URL in environment variables
2. Verify user has required permissions (`ai.missions.read`, `ai_orchestration.read`, etc.)
3. Check subscription params are correct (channel name, type, id)

```typescript
const { isConnected, error } = useWebSocket({
  channel: 'MissionChannel',
  params: { type: 'mission', id: missionId },
  onMessage: (msg) => console.log('Received:', msg)
});
console.log('Connected:', isConnected, 'Error:', error);
```

### API Calls Failing

**Symptoms**: API service methods returning errors

**Solutions**:
1. Check authentication token is valid
2. Verify API endpoint exists (`rails routes | grep <resource>`)
3. Check request/response format
4. Inspect Rails logs: `journalctl -u powernode-backend@default -f`

### Permission Denied Errors

**Symptoms**: User can't access features

**Solutions**:
1. Verify user has required permissions in database
2. Check permission strings match exactly (spelling and dots)
3. Ensure `currentUser.permissions` array is populated (login response)

```typescript
console.log('Permissions:', currentUser?.permissions);
console.log('Has permission:',
  currentUser?.permissions?.includes('ai.missions.manage'));
```

### Mission Stuck in a Phase

**Symptoms**: Mission doesn't advance past a specific phase

**Solutions**:
1. Check Sidekiq worker is running: `systemctl status powernode-worker@default`
2. Inspect mission phase execution log via `get_mission_status` MCP tool
3. Use `POST /api/v1/ai/missions/:id/retry_phase` to re-dispatch current phase job
4. Check worker logs for errors in `AiMission<Phase>Job`

```bash
# Check Sidekiq
systemctl status powernode-worker@default

# Tail worker logs
journalctl -u powernode-worker@default -f
```

### Circuit Breakers Always Open

**Symptoms**: Provider circuit breakers immediately open

**Solutions**:
1. Check failure threshold configuration
2. Verify success threshold for recovery
3. Check underlying provider is healthy via `/api/v1/internal/ai/providers/:id/health`

```ruby
# Reset from Rails console (admin only)
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

### Debounce User Input

```typescript
const debouncedSearch = useMemo(
  () => debounce(setQuery, 300),
  []
);
```

### Lazy Load Components

```typescript
const MissionDetailModal = lazy(() =>
  import('@/features/missions/components/MissionDetailModal')
);

<Suspense fallback={<Loading />}>
  <MissionDetailModal {...props} />
</Suspense>
```

### Limit WebSocket Updates

```typescript
const handleMessage = useCallback((message) => {
  setData(prev => {
    if (JSON.stringify(prev) === JSON.stringify(message.payload)) {
      return prev; // No update needed — avoid React re-render
    }
    return message.payload;
  });
}, []);
```

---

## Quick Reference Tables

### Permission Requirements

| Feature | Read | Manage |
|---------|------|--------|
| Missions | `ai.missions.read` | `ai.missions.manage` |
| Agents | `ai.agents.read` | `ai.agents.manage` |
| Teams | `ai.teams.read` | `ai.teams.manage` |
| Ralph Loops | `ai.ralph.read` | `ai.ralph.manage` |
| Code Factory | `ai.code_factory.read` | `ai.code_factory.manage` |
| Providers | `ai.providers.manage` | `ai.providers.manage` |
| Autonomy | `ai.autonomy.read` | `ai.autonomy.manage` |
| Data Sources | `ai.data_sources.read` | `ai.data_sources.manage` |
| Cost Dashboard | `ai.analytics.read` | N/A |
| Daily Summaries | `admin.access` | `admin.access` |
| Orchestration Streams | `ai_orchestration.read` | `system.admin` |

### Development Commands

```bash
# Start services
sudo systemctl start powernode.target

# Run backend specs
cd server && bundle exec rspec

# Run frontend tests (CI=true is required)
cd frontend && CI=true npm test

# Type check
cd frontend && npx tsc --noEmit

# Database migrations
cd server && rails db:migrate

# Check AI routes
cd server && rails routes | grep ai
```

### Key Files

| Purpose | Path |
|---------|------|
| Agent Orchestration | `server/app/services/ai_agent_orchestration_service.rb` |
| Missions Orchestrator | `server/app/services/ai/missions/orchestrator_service.rb` |
| Ralph Loop Execution | `server/app/services/ai/ralph/execution_service.rb` |
| Missions Controller | `server/app/controllers/api/v1/ai/missions_controller.rb` |
| Ralph Controller | `server/app/controllers/api/v1/ai/ralph_loops_controller.rb` |
| Frontend AI Services | `frontend/src/shared/services/ai/index.ts` |
| Mission Types | `frontend/src/shared/types/mission.ts` |
| Missions Page | `frontend/src/features/missions/pages/MissionsPage.tsx` |

---

**Document Status**: Complete
