// Hook for managing workflow save operations

import { useCallback } from 'react';
import { Node, Edge } from '@xyflow/react';
import { migrateHandleId } from '@/shared/components/workflow/workflow-builder/utils';
import { getDefaultHandlePositions } from '@/shared/components/workflow/nodes/DynamicNodeHandles';

interface UseWorkflowBuilderSaveOptions {
  nodes: Node[];
  edges: Edge[];
  onSave: (workflowData: { nodes: any[]; edges: any[]; configuration: Record<string, any> }) => void;
  onValidate?: (nodes: Node[], edges: Edge[]) => Promise<{
    valid: boolean;
    errors: string[];
    warnings: string[];
  }>;
  validationResult: {
    valid: boolean;
    errors: string[];
    warnings: string[];
  } | null;
  setValidationResult: React.Dispatch<React.SetStateAction<{
    valid: boolean;
    errors: string[];
    warnings: string[];
  } | null>>;
  setOriginalNodes: React.Dispatch<React.SetStateAction<Node[]>>;
  setOriginalEdges: React.Dispatch<React.SetStateAction<Edge[]>>;
  setHasChanges: React.Dispatch<React.SetStateAction<boolean>>;
}

interface UseWorkflowBuilderSaveReturn {
  handleValidate: () => Promise<{ valid: boolean; errors: string[]; warnings: string[] }>;
  handleSave: () => Promise<void>;
}

export const useWorkflowBuilderSave = ({
  nodes,
  edges,
  onSave,
  onValidate,
  validationResult,
  setValidationResult,
  setOriginalNodes,
  setOriginalEdges,
  setHasChanges
}: UseWorkflowBuilderSaveOptions): UseWorkflowBuilderSaveReturn => {

  // Handle workflow validation
  const handleValidate = useCallback(async () => {
    if (onValidate) {
      const result = await onValidate(nodes, edges);
      setValidationResult(result);
      return result;
    }
    return { valid: true, errors: [], warnings: [] };
  }, [nodes, edges, onValidate, setValidationResult]);

  // Handle workflow save
  const handleSave = useCallback(async () => {
    // Validate first
    const validation = await handleValidate();
    if (!validation.valid) {
      return;
    }

    // Convert React Flow nodes/edges back to workflow format
    const workflowNodes = nodes.map(node => {
      const isStartNode = Boolean(node.data.is_start_node || node.data.node_type === 'trigger' || node.data.node_type === 'start');
      const isEndNode = Boolean(node.data.is_end_node || node.data.node_type === 'end');

      return {
        id: node.id,
        node_id: node.id,
        node_type: node.data.node_type,
        name: node.data.name,
        description: node.data.description || '',
        position: {
          x: Math.round(node.position.x),
          y: Math.round(node.position.y)
        },
        configuration: node.data.configuration || {},
        metadata: {
          ...node.data.metadata || {},
          handlePositions: node.data.handlePositions || getDefaultHandlePositions(
            node.data.node_type as string,
            isStartNode,
            isEndNode
          )
        },
        is_start_node: isStartNode,
        is_end_node: isEndNode,
        is_error_handler: node.data.is_error_handler || false,
        timeout_seconds: node.data.timeout_seconds || 300,
        retry_count: node.data.retry_count || 0
      };
    });

    const workflowEdges = edges.map(edge => ({
      id: edge.id,
      edge_id: edge.id,
      source_node_id: edge.source,
      target_node_id: edge.target,
      source_handle: migrateHandleId(edge.sourceHandle, true),
      target_handle: migrateHandleId(edge.targetHandle, false),
      edge_type: edge.data?.edge_type || (edge.data?.condition_type ? 'conditional' : 'default'),
      is_conditional: Boolean(edge.data?.condition_type),
      condition_type: edge.data?.condition_type,
      condition_value: edge.data?.condition_value,
      metadata: edge.data?.metadata || {}
    }));

    onSave({
      nodes: workflowNodes,
      edges: workflowEdges,
      configuration: {
        validation: validationResult,
        lastModified: new Date().toISOString()
      }
    });

    // Reset change tracking after save
    setOriginalNodes([...nodes]);
    setOriginalEdges([...edges]);
    setHasChanges(false);
  }, [nodes, edges, onSave, handleValidate, validationResult, setOriginalNodes, setOriginalEdges, setHasChanges]);

  return {
    handleValidate,
    handleSave
  };
};
