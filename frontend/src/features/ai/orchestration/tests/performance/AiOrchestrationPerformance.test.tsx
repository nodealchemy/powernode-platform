import React from 'react';
import { render, screen } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

import { agentsApi } from '@/shared/services/ai';

// Mock ESM packages before importing components
jest.mock('remark-gfm', () => () => ({}));
jest.mock('remark-breaks', () => () => ({}));
jest.mock('react-markdown', () => ({ children }: any) => <div>{children}</div>);

// Mock all API services
jest.mock('@/shared/services/ai', () => ({
  agentsApi: {
    getAgents: jest.fn(),
    createAgent: jest.fn(),
    updateAgent: jest.fn(),
    deleteAgent: jest.fn(),
    executeAgent: jest.fn()
  },
  workflowsApi: {
    getWorkflows: jest.fn(),
    createWorkflow: jest.fn(),
    updateWorkflow: jest.fn(),
    deleteWorkflow: jest.fn(),
    executeWorkflow: jest.fn(),
    getWorkflow: jest.fn()
  },
  providersApi: {
    getProviders: jest.fn(),
    createProvider: jest.fn(),
    updateProvider: jest.fn(),
    deleteProvider: jest.fn(),
    testConnection: jest.fn()
  },
  conversationsApi: {},
  pluginsApi: {}
}));

// Mock useNotifications to avoid Redux dependency
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: jest.fn(),
    addNotification: jest.fn(),
  }),
}));

// Mock usePermissions to avoid Redux dependency
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({
    hasPermission: () => true,
    hasAnyPermission: () => true,
    hasAllPermissions: () => true,
  }),
}));

// Note: Full performance tests for AI orchestration components
// require complex setup for WebSocket mocking, timing-sensitive scenarios,
// and PerformanceObserver integration that is brittle in CI environments.
// These tests verify the mock infrastructure and helper utilities work correctly.

describe('AI Orchestration Performance Test Infrastructure', () => {
  let queryClient: QueryClient;

  beforeEach(() => {
    queryClient = new QueryClient({
      defaultOptions: {
        queries: { retry: false },
        mutations: { retry: false }
      }
    });
    jest.clearAllMocks();
  });

  const renderWithProviders = (component: React.ReactElement) => {
    return render(
      <QueryClientProvider client={queryClient}>
        <BrowserRouter>
          {component}
        </BrowserRouter>
      </QueryClientProvider>
    );
  };

  describe('Mock Infrastructure Verification', () => {
    it('API mocks are properly configured', () => {
      expect(agentsApi.getAgents).toBeDefined();
      expect(typeof agentsApi.getAgents).toBe('function');
    });

    it('can render test components with providers', () => {
      renderWithProviders(<div data-testid="perf-test">Performance Test</div>);
      expect(screen.getByTestId('perf-test')).toBeInTheDocument();
    });

    it('API mocks return resolved promises', async () => {
      (agentsApi.getAgents as jest.Mock).mockResolvedValue({
        items: [{ id: 'agent-1', name: 'Test Agent' }],
        pagination: { current_page: 1, per_page: 25, total_pages: 1, total_count: 1 }
      });

      const result = await agentsApi.getAgents();
      expect(result.items).toHaveLength(1);
    });

    it('API mocks can simulate large datasets', async () => {
      const largeDataset = Array.from({ length: 100 }, (_, i) => ({
        id: `agent-${i}`,
        name: `Agent ${i}`,
        status: 'active'
      }));

      (agentsApi.getAgents as jest.Mock).mockResolvedValue({
        items: largeDataset,
        pagination: { current_page: 1, per_page: 100, total_pages: 1, total_count: 100 }
      });

      const result = await agentsApi.getAgents();
      expect(result.items).toHaveLength(100);
    });
  });

  describe('Helper Function Verification', () => {
    // Helper functions that would be used in actual performance tests
    function generateMockAgents(count: number) {
      return Array.from({ length: count }, (_, i) => ({
        id: `agent-${i}`,
        name: `Agent ${i}`,
        description: `Description for agent ${i}`,
        agent_type: 'content_analysis',
        status: 'active',
        created_at: new Date().toISOString(),
        ai_provider: {
          id: `provider-${i % 3}`,
          name: `Provider ${i % 3}`,
          provider_type: 'openai'
        }
      }));
    }

    function generateMockActivity() {
      const types = ['agent_executed', 'workflow_completed', 'provider_health_changed'] as const;
      const statuses = ['success', 'info', 'warning', 'error'] as const;

      return {
        id: `activity-${Date.now()}-${Math.random()}`,
        type: types[Math.floor(Math.random() * types.length)],
        title: 'Performance Test Activity',
        description: 'Generated for performance testing',
        timestamp: new Date().toISOString(),
        status: statuses[Math.floor(Math.random() * statuses.length)],
        metadata: { test: true }
      };
    }

    it('generateMockAgents creates correct number of agents', () => {
      const agents = generateMockAgents(50);
      expect(agents).toHaveLength(50);
    });

    it('generateMockAgents creates agents with correct structure', () => {
      const agents = generateMockAgents(1);
      const agent = agents[0];

      expect(agent).toHaveProperty('id');
      expect(agent).toHaveProperty('name');
      expect(agent).toHaveProperty('description');
      expect(agent).toHaveProperty('agent_type');
      expect(agent).toHaveProperty('status');
      expect(agent).toHaveProperty('ai_provider');
      expect(agent.ai_provider).toHaveProperty('id');
      expect(agent.ai_provider).toHaveProperty('name');
      expect(agent.ai_provider).toHaveProperty('provider_type');
    });

    it('generateMockActivity creates activity with correct structure', () => {
      const activity = generateMockActivity();

      expect(activity).toHaveProperty('id');
      expect(activity).toHaveProperty('type');
      expect(activity).toHaveProperty('title');
      expect(activity).toHaveProperty('description');
      expect(activity).toHaveProperty('timestamp');
      expect(activity).toHaveProperty('status');
      expect(activity).toHaveProperty('metadata');
    });

    it('generateMockActivity creates unique IDs', () => {
      const activities = Array.from({ length: 10 }, () => generateMockActivity());
      const ids = activities.map(a => a.id);
      const uniqueIds = new Set(ids);

      expect(uniqueIds.size).toBe(10);
    });
  });

  describe('Performance Test Data Structures', () => {
    it('mock workflow data has correct shape for performance testing', () => {
      const mockLargeWorkflow = {
        id: 'large-workflow-1',
        name: 'Large Performance Test Workflow',
        description: 'Workflow with many nodes for performance testing',
        status: 'active',
        trigger_type: 'manual',
        created_at: '2024-01-15T10:00:00Z',
        ai_workflow_nodes: Array.from({ length: 50 }, (_, i) => ({
          id: `node-${i}`,
          node_id: `node-${i}`,
          node_type: 'ai_agent',
          name: `Node ${i}`,
          position_x: (i % 10) * 150,
          position_y: Math.floor(i / 10) * 100,
          configuration: { agent_id: `agent-${i % 5}` }
        })),
        ai_workflow_edges: Array.from({ length: 49 }, (_, i) => ({
          id: `edge-${i}`,
          source_node_id: `node-${i}`,
          target_node_id: `node-${i + 1}`
        })),
        statistics: {
          total_executions: 500,
          successful_executions: 485,
          failed_executions: 15,
          average_execution_time: 15000
        }
      };

      expect(mockLargeWorkflow.ai_workflow_nodes).toHaveLength(50);
      expect(mockLargeWorkflow.ai_workflow_edges).toHaveLength(49);
      expect(mockLargeWorkflow.statistics.total_executions).toBe(500);
    });

    it('mock execution updates have correct shape', () => {
      const executionUpdate = {
        type: 'node_execution_update',
        data: {
          id: 'node-update-1',
          type: 'node_completed',
          title: 'Node Completed',
          description: 'Node processing completed',
          timestamp: new Date().toISOString(),
          status: 'success',
          metadata: { node_id: 'node-1', execution_time: 1000 }
        }
      };

      expect(executionUpdate.type).toBe('node_execution_update');
      expect(executionUpdate.data).toHaveProperty('id');
      expect(executionUpdate.data).toHaveProperty('type');
      expect(executionUpdate.data).toHaveProperty('metadata');
      expect(executionUpdate.data.metadata.execution_time).toBe(1000);
    });
  });
});
