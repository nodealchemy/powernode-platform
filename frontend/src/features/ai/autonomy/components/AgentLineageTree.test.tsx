import { render, screen, within } from '@testing-library/react';
import { AgentLineageTree } from './AgentLineageTree';
import type { AgentLineageNode } from '../types/autonomy';

// HIER-P0 — a lineage node renders its NAME first and its agent_type as a
// secondary label, and a global canonical agent (is_system && account_id nil)
// carries a "canonical" badge so an operator can tell the seeded platform
// agent from an account's clone of it at a glance.

jest.mock('@/shared/components/entity', () => ({
  EntityLink: ({ label }: { label: React.ReactNode }) => <span>{label}</span>,
}));

const baseNode: AgentLineageNode = {
  id: 'agent-1',
  name: 'System Concierge',
  type: 'concierge',
  status: 'active',
  trust_level: 'supervised',
  depth: 0,
  canonical: true,
  children: [
    {
      id: 'agent-2',
      name: 'Concierge (ours)',
      type: 'concierge',
      status: 'active',
      depth: 1,
      canonical: false,
      children: [],
    },
  ],
};

describe('AgentLineageTree', () => {
  it('renders the agent name before the type label', () => {
    render(<AgentLineageTree root={baseNode} />);

    const row = screen.getByTestId('lineage-node-agent-1');
    const name = within(row).getByTestId('lineage-node-name');
    const type = within(row).getByTestId('lineage-node-type');

    expect(name).toHaveTextContent('System Concierge');
    expect(type).toHaveTextContent('concierge');
    // DOM order: the name precedes the type label.
    expect(name.compareDocumentPosition(type) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('shows a canonical badge on a global agent and none on an account clone', () => {
    render(<AgentLineageTree root={baseNode} />);

    const canonicalRow = screen.getByTestId('lineage-node-agent-1');
    expect(within(canonicalRow).getByText('canonical')).toBeInTheDocument();

    const cloneRow = screen.getByTestId('lineage-node-agent-2');
    expect(within(cloneRow).queryByText('canonical')).not.toBeInTheDocument();
    expect(within(cloneRow).getByTestId('lineage-node-name')).toHaveTextContent('Concierge (ours)');
  });

  it('treats a node without the canonical flag as an ordinary agent', () => {
    const legacy: AgentLineageNode = { ...baseNode, canonical: undefined, children: [] };
    render(<AgentLineageTree root={legacy} />);

    expect(screen.queryByText('canonical')).not.toBeInTheDocument();
  });
});
