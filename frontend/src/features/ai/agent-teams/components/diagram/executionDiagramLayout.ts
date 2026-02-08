// Deterministic layout for team execution diagrams by team_type
import type {
  ExecutionNode,
  ExecutionEdge,
  DiagramDirection,
  LayoutResult,
  AgentTeam,
  TeamMember,
} from './executionDiagramTypes';

const H_GAP = 250;
const V_GAP = 120;

const INPUT_NODE_ID = '__input__';
const OUTPUT_NODE_ID = '__output__';

function createMemberNode(
  id: string,
  member: TeamMember,
  x: number,
  y: number,
  direction: DiagramDirection
): ExecutionNode {
  return {
    id,
    type: 'executionMember',
    position: { x, y },
    data: {
      memberName: member.agent_name,
      role: member.role,
      isLead: member.is_lead,
      status: 'idle',
      nodeKind: 'member',
      direction,
      capabilities: member.capabilities || [],
    },
  };
}

function createSentinelNode(
  kind: 'input' | 'output',
  x: number,
  y: number,
  direction: DiagramDirection
): ExecutionNode {
  const id = kind === 'input' ? INPUT_NODE_ID : OUTPUT_NODE_ID;
  return {
    id,
    type: kind === 'input' ? 'executionInput' : 'executionOutput',
    position: { x, y },
    data: {
      memberName: kind === 'input' ? 'Input' : 'Output',
      role: '',
      isLead: false,
      status: 'idle',
      nodeKind: kind,
      direction,
    },
  };
}

function createEdge(
  source: string,
  target: string,
  direction: DiagramDirection
): ExecutionEdge {
  return {
    id: `edge-${source}-${target}`,
    source,
    target,
    type: 'executionFlow',
    data: { status: 'idle', direction },
  };
}

function sortByPriority(members: TeamMember[]): TeamMember[] {
  return [...members].sort((a, b) => a.priority_order - b.priority_order);
}

function findLead(members: TeamMember[]): TeamMember | undefined {
  return members.find((m) => m.is_lead) || sortByPriority(members)[0];
}

function layoutSequential(
  members: TeamMember[],
  direction: DiagramDirection
): LayoutResult {
  const sorted = sortByPriority(members);
  const nodes: ExecutionNode[] = [];
  const edges: ExecutionEdge[] = [];
  const nameToId = new Map<string, string>();

  // Input sentinel
  nodes.push(createSentinelNode('input', 0, 0, direction));

  // Members in a chain
  sorted.forEach((member, i) => {
    const nodeId = `member-${member.id}`;
    nameToId.set(member.agent_name, nodeId);
    nodes.push(createMemberNode(nodeId, member, (i + 1) * H_GAP, 0, direction));
  });

  // Output sentinel
  nodes.push(
    createSentinelNode('output', (sorted.length + 1) * H_GAP, 0, direction)
  );

  // Edges: input → m1 → m2 → ... → output
  edges.push(createEdge(INPUT_NODE_ID, `member-${sorted[0].id}`, direction));
  for (let i = 0; i < sorted.length - 1; i++) {
    edges.push(
      createEdge(`member-${sorted[i].id}`, `member-${sorted[i + 1].id}`, direction)
    );
  }
  edges.push(
    createEdge(`member-${sorted[sorted.length - 1].id}`, OUTPUT_NODE_ID, direction)
  );

  return { nodes, edges, direction, memberNameToNodeId: nameToId };
}

function layoutParallel(
  members: TeamMember[],
  direction: DiagramDirection
): LayoutResult {
  const sorted = sortByPriority(members);
  const nodes: ExecutionNode[] = [];
  const edges: ExecutionEdge[] = [];
  const nameToId = new Map<string, string>();

  const totalHeight = (sorted.length - 1) * V_GAP;
  const startY = -totalHeight / 2;

  // Input sentinel on the left, centered vertically
  nodes.push(createSentinelNode('input', 0, 0, direction));

  // Members stacked vertically at same x
  sorted.forEach((member, i) => {
    const nodeId = `member-${member.id}`;
    nameToId.set(member.agent_name, nodeId);
    nodes.push(
      createMemberNode(nodeId, member, H_GAP, startY + i * V_GAP, direction)
    );
  });

  // Output sentinel on the right, centered vertically
  nodes.push(createSentinelNode('output', H_GAP * 2, 0, direction));

  // Fan-out edges: input → each member
  sorted.forEach((member) => {
    edges.push(createEdge(INPUT_NODE_ID, `member-${member.id}`, direction));
  });

  // Fan-in edges: each member → output
  sorted.forEach((member) => {
    edges.push(createEdge(`member-${member.id}`, OUTPUT_NODE_ID, direction));
  });

  return { nodes, edges, direction, memberNameToNodeId: nameToId };
}

function layoutHierarchical(
  members: TeamMember[],
  direction: DiagramDirection
): LayoutResult {
  const nodes: ExecutionNode[] = [];
  const edges: ExecutionEdge[] = [];
  const nameToId = new Map<string, string>();

  const lead = findLead(members);
  const workers = members.filter((m) => m !== lead);
  const sortedWorkers = sortByPriority(workers);

  const workerTotalWidth = (sortedWorkers.length - 1) * H_GAP;
  const workerStartX = -workerTotalWidth / 2;

  // Input at top center
  nodes.push(createSentinelNode('input', 0, 0, direction));

  // Lead below input
  if (lead) {
    const leadId = `member-${lead.id}`;
    nameToId.set(lead.agent_name, leadId);
    nodes.push(createMemberNode(leadId, lead, 0, V_GAP, direction));
    edges.push(createEdge(INPUT_NODE_ID, leadId, direction));

    // Workers below lead
    sortedWorkers.forEach((worker, i) => {
      const workerId = `member-${worker.id}`;
      nameToId.set(worker.agent_name, workerId);
      nodes.push(
        createMemberNode(
          workerId,
          worker,
          workerStartX + i * H_GAP,
          V_GAP * 2,
          direction
        )
      );
      edges.push(createEdge(leadId, workerId, direction));
    });

    // Output below workers
    nodes.push(createSentinelNode('output', 0, V_GAP * 3, direction));
    sortedWorkers.forEach((worker) => {
      edges.push(createEdge(`member-${worker.id}`, OUTPUT_NODE_ID, direction));
    });

    // If no workers, lead connects directly to output
    if (sortedWorkers.length === 0) {
      edges.push(createEdge(leadId, OUTPUT_NODE_ID, direction));
    }
  }

  return { nodes, edges, direction, memberNameToNodeId: nameToId };
}

function layoutMesh(
  members: TeamMember[],
  direction: DiagramDirection
): LayoutResult {
  const nodes: ExecutionNode[] = [];
  const edges: ExecutionEdge[] = [];
  const nameToId = new Map<string, string>();

  const sorted = sortByPriority(members);
  const maxPerRow = 5;
  const rows: TeamMember[][] = [];

  for (let i = 0; i < sorted.length; i += maxPerRow) {
    rows.push(sorted.slice(i, i + maxPerRow));
  }

  // Input at top center
  nodes.push(createSentinelNode('input', 0, 0, direction));

  // Members in grid rows
  rows.forEach((row, rowIdx) => {
    const rowWidth = (row.length - 1) * H_GAP;
    const rowStartX = -rowWidth / 2;

    row.forEach((member, colIdx) => {
      const nodeId = `member-${member.id}`;
      nameToId.set(member.agent_name, nodeId);
      nodes.push(
        createMemberNode(
          nodeId,
          member,
          rowStartX + colIdx * H_GAP,
          (rowIdx + 1) * V_GAP,
          direction
        )
      );
    });
  });

  // Output below all rows
  const outputY = (rows.length + 1) * V_GAP;
  nodes.push(createSentinelNode('output', 0, outputY, direction));

  // All members connect to input and output
  sorted.forEach((member) => {
    edges.push(createEdge(INPUT_NODE_ID, `member-${member.id}`, direction));
    edges.push(createEdge(`member-${member.id}`, OUTPUT_NODE_ID, direction));
  });

  return { nodes, edges, direction, memberNameToNodeId: nameToId };
}

export function buildExecutionGraph(
  team: AgentTeam,
  members: TeamMember[]
): LayoutResult {
  if (members.length === 0) {
    return {
      nodes: [],
      edges: [],
      direction: 'LR',
      memberNameToNodeId: new Map(),
    };
  }

  switch (team.team_type) {
    case 'sequential':
      return layoutSequential(members, 'LR');
    case 'parallel':
      return layoutParallel(members, 'LR');
    case 'hierarchical':
      return layoutHierarchical(members, 'TB');
    case 'mesh':
      return layoutMesh(members, 'TB');
    default:
      return layoutSequential(members, 'LR');
  }
}
