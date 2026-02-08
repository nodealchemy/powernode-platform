import React from 'react';
import { render, screen } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { AgentConnectionsGraph } from '@/features/ai/agents/components/AgentConnectionsGraph';
import { agentConnectionsApi } from '@/features/ai/agents/services/agentConnectionsApi';

// Mock ReactFlow
jest.mock('@xyflow/react', () => ({
  ReactFlow: ({ children }: { children: React.ReactNode }) => <div data-testid="react-flow">{children}</div>,
  MiniMap: () => <div data-testid="minimap" />,
  Controls: () => <div data-testid="controls" />,
  Background: () => <div data-testid="background" />,
  useNodesState: (initial: unknown[]) => [initial, jest.fn(), jest.fn()],
  useEdgesState: (initial: unknown[]) => [initial, jest.fn(), jest.fn()],
  MarkerType: { ArrowClosed: 'arrowclosed' },
  BackgroundVariant: { Dots: 'dots' },
  Handle: () => null,
  Position: { Top: 'top', Bottom: 'bottom' },
}));

jest.mock('@/shared/utils/workflowLayout', () => ({
  autoArrangeNodes: (nodes: unknown[]) => nodes,
}));

jest.mock('@/features/ai/agents/services/agentConnectionsApi');

const mockApi = agentConnectionsApi as jest.Mocked<typeof agentConnectionsApi>;

const renderWithRouter = (ui: React.ReactElement) => {
  return render(<BrowserRouter>{ui}</BrowserRouter>);
};

describe('AgentConnectionsGraph', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('renders loading state initially', () => {
    mockApi.getAgentConnections.mockImplementation(() => new Promise(() => {}));
    renderWithRouter(<AgentConnectionsGraph agentId="test-id" />);
    expect(screen.getByText('Loading connections...')).toBeInTheDocument();
  });

  it('renders empty state when no connections', async () => {
    mockApi.getAgentConnections.mockResolvedValue({
      nodes: [{ id: '1', type: 'agent', name: 'Test Agent', status: 'active', metadata: {} }],
      edges: [],
      summary: { teams: 0, peers: 0, mcp_servers: 0, connections: 0 },
    });

    renderWithRouter(<AgentConnectionsGraph agentId="test-id" />);
    expect(await screen.findByText('No connections found')).toBeInTheDocument();
  });

  it('renders summary cards with connection data', async () => {
    mockApi.getAgentConnections.mockResolvedValue({
      nodes: [
        { id: '1', type: 'agent', name: 'Test Agent', status: 'active', metadata: {} },
        { id: '2', type: 'team', name: 'Team A', status: 'active', metadata: { member_count: 3 } },
      ],
      edges: [
        { source: '1', target: '2', relationship: 'team_membership', label: 'member of' },
      ],
      summary: { teams: 1, peers: 0, mcp_servers: 0, connections: 1 },
    });

    renderWithRouter(<AgentConnectionsGraph agentId="test-id" />);
    expect(await screen.findByText('Teams')).toBeInTheDocument();
    expect(screen.getByText('Peers')).toBeInTheDocument();
    expect(screen.getByText('MCP Servers')).toBeInTheDocument();
  });
});
