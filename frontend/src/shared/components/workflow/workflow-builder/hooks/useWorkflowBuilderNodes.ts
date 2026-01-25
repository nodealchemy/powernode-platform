// Hook for managing workflow nodes in the builder

import { useCallback, useRef } from 'react';
import { Node } from '@xyflow/react';
import { AiWorkflow, AiWorkflowNode } from '@/shared/types/workflow';
import { migrateHandleId, generateUniqueEdgeId } from '../utils';
import { getDefaultHandlePositions, type HandlePositions } from '../../nodes/DynamicNodeHandles';

// Extended node type that may have position object from ReactFlow format
interface ExtendedWorkflowNode extends AiWorkflowNode {
  position?: { x: number; y: number };
}

// Node data type with handle positions
interface WorkflowNodeData extends Record<string, unknown> {
  name?: string;
  description?: string;
  node_type?: string;
  configuration?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
  is_start_node?: boolean;
  is_end_node?: boolean;
  timeout_seconds?: number;
  retry_count?: number;
  handlePositions?: HandlePositions;
}

interface UseWorkflowBuilderNodesOptions {
  workflow: AiWorkflow | undefined;
  nodes: Node[];
  edges: unknown[];
  setNodes: React.Dispatch<React.SetStateAction<Node[]>>;
  setEdges: React.Dispatch<React.SetStateAction<unknown[]>>;
  readOnly: boolean;
}

interface UseWorkflowBuilderNodesReturn {
  initializeNodesFromWorkflow: () => { nodes: Node[]; edges: unknown[] } | null;
  onAddNode: (nodeType: string, position: { x: number; y: number }) => void;
  onUpdateNode: (nodeId: string, updates: Partial<WorkflowNodeData>) => void;
  initializedWorkflowIdRef: React.MutableRefObject<string | null>;
}

export const useWorkflowBuilderNodes = ({
  workflow,
  nodes,
  edges,
  setNodes,
  setEdges,
  readOnly
}: UseWorkflowBuilderNodesOptions): UseWorkflowBuilderNodesReturn => {
  // Track the workflow ID we've initialized to prevent re-initialization after save
  const initializedWorkflowIdRef = useRef<string | null>(null);

  // Initialize nodes and edges from workflow data
  const initializeNodesFromWorkflow = useCallback(() => {
    if (!workflow || !workflow.nodes || !workflow.edges) return null;

    // Track used IDs to prevent duplicates
    const usedNodeIds = new Set<string>();

    const reactFlowNodes: Node[] = workflow.nodes
      .filter(node => node.node_id && node.node_type)
      .map((node, index) => {
        // Ensure unique ID
        let nodeId = node.node_id || `fallback-node-${index}-${Date.now()}`;
        let counter = 0;
        while (usedNodeIds.has(nodeId)) {
          nodeId = `${node.node_id || 'fallback-node'}-${index}-${counter++}-${Date.now()}`;
        }
        usedNodeIds.add(nodeId);

        const extendedNode = node as ExtendedWorkflowNode;
        const positionX = Number(node.position_x) || Number(extendedNode.position?.x) || 0;
        const positionY = Number(node.position_y) || Number(extendedNode.position?.y) || 0;

        return {
          id: nodeId,
          type: node.node_type,
          position: { x: positionX, y: positionY },
          data: {
            name: node.name || `Node ${index + 1}`,
            description: node.description || '',
            node_type: node.node_type,
            configuration: node.configuration || {},
            metadata: node.metadata || {},
            is_start_node: node.is_start_node || false,
            is_end_node: node.is_end_node || false,
            timeout_seconds: node.timeout_seconds || 3600,
            retry_count: node.retry_count || 0,
            handlePositions: node.handlePositions || node.metadata?.handlePositions || getDefaultHandlePositions(
              node.node_type,
              node.is_start_node || node.node_type === 'start' || node.node_type === 'trigger',
              node.is_end_node || node.node_type === 'end'
            )
          }
        };
      });

    // Track used edge IDs
    const usedEdgeIds = new Set<string>();

    const reactFlowEdges = workflow.edges
      .filter(edge => edge.source_node_id && edge.target_node_id)
      .map((edge, index) => {
        let edgeId = edge.edge_id || `edge-${edge.source_node_id}-${edge.target_node_id}-${index}`;
        let counter = 0;
        while (usedEdgeIds.has(edgeId)) {
          edgeId = `${edge.edge_id || 'edge'}-${edge.source_node_id}-${edge.target_node_id}-${index}-${counter++}-${Date.now()}`;
        }
        usedEdgeIds.add(edgeId);

        const migratedSourceHandle = migrateHandleId(edge.source_handle, true);
        const isConditionalEdge = migratedSourceHandle === 'true' ||
                                  migratedSourceHandle === 'false' ||
                                  edge.edge_type === 'conditional' ||
                                  edge.edge_type === 'success' ||
                                  edge.edge_type === 'error' ||
                                  edge.is_conditional;

        return {
          id: edgeId,
          source: edge.source_node_id,
          target: edge.target_node_id,
          type: isConditionalEdge ? 'conditional' : 'default',
          animated: false,
          sourceHandle: migratedSourceHandle,
          targetHandle: migrateHandleId(edge.target_handle, false),
          markerEnd: {
            type: 'arrowclosed' as const,
            width: 8,
            height: 8,
          },
          data: {
            conditionType: edge.condition_type,
            conditionValue: edge.condition_value,
            metadata: edge.metadata || {},
            edgeType: edge.edge_type || 'default',
            sourceHandle: migratedSourceHandle,
          },
        };
      });

    // Ensure no duplicates
    const uniqueNodes = reactFlowNodes.filter((node, index, arr) =>
      arr.findIndex(n => n.id === node.id) === index
    );
    const uniqueEdges = reactFlowEdges.filter((edge, index, arr) =>
      arr.findIndex(e => e.id === edge.id) === index
    );

    return { nodes: uniqueNodes, edges: uniqueEdges };
  }, [workflow]);

  // Handle adding new nodes
  const onAddNode = useCallback((nodeType: string, position: { x: number; y: number }) => {
    if (readOnly) return;

    const isStartNodeType = nodeType === 'trigger' || nodeType === 'start';

    if (isStartNodeType) {
      const existingStartNodes = nodes.filter(node => node.data?.is_start_node);
      if (existingStartNodes.length > 0) {
        const confirmAdd = window.confirm(
          'A start node already exists. Adding another start node will create multiple entry points. Continue?'
        );
        if (!confirmAdd) return;
      }
    }

    setNodes((currentNodes) => {
      let newNodeId = `node-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
      const existingIds = new Set(currentNodes.map(n => n.id));
      let counter = 0;
      while (existingIds.has(newNodeId)) {
        newNodeId = `node-${Date.now()}-${counter++}-${Math.random().toString(36).substr(2, 9)}`;
      }

      const newNode: Node = {
        id: newNodeId,
        type: nodeType,
        position,
        data: {
          name: `New ${nodeType.replace('_', ' ')} Node`,
          description: '',
          node_type: nodeType,
          configuration: {},
          metadata: {},
          is_start_node: nodeType === 'trigger' || nodeType === 'start',
          is_end_node: nodeType === 'end'
        }
      };

      return [...currentNodes, newNode];
    });
  }, [readOnly, nodes, setNodes]);

  // Handle node updates from config panel
  const onUpdateNode = useCallback((nodeId: string, updates: Partial<WorkflowNodeData>) => {
    const currentNode = nodes.find(n => n.id === nodeId);
    const currentNodeData = currentNode?.data as WorkflowNodeData | undefined;
    const newPositions = updates.handlePositions;
    const currentPositions = currentNodeData?.handlePositions;
    const positionsChanging = newPositions && JSON.stringify(newPositions) !== JSON.stringify(currentPositions);

    if (positionsChanging && currentNode) {
      interface EdgeWithSource { source: string; target: string; [key: string]: unknown; }
      const affectedEdges = (edges as EdgeWithSource[]).filter(edge => edge.source === nodeId || edge.target === nodeId);

      const updatedNode = {
        ...currentNode,
        data: {
          ...currentNode.data,
          ...updates,
          handlePositions: updates.handlePositions,
          is_start_node: currentNodeData?.is_start_node || currentNodeData?.node_type === 'trigger' || currentNodeData?.node_type === 'start',
          is_end_node: currentNodeData?.is_end_node || currentNodeData?.node_type === 'end',
        }
      };

      setNodes((nds) => nds.filter(n => n.id !== nodeId));
      setEdges((eds) => (eds as EdgeWithSource[]).filter(e => e.source !== nodeId && e.target !== nodeId));

      setTimeout(() => {
        setNodes((nds) => [...nds, updatedNode]);

        setTimeout(() => {
          const rebuiltEdges = affectedEdges.map(edge => {
            const migratedSourceHandle = migrateHandleId(edge.sourceHandle, true);
            return {
              ...edge,
              id: generateUniqueEdgeId(`${edge.source}-${edge.target}`),
              type: edge.type,
              animated: edge.animated,
              style: edge.style,
              markerEnd: edge.markerEnd,
              label: edge.label,
              data: {
                ...edge.data,
                sourceHandle: migratedSourceHandle,
              },
              sourceHandle: migratedSourceHandle,
              targetHandle: migrateHandleId(edge.targetHandle, false),
            };
          });
          setEdges((eds) => [...eds, ...rebuiltEdges]);
        }, 100);
      }, 50);
    } else {
      setNodes((nds) =>
        nds.map((node) => {
          if (node.id === nodeId) {
            const updatedData = { ...node.data, ...updates };

            if (updatedData.node_type) {
              updatedData.is_start_node = updatedData.is_start_node || updatedData.node_type === 'trigger' || updatedData.node_type === 'start';
              updatedData.is_end_node = updatedData.is_end_node || updatedData.node_type === 'end';
            }

            return { ...node, data: updatedData };
          }
          return node;
        })
      );
    }
  }, [nodes, edges, setNodes, setEdges]);

  return {
    initializeNodesFromWorkflow,
    onAddNode,
    onUpdateNode,
    initializedWorkflowIdRef
  };
};
