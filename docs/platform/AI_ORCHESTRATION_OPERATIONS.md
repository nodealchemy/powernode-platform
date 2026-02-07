# AI Orchestration Operations Guide

**Testing, Monitoring, and Code Quality for AI Orchestration**

---

## Table of Contents

1. [Testing Strategy](#testing-strategy)
2. [Backend Testing (RSpec)](#backend-testing-rspec)
3. [Frontend Testing (Jest)](#frontend-testing-jest)
4. [Integration Testing](#integration-testing)
5. [E2E Testing (Cypress)](#e2e-testing-cypress)
6. [Monitoring & Alerting](#monitoring--alerting)
7. [Code Quality](#code-quality)
8. [Operational Procedures](#operational-procedures)

---

## Testing Strategy

### Testing Pyramid

```
        ┌──────────────┐
        │  E2E Tests   │  (10% - Workflow execution scenarios)
        │   Cypress    │
        ├──────────────┤
        │ Integration  │  (30% - API + DB + WebSocket)
        │    Tests     │
        ├──────────────┤
        │   Unit Tests │  (60% - Services, models, components)
        │ RSpec + Jest │
        └──────────────┘
```

### Coverage Targets

| Layer | Target | Focus |
|-------|--------|-------|
| Services | 85%+ | Core orchestration logic |
| Models | 90%+ | Critical business logic |
| Controllers | 80%+ | API endpoints |
| Jobs | 75%+ | Background processing |
| Frontend Components | 70%+ | User interactions |
| Frontend Services | 90%+ | API integration |

---

## Backend Testing (RSpec)

### Test Environment Setup

```bash
# Setup test database
cd server
RAILS_ENV=test bundle exec rails db:test:prepare

# Run all tests
bundle exec rspec

# Run specific file
bundle exec rspec spec/services/ai_agent_orchestration_service_spec.rb

# Run with coverage
COVERAGE=true bundle exec rspec
```

### Service Testing Pattern

```ruby
# spec/services/ai_agent_orchestration_service_spec.rb
require 'rails_helper'

RSpec.describe AiAgentOrchestrationService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:workflow) { create(:ai_workflow, account: account) }
  let(:service) { described_class.new(workflow, account: account, user: user) }

  describe '#execute_workflow' do
    let(:input_variables) { { input: 'test data' } }

    context 'when execution succeeds' do
      it 'creates a workflow run' do
        expect { service.execute_workflow(input_variables: input_variables) }
          .to change { AiWorkflowRun.count }.by(1)
      end

      it 'sets correct workflow run status' do
        run = service.execute_workflow(input_variables: input_variables)
        expect(run.status).to be_in(%w[completed running])
      end
    end

    context 'when execution fails' do
      before do
        allow_any_instance_of(Mcp::WorkflowOrchestrator)
          .to receive(:execute)
          .and_raise(StandardError, 'Execution failed')
      end

      it 'marks run as failed' do
        run = service.execute_workflow(input_variables: input_variables)
        expect(run.status).to eq('failed')
        expect(run.error_message).to eq('Execution failed')
      end
    end
  end
end
```

### Controller Testing Pattern

```ruby
# spec/controllers/api/v1/ai/workflows_controller_spec.rb
require 'rails_helper'

RSpec.describe Api::V1::Ai::WorkflowsController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.workflows.read']) }
  let(:workflow) { create(:ai_workflow, account: account) }

  before { sign_in(user) }

  describe 'GET #index' do
    it 'returns success' do
      get :index
      expect(response).to have_http_status(:success)
      expect(json_response['success']).to be_truthy
    end

    it 'filters by status' do
      create(:ai_workflow, account: account, status: 'published')
      create(:ai_workflow, account: account, status: 'draft')

      get :index, params: { status: 'published' }

      workflows = json_response['data']['workflows']
      expect(workflows.count).to eq(1)
    end
  end

  describe 'POST #execute' do
    before { user.update!(permissions: ['ai.workflows.execute']) }

    it 'executes workflow' do
      post :execute, params: { id: workflow.id, input_variables: {} }
      expect(response).to have_http_status(:success)
    end

    it 'requires execute permission' do
      user.update!(permissions: ['ai.workflows.read'])
      post :execute, params: { id: workflow.id }
      expect(response).to have_http_status(:forbidden)
    end
  end
end
```

### Model Testing Pattern

```ruby
# spec/models/ai_workflow_spec.rb
require 'rails_helper'

RSpec.describe AiWorkflow, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should have_many(:ai_workflow_nodes) }
    it { should have_many(:ai_workflow_runs) }
  end

  describe 'validations' do
    subject { create(:ai_workflow) }
    it { should validate_presence_of(:name) }
    it { should validate_inclusion_of(:status).in_array(%w[draft published archived]) }
  end

  describe '#publishable?' do
    let(:workflow) { create(:ai_workflow, :with_nodes) }

    it 'returns true for valid workflow' do
      expect(workflow.publishable?).to be_truthy
    end
  end
end
```

---

## Frontend Testing (Jest)

### Component Testing

```typescript
// __tests__/components/WorkflowBuilder.test.tsx
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { WorkflowBuilder } from '@/shared/components/workflow/WorkflowBuilder';
import { workflowsApi } from '@/shared/services/ai';

jest.mock('@/shared/services/ai');

describe('WorkflowBuilder', () => {
  const mockWorkflow = {
    id: 'workflow-123',
    name: 'Test Workflow',
    nodes: [{ id: 'node-1', type: 'start', position: { x: 0, y: 0 } }],
    edges: []
  };

  beforeEach(() => {
    (workflowsApi.getWorkflow as jest.Mock).mockResolvedValue(mockWorkflow);
  });

  it('renders workflow builder', async () => {
    render(<WorkflowBuilder workflowId="workflow-123" />);
    await waitFor(() => {
      expect(screen.getByText('Test Workflow')).toBeInTheDocument();
    });
  });

  it('saves workflow design', async () => {
    (workflowsApi.updateWorkflow as jest.Mock).mockResolvedValue({
      workflow: mockWorkflow
    });

    render(<WorkflowBuilder workflowId="workflow-123" />);
    const saveButton = await screen.findByText('Save');
    fireEvent.click(saveButton);

    await waitFor(() => {
      expect(workflowsApi.updateWorkflow).toHaveBeenCalled();
    });
  });
});
```

### API Service Testing

```typescript
// __tests__/services/workflowsApi.test.ts
import { workflowsApi } from '@/shared/services/ai';
import { apiClient } from '@/shared/services/apiClient';

jest.mock('@/shared/services/apiClient');

describe('workflowsApi', () => {
  describe('getWorkflows', () => {
    it('fetches workflows with filters', async () => {
      const mockResponse = {
        success: true,
        data: {
          workflows: [{ id: '1', name: 'Workflow 1' }],
          pagination: { total: 1, page: 1, per_page: 25 }
        }
      };

      (apiClient.get as jest.Mock).mockResolvedValue({ data: mockResponse });

      const result = await workflowsApi.getWorkflows({ status: 'published' });

      expect(result.items).toHaveLength(1);
      expect(apiClient.get).toHaveBeenCalledWith(
        '/api/v1/ai/workflows',
        { params: { status: 'published' } }
      );
    });
  });

  describe('executeWorkflow', () => {
    it('executes workflow and unwraps response', async () => {
      const mockResponse = {
        success: true,
        data: { workflow_run: { id: 'run-123', status: 'running' } }
      };

      (apiClient.post as jest.Mock).mockResolvedValue({ data: mockResponse });

      const run = await workflowsApi.executeWorkflow('workflow-123', {
        input_variables: { key: 'value' }
      });

      expect(run.id).toBe('run-123');
    });
  });
});
```

### Hook Testing

```typescript
// __tests__/hooks/useWorkflowExecution.test.ts
import { renderHook, waitFor, act } from '@testing-library/react';
import { useWorkflowExecution } from '@/shared/hooks/useWorkflowExecution';
import { workflowsApi } from '@/shared/services/ai';

jest.mock('@/shared/services/ai');

describe('useWorkflowExecution', () => {
  it('fetches workflow run status', async () => {
    const mockRun = { id: 'run-123', status: 'running', progress: 50 };
    (workflowsApi.getRun as jest.Mock).mockResolvedValue(mockRun);

    const { result } = renderHook(() =>
      useWorkflowExecution('workflow-123', 'run-123')
    );

    await waitFor(() => {
      expect(result.current.run).toEqual(mockRun);
      expect(result.current.status).toBe('running');
    });
  });
});
```

---

## Integration Testing

### Full Workflow Execution Test

```ruby
# spec/integration/workflow_execution_spec.rb
require 'rails_helper'

RSpec.describe 'Workflow Execution Integration', type: :integration do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, :openai, account: account) }
  let(:workflow) { create(:ai_workflow, :with_nodes, account: account) }

  it 'executes complete workflow successfully' do
    VCR.use_cassette('openai_generate_text') do
      service = AiAgentOrchestrationService.new(workflow, account: account, user: user)
      run = service.execute_workflow(input_variables: { prompt: 'Hello' })

      expect(run.status).to eq('completed')
      expect(run.ai_workflow_node_executions.completed.count).to eq(3)
    end
  end
end
```

### WebSocket Integration Test

```ruby
# spec/channels/ai_orchestration_channel_spec.rb
require 'rails_helper'

RSpec.describe AiOrchestrationChannel, type: :channel do
  let(:user) { create(:user) }

  before { stub_connection current_user: user }

  it 'subscribes to account stream' do
    subscribe(type: 'account', id: user.account_id)

    expect(subscription).to be_confirmed
    expect(subscription.streams).to include("ai_orchestration:account:#{user.account_id}")
  end

  it 'rejects unauthorized subscriptions' do
    other_account = create(:account)
    subscribe(type: 'account', id: other_account.id)
    expect(subscription).to be_rejected
  end
end
```

---

## E2E Testing (Cypress)

### Workflow Execution E2E

```typescript
// cypress/e2e/workflow-execution.cy.ts
describe('Workflow Execution', () => {
  beforeEach(() => {
    cy.login();
    cy.visit('/ai/workflows');
  });

  it('creates and executes workflow end-to-end', () => {
    // Create workflow
    cy.get('[data-testid="create-workflow-btn"]').click();
    cy.get('[data-testid="workflow-name-input"]').type('Test Workflow');
    cy.get('[data-testid="save-workflow-btn"]').click();

    // Add nodes
    cy.get('[data-testid="add-start-node"]').click();
    cy.get('[data-testid="add-ai-agent-node"]').click();
    cy.get('[data-testid="add-end-node"]').click();

    // Execute workflow
    cy.get('[data-testid="execute-workflow-btn"]').click();
    cy.get('[data-testid="execute-confirm-btn"]').click();

    // Verify completion
    cy.get('[data-testid="run-status"]', { timeout: 30000 })
      .should('contain', 'Completed');
  });

  it('handles execution errors gracefully', () => {
    cy.intercept('POST', '/api/v1/ai/workflows/*/execute', {
      statusCode: 500,
      body: { success: false, error: 'Execution failed' }
    }).as('executeWorkflow');

    cy.visit('/ai/workflows/workflow-123');
    cy.get('[data-testid="execute-workflow-btn"]').click();

    cy.wait('@executeWorkflow');
    cy.get('.error-message').should('contain', 'Execution failed');
  });
});
```

---

## Monitoring & Alerting

### Key Metrics to Track

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `ai_orchestration.api.response_time` | API response time | P95 > 500ms |
| `ai_orchestration.api.requests.500` | Server errors | > 5% error rate |
| `ai_orchestration.workflow.runs.failed` | Failed workflows | > 10% failure rate |
| `ai_orchestration.batch.active` | Active batches | > 100 concurrent |
| `ai_orchestration.circuit_breaker.open` | Open breakers | > 3 open |
| `sidekiq.queue.ai_workflows.size` | Queue depth | > 1000 jobs |
| `sidekiq.queue.ai_workflows.latency` | Queue wait time | > 60 seconds |

### Critical Alerts (P1)

**API Availability Alert**:
```yaml
- alert: AIOrchestrationAPIDown
  expr: |
    (sum(rate(ai_orchestration_api_requests_500[5m])) /
     sum(rate(ai_orchestration_api_requests_total[5m]))) > 0.05
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "AI Orchestration API has high error rate"
```

**Circuit Breakers Opening**:
```yaml
- alert: MultipleCircuitBreakersOpen
  expr: ai_orchestration_circuit_breaker_open > 3
  for: 5m
  labels:
    severity: high
  annotations:
    summary: "Multiple circuit breakers are open"
```

### Operations Dashboard

**Key Panels**:
1. **API Health**: Request rate, error rate, P95 response time
2. **Workflow Execution**: Active runs, success rate, average duration
3. **Infrastructure**: Database connections, Redis memory, Sidekiq workers
4. **Circuit Breakers**: Open breakers count, state distribution

### Incident Runbooks

**High API Error Rate**:
1. Check application logs for exceptions
2. Check database connection status
3. Check external service availability (AI providers)
4. Review recent deployments
5. Restart if needed: `sudo systemctl restart powernode-backend@default`

**Workflow Executions Stalled**:
1. Check Sidekiq worker status: `systemctl status powernode-worker@default`
2. Check queue depths in Redis
3. Review worker logs for errors
4. Restart workers: `sudo systemctl restart powernode-worker@default`

---

## Code Quality

### Quality Score: 7/10 (Good, needs cleanup)

### Positive Findings

- ✅ Zero debugging code (no puts/console.log in production)
- ✅ Minimal TODO comments (5 in 20K+ lines)
- ✅ Good separation of concerns
- ✅ Consistent naming conventions

### Issues Identified

**Critical**: Multiple obsolete monitoring services
- `AiMonitoringService` - OBSOLETE
- `AiComprehensiveMonitoringService` - OBSOLETE
- `UnifiedMonitoringService` - ACTIVE (use this)

**Moderate**: Service duplication in circuit breaker/recovery systems

### Cleanup Actions

**Phase 1** (Immediate):
- Add deprecation warnings to obsolete monitoring services
- Document service purposes in quick reference guide
- Create migration guide from old to new services

**Phase 2** (1-2 weeks):
- Consolidate circuit breaker services
- Refactor recovery services
- Extract common patterns into concerns

**Phase 3** (Ongoing):
- Resolve TODO comments
- Update documentation
- Improve test coverage

### Pre-Commit Checks

Install hooks: `./scripts/install-git-hooks.sh`

Automated checks:
- No console.log in production code
- No hardcoded color classes
- No puts/print in Ruby code
- All Ruby files have frozen_string_literal pragma

---

## Operational Procedures

### Daily Operations Checklist (10 minutes)

- [ ] Review overnight alerts
- [ ] Check dashboard for anomalies
- [ ] Verify all services running
- [ ] Review error rate trends
- [ ] Check cost tracking

### Weekly Review (30 minutes)

- [ ] Analyze failure patterns
- [ ] Review slow query log
- [ ] Check capacity trends
- [ ] Update alert thresholds
- [ ] Review cost optimization opportunities

### Monthly Review (2 hours)

- [ ] Capacity planning assessment
- [ ] Cost analysis and optimization
- [ ] Performance trend analysis
- [ ] Incident postmortems
- [ ] Update runbooks

### Success Metrics

**Reliability Targets**:
- Availability: 99.9% uptime
- API Response Time: < 200ms (P95)
- Workflow Success Rate: > 95%
- WebSocket Connection Stability: < 1% disconnection rate

**Performance Targets**:
- Batch Throughput: 100+ workflows/minute
- Queue Latency: < 1 second
- Database Query Time: < 50ms (P95)

---

## Quick Reference Commands

```bash
# Run backend tests
cd server && bundle exec rspec

# Run frontend tests
cd frontend && npm test

# Run with coverage
cd server && COVERAGE=true bundle exec rspec
cd frontend && npm run test:coverage

# Run E2E tests
cd frontend && npx cypress run

# Check service status
sudo scripts/systemd/powernode-installer.sh status

# View logs
journalctl -u powernode-backend@default -f

# Monitor Sidekiq
systemctl status powernode-worker@default
```

---

**Document Status**: ✅ Complete
**Consolidates**: AI_ORCHESTRATION_TESTING_GUIDE.md, AI_ORCHESTRATION_MONITORING_GUIDE.md, AI_ORCHESTRATION_CODE_QUALITY_EVALUATION.md
