import React, { useMemo } from 'react';
import {
  ReactFlow,
  Controls,
  Background,
  MiniMap,
  type Node,
  type Edge,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import { autoArrangeNodes } from '@/shared/utils/workflowLayout';
import RalphTaskNode from './RalphTaskNode';
import ApprovalGateNode from './ApprovalGateNode';
import type { TaskGraph, MissionPhase } from '../../types/mission';
import { Loader2 } from 'lucide-react';

interface MissionTaskGraphProps {
  taskGraph: TaskGraph | null;
  loading: boolean;
  selectedPhase?: MissionPhase | null;
}

const nodeTypes = {
  ralphTask: RalphTaskNode,
  approvalGate: ApprovalGateNode,
};

export const MissionTaskGraph: React.FC<MissionTaskGraphProps> = ({
  taskGraph,
  loading,
  selectedPhase,
}) => {
  const { nodes, edges } = useMemo(() => {
    if (!taskGraph || taskGraph.nodes.length === 0) {
      return { nodes: [] as Node[], edges: [] as Edge[] };
    }

    let filteredNodes = taskGraph.nodes;
    if (selectedPhase) {
      filteredNodes = taskGraph.nodes.filter(n => n.phase === selectedPhase);
    }

    const nodeIds = new Set(filteredNodes.map(n => n.id));

    const flowNodes: Node[] = filteredNodes.map(node => ({
      id: node.id,
      type: 'ralphTask',
      position: { x: 0, y: 0 },
      data: {
        task_key: node.task_key,
        description: node.description,
        status: node.status,
        execution_type: node.execution_type,
        executor_name: node.executor_name,
        phase: node.phase,
      },
    }));

    const flowEdges: Edge[] = taskGraph.edges
      .filter(e => nodeIds.has(e.source) && nodeIds.has(e.target))
      .map(edge => ({
        id: edge.id,
        source: edge.source,
        target: edge.target,
        animated: true,
      }));

    const arranged = autoArrangeNodes(flowNodes, flowEdges, {
      direction: 'TB',
      nodeWidth: 220,
      nodeHeight: 80,
      spacing: 60,
    });

    return { nodes: arranged, edges: flowEdges };
  }, [taskGraph, selectedPhase]);

  if (loading) {
    return (
      <div className="card-theme p-6 flex items-center justify-center h-64">
        <Loader2 className="w-5 h-5 animate-spin text-theme-secondary" />
      </div>
    );
  }

  if (nodes.length === 0) {
    return (
      <div className="card-theme p-6 flex items-center justify-center h-64">
        <p className="text-sm text-theme-tertiary">No tasks to display</p>
      </div>
    );
  }

  return (
    <div className="card-theme overflow-hidden" style={{ height: 400 }}>
      <ReactFlow
        nodes={nodes}
        edges={edges}
        nodeTypes={nodeTypes}
        fitView
        nodesDraggable
        nodesConnectable={false}
        elementsSelectable={false}
        proOptions={{ hideAttribution: true }}
      >
        <Controls showInteractive={false} />
        <Background gap={16} size={1} />
        <MiniMap
          nodeStrokeWidth={3}
          pannable
          zoomable
          className="!bg-theme-surface"
        />
      </ReactFlow>
    </div>
  );
};
