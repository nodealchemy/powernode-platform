import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { StackTopologyPreview, buildTopologyFlowGraph } from './StackTopologyPreview';
import type { TopologyPreview } from './types';

jest.mock('@xyflow/react', () => ({
  ReactFlow: ({ children, nodes, edges }: { children?: React.ReactNode; nodes: unknown[]; edges: unknown[] }) => (
    <div
      data-testid="react-flow"
      data-node-count={nodes.length}
      data-edge-count={edges.length}
    >
      {children}
    </div>
  ),
  Background: () => <div data-testid="flow-background" />,
  Controls: () => <div data-testid="flow-controls" />,
  MarkerType: { ArrowClosed: 'arrowclosed' },
  Handle: () => null,
  Position: { Top: 'top', Bottom: 'bottom' }
}));

const sampleTopology: TopologyPreview = {
  nodes: [
    { id: 'web-1', type: 'compute', label: 'Web tier', region_id: 'us-east-1' },
    { id: 'db-1', type: 'database', label: 'Postgres', region_id: 'us-east-1' },
    { id: 'cache-1', type: 'cache', label: 'Redis', region_id: 'us-east-1' },
    { id: 'gw-1', type: 'gateway', label: 'API Gateway', region_id: 'us-east-1' },
    { id: 'net-1', type: 'network', label: 'VPC', region_id: 'us-east-1' }
  ],
  edges: [
    { source: 'gw-1', target: 'web-1' },
    { source: 'web-1', target: 'db-1' },
    { source: 'web-1', target: 'cache-1' }
  ],
  regions: [{ id: 'us-east-1', name: 'us-east-1' }]
};

describe('StackTopologyPreview', () => {
  it('renders the ReactFlow shell with one node per topology node', () => {
    render(<StackTopologyPreview topology={sampleTopology} />);
    const flow = screen.getByTestId('react-flow');
    expect(flow).toHaveAttribute('data-node-count', '5');
    expect(flow).toHaveAttribute('data-edge-count', '3');
  });

  it('renders the empty state when topology has no nodes', () => {
    render(
      <StackTopologyPreview
        topology={{ nodes: [], edges: [], regions: [] }}
      />
    );
    expect(screen.getByTestId('stack-topology-preview-empty')).toBeInTheDocument();
    expect(screen.queryByTestId('react-flow')).not.toBeInTheDocument();
  });

  it('toggles the expand affordance and reveals controls when expanded', () => {
    render(<StackTopologyPreview topology={sampleTopology} />);
    const toggle = screen.getByTestId('stack-topology-expand-toggle');
    expect(toggle).toHaveAttribute('aria-label', 'Expand topology');
    expect(screen.queryByTestId('flow-controls')).not.toBeInTheDocument();

    fireEvent.click(toggle);
    expect(toggle).toHaveAttribute('aria-label', 'Collapse topology');
    expect(screen.getByTestId('flow-controls')).toBeInTheDocument();
  });

  it('hides the expand affordance when expandable=false', () => {
    render(<StackTopologyPreview topology={sampleTopology} expandable={false} />);
    expect(screen.queryByTestId('stack-topology-expand-toggle')).not.toBeInTheDocument();
  });

  describe('buildTopologyFlowGraph', () => {
    it('returns empty arrays for null/empty input', () => {
      expect(buildTopologyFlowGraph(null)).toEqual({ nodes: [], edges: [] });
      expect(buildTopologyFlowGraph({ nodes: [], edges: [], regions: [] })).toEqual({
        nodes: [],
        edges: []
      });
    });

    it('places network containers ahead of leaf children for ReactFlow parentage', () => {
      const topology: TopologyPreview = {
        nodes: [
          { id: 'web-1', type: 'compute', label: 'Web', parent_id: 'net-1', region_id: 'us-east-1' },
          { id: 'net-1', type: 'network', label: 'VPC', region_id: 'us-east-1' }
        ],
        edges: [],
        regions: [{ id: 'us-east-1', name: 'us-east-1' }]
      };
      const { nodes } = buildTopologyFlowGraph(topology);
      expect(nodes[0].id).toBe('net-1');
      expect(nodes[1].id).toBe('web-1');
      expect(nodes[1].parentId).toBe('net-1');
      expect(nodes[1].extent).toBe('parent');
    });

    it('encodes edges with markerEnd and a stable id', () => {
      const { edges } = buildTopologyFlowGraph(sampleTopology);
      expect(edges).toHaveLength(3);
      expect(edges[0]).toMatchObject({
        source: 'gw-1',
        target: 'web-1',
        markerEnd: { type: 'arrowclosed' }
      });
      expect(edges[0].id).toMatch(/^e-0-gw-1-web-1$/);
    });
  });
});
