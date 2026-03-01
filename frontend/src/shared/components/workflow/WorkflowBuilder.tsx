import React, { useState, useCallback, useEffect, useMemo, useRef } from 'react';
import {
  ReactFlow,
  Node,
  Edge,
  addEdge,
  useNodesState,
  useEdgesState,
  Controls,
  MiniMap,
  Background,
  BackgroundVariant,
  Connection,
  NodeChange,
  ReactFlowProvider,
  Panel,
  ReactFlowInstance,
  ConnectionLineType
} from '@xyflow/react';
import { Workflow } from 'lucide-react';
import '@xyflow/react/dist/style.css';
import { autoArrangeNodes, getLayoutOptions } from '@/shared/utils/workflowLayout';
import { useWorkflowHistory } from '@/shared/hooks/useWorkflowHistory';
import { useWorkflowExecution } from '@/shared/hooks/useWorkflowExecution';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { HistoryControls } from '@/shared/components/workflow/HistoryControls';
import { ExecutionStats } from '@/shared/components/workflow/ExecutionOverlay';

// Import extracted constants and utilities
import {
  NODE_TYPES,
  EDGE_TYPES,
  DEFAULT_EDGE_OPTIONS,
  generateUniqueEdgeId,
  migrateHandleId,
  calculateOptimalSide,
  snapToGridPosition as snapToGridUtil
} from '@/shared/components/workflow/workflow-builder';
import { getDefaultHandlePositions, type HandlePositions } from '@/shared/components/workflow/nodes/DynamicNodeHandles';

// Components
import { NodePalette } from '@/shared/components/workflow/NodePalette';
import { NodeConfigPanel } from '@/shared/components/workflow/NodeConfigPanel';
import { WorkflowToolbar } from '@/shared/components/workflow/WorkflowToolbar';
import { NodeOperationsChat } from '@/shared/components/workflow/NodeOperationsChat';
import { WorkflowProvider } from '@/shared/components/workflow/WorkflowContext';

import { AiWorkflow, AiWorkflowNode, BaseWorkflowNodeData, NodeExecutionStatus } from '@/shared/types/workflow';
import { AiAgent } from '@/shared/types/ai';
import { agentsApi } from '@/shared/services/ai';

// Extended workflow node type that may have position as object (from save response)
interface ExtendedWorkflowNode extends AiWorkflowNode {
  position?: { x: number; y: number };
}

// Extended node data type with handle positions
interface NodeDataWithHandles extends BaseWorkflowNodeData {
  handlePositions?: HandlePositions;
  positionsUpdated?: number;
  executionStatus?: NodeExecutionStatus;
  executionDuration?: number;
  executionError?: string;
}


export interface WorkflowBuilderProps {
  workflow?: AiWorkflow;
   
  onSave: (workflowData: { nodes: Node[]; edges: Edge[]; configuration: Record<string, unknown> }) => void;
  onValidate?: (nodes: Node[], edges: Edge[]) => Promise<{
    valid: boolean;
    errors: string[];
    warnings: string[];
  }>;
  readOnly?: boolean;
  className?: string;
  showGrid?: boolean;
  onGridToggle?: (showGrid: boolean) => void;
  snapToGrid?: boolean;
  onSnapToGridToggle?: (snapToGrid: boolean) => void;
  gridSize?: number;
  isPreviewMode?: boolean;
  onPreviewModeToggle?: (isPreviewMode: boolean) => void;
  isSaving?: boolean;
  layoutOrientation?: 'horizontal' | 'vertical';
  onLayoutOrientationChange?: (orientation: 'horizontal' | 'vertical') => void;
}

export const WorkflowBuilder: React.FC<WorkflowBuilderProps> = ({
  workflow,
  onSave,
  onValidate,
  readOnly = false,
  className = '',
  showGrid = true,
  onGridToggle,
  snapToGrid = false,
  onSnapToGridToggle,
  gridSize = 20,
  isPreviewMode = false,
  onPreviewModeToggle,
  isSaving = false,
  layoutOrientation = 'vertical',
  onLayoutOrientationChange
}) => {
  const [nodes, setNodes, onNodesChangeOriginal] = useNodesState<Node>([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState<Edge>([]);
  const [selectedNode, setSelectedNode] = useState<Node | null>(null);
  const { confirm, ConfirmationDialog } = useConfirmation();

  // Undo/Redo history
  const {
    canUndo,
    canRedo,
    pushState,
    undo: historyUndo,
    redo: historyRedo,
    getHistoryStats
  } = useWorkflowHistory(nodes, edges);

  // Execution state tracking via WebSocket
  const {
    executionState,
    isExecuting
  } = useWorkflowExecution(workflow?.id);

  const [isConfigPanelOpen, setIsConfigPanelOpen] = useState(false);
  const [validationResult, setValidationResult] = useState<{
    valid: boolean;
    errors: string[];
    warnings: string[];
  } | null>(null);
  const [isArranging, setIsArranging] = useState(false);

  // Track original workflow data to detect changes
  const [originalNodes, setOriginalNodes] = useState<Node[]>([]);
  const [originalEdges, setOriginalEdges] = useState<Edge[]>([]);
  const [hasChanges, setHasChanges] = useState(false);

  // Chat functionality state
  const [isChatOpen, setIsChatOpen] = useState(false);
  const [chatNodeId, setChatNodeId] = useState<string | null>(null);
  const [operationsAgent, setOperationsAgent] = useState<AiAgent | null>(null);

  // Load operations agent on mount
  useEffect(() => {
    const loadOperationsAgent = async () => {
      try {
        const response = await agentsApi.getAgents({
          status: 'active',
          per_page: 10
        });

        // Extract agent list from paginated response
        const agentList = response?.items || [];

        // Find a suitable operations agent (prefer one with 'operations' or 'assistant' in the name)
        const operationsAgentCandidate = agentList.find((agent: AiAgent) =>
          agent.name?.toLowerCase().includes('operations') ||
          agent.name?.toLowerCase().includes('assistant') ||
          agent.name?.toLowerCase().includes('node')
        ) || agentList[0]; // Fallback to first available agent

        if (operationsAgentCandidate) {
          setOperationsAgent(operationsAgentCandidate);
        }
        // No operations agent available - chat feature will be disabled
      } catch (_error) {
        // Operations agent failed to load - chat feature will be disabled
      }
    };

    loadOperationsAgent();
  }, []);

  // Snap to grid utility function - snaps nodes by their top-left corner
  const snapToGridPosition = useCallback((position: { x: number; y: number }) => {
    return snapToGridUtil(position, snapToGrid, gridSize);
  }, [snapToGrid, gridSize]);

  // Custom node change handler that applies snap-to-grid
  const onNodesChange = useCallback((changes: NodeChange<Node>[]) => {
    if (snapToGrid) {
      // Apply snap-to-grid to position changes
      const modifiedChanges = changes.map((change) => {
        if (change.type === 'position' && change.position) {
          const snappedPosition = snapToGridPosition(change.position);
          return {
            ...change,
            position: snappedPosition
          } as NodeChange<Node>;
        }
        return change;
      });
      onNodesChangeOriginal(modifiedChanges);
    } else {
      onNodesChangeOriginal(changes);
    }

    // Mark as changed when nodes are modified
    setHasChanges(true);
  }, [onNodesChangeOriginal, snapToGrid, snapToGridPosition]);

  // Use extracted node types (memoized to prevent Handle component errors)
  const nodeTypes = useMemo(() => NODE_TYPES, []);

  // Use extracted edge types
  const edgeTypes = useMemo(() => EDGE_TYPES, []);

  // Use extracted default edge options
  const defaultEdgeOptions = useMemo(() => DEFAULT_EDGE_OPTIONS, []);

  // React Flow instance for coordinate transformations
  const reactFlowInstance = useRef<ReactFlowInstance | null>(null);

  // Helper function to check if workflow data has changed
  const checkForChanges = useCallback((currentNodes: Node[], currentEdges: Edge[]) => {
    if (originalNodes.length === 0 && originalEdges.length === 0) {
      // No original data to compare against
      setHasChanges(false);
      return;
    }

    // Compare nodes - check if count, positions, or data changed
    if (currentNodes.length !== originalNodes.length) {
      setHasChanges(true);
      return;
    }

    // Deep comparison of nodes
    const nodesChanged = currentNodes.some((node, index) => {
      const originalNode = originalNodes[index];
      if (!originalNode || node.id !== originalNode.id) return true;

      // Check position changes
      if (node.position.x !== originalNode.position.x || node.position.y !== originalNode.position.y) return true;

      // Check data changes (shallow comparison for performance)
      if (JSON.stringify(node.data) !== JSON.stringify(originalNode.data)) return true;

      return false;
    });

    // Compare edges
    if (currentEdges.length !== originalEdges.length) {
      setHasChanges(true);
      return;
    }

    const edgesChanged = currentEdges.some((edge, index) => {
      const originalEdge = originalEdges[index];
      if (!originalEdge || edge.id !== originalEdge.id) return true;
      if (edge.source !== originalEdge.source || edge.target !== originalEdge.target) return true;
      if (JSON.stringify(edge.data) !== JSON.stringify(originalEdge.data)) return true;
      return false;
    });

    setHasChanges(nodesChanged || edgesChanged);
  }, [originalNodes, originalEdges]);

  // Track the workflow ID we've initialized to prevent re-initialization after save
  const initializedWorkflowIdRef = useRef<string | null>(null);

  // Initialize nodes and edges from workflow data
  useEffect(() => {
    if (workflow) {
      // Skip re-initialization if we already initialized this workflow
      // This prevents canvas reset after save when workflow prop is updated
      // Note: We check the ref only, not nodes.length, to avoid re-running during auto-arrange
      if (initializedWorkflowIdRef.current === workflow.id) {
        return;
      }

      // Handle workflow with nodes and edges
      if (workflow.nodes && workflow.edges) {
        // Check for duplicate node_ids in source data
        const nodeIds = workflow.nodes.map(n => n.node_id);
        const duplicateNodeIds = nodeIds.filter((id, index) => nodeIds.indexOf(id) !== index);
        if (duplicateNodeIds.length > 0) {
          // Duplicate nodes detected - will be deduplicated below
        }
        // Track used IDs to prevent duplicates
        const usedNodeIds = new Set<string>();
        
        const reactFlowNodes: Node[] = workflow.nodes
          .filter(node => node.node_id && node.node_type) // Filter out invalid nodes
          .map((node, index) => {
            // Ensure unique ID
            let nodeId = node.node_id || `fallback-node-${index}-${Date.now()}`;
            let counter = 0;
            while (usedNodeIds.has(nodeId)) {
              nodeId = `${node.node_id || 'fallback-node'}-${index}-${counter++}-${Date.now()}`;
            }
            usedNodeIds.add(nodeId);

            // Extract position - handle both formats:
            // Backend uses position_x/position_y columns, but save response may use position object
            const extendedNode = node as ExtendedWorkflowNode;
            const positionX = Number(node.position_x) || Number(extendedNode.position?.x) || 0;
            const positionY = Number(node.position_y) || Number(extendedNode.position?.y) || 0;

            return {
              id: nodeId,
              type: node.node_type,
              position: {
                x: positionX,
                y: positionY
              },
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
                // Per-handle positions from top-level, or use defaults
                // Check both top-level and inside metadata for handlePositions (saved inside metadata)
                handlePositions: node.handlePositions || node.metadata?.handlePositions || getDefaultHandlePositions(
                  node.node_type,
                  node.is_start_node || node.node_type === 'start' || node.node_type === 'trigger',
                  node.is_end_node || node.node_type === 'end'
                )
              }
            };
          });

        // Track used edge IDs to prevent duplicates
        const usedEdgeIds = new Set<string>();

        const reactFlowEdges: Edge[] = workflow.edges
          .filter(edge => edge.source_node_id && edge.target_node_id) // Filter out invalid edges
          .map((edge, index) => {
            // Ensure unique edge ID
            let edgeId = edge.edge_id || `edge-${edge.source_node_id}-${edge.target_node_id}-${index}`;
            let counter = 0;
            while (usedEdgeIds.has(edgeId)) {
              edgeId = `${edge.edge_id || 'edge'}-${edge.source_node_id}-${edge.target_node_id}-${index}-${counter++}-${Date.now()}`;
            }
            usedEdgeIds.add(edgeId);

            // Use 'conditional' type for edges from true/false handles (condition nodes)
            // This provides animated green/red styling for decision branches
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
            animated: false, // ConditionalEdge has its own animation
            // Migrate obsolete handle IDs to new utilitarian IDs
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
              // Store source handle for edge color lookup
              sourceHandle: migratedSourceHandle,
            },
          };
          });

        // Ensure no duplicate nodes before setting state
        const uniqueNodes = reactFlowNodes.filter((node, index, arr) =>
          arr.findIndex(n => n.id === node.id) === index
        );

        // Debug: Check if we had to remove duplicates
        if (reactFlowNodes.length !== uniqueNodes.length) {
          // Duplicates were removed to ensure node uniqueness
        }

        // Ensure no duplicate edges before setting state
        const uniqueEdges = reactFlowEdges.filter((edge, index, arr) =>
          arr.findIndex(e => e.id === edge.id) === index
        );

        // Debug: Check if we had to remove duplicate edges
        if (reactFlowEdges.length !== uniqueEdges.length) {
          // Duplicate edges were removed to ensure edge uniqueness
        }

        setNodes(uniqueNodes);
        setEdges(uniqueEdges);

        // Store original data for change detection
        setOriginalNodes([...reactFlowNodes]);
        setOriginalEdges([...reactFlowEdges]);
        setHasChanges(false);

        // Track that we've initialized this workflow
        initializedWorkflowIdRef.current = workflow.id;
      } else {
        // Initialize empty workflow with clean slate
        setNodes([]);
        setEdges([]);
        setOriginalNodes([]);
        setOriginalEdges([]);
        setHasChanges(false);
        initializedWorkflowIdRef.current = workflow.id;
      }
    }
  }, [workflow, setNodes, setEdges]);

  // Initialize start/end flags for new nodes only (preserves user selections)
  useEffect(() => {
    if (workflow && nodes.length > 0) {
      const nodesNeedingInitialization = nodes.filter(node => {
        // Only initialize flags for nodes that don't have them set yet
        const hasFlags = ('is_start_node' in node.data) && ('is_end_node' in node.data);
        return !hasFlags;
      });

      if (nodesNeedingInitialization.length > 0) {
        setNodes((currentNodes) =>
          currentNodes.map(node => {
            // Only set flags for nodes that need initialization
            const needsInitialization = !('is_start_node' in node.data) || !('is_end_node' in node.data);

            if (needsInitialization) {
              const isStartNodeType = node.data.node_type === 'trigger' || node.data.node_type === 'start';
              const isEndNodeType = node.data.node_type === 'end';

              return {
                ...node,
                data: {
                  ...node.data,
                  is_start_node: isStartNodeType,
                  is_end_node: isEndNodeType
                }
              };
            }

            return node;
          })
        );
      }
    }
  }, [workflow?.id, setNodes]); // Run when workflow changes

  // Effect to check for changes whenever nodes or edges change
  useEffect(() => {
    checkForChanges(nodes, edges);
  }, [nodes, edges, checkForChanges]);

  // Handle new connections with arrow markers
  const onConnect = useCallback(
    (params: Connection) => {
      if (readOnly) return;

      // Validate connection: prevent connections TO start/trigger nodes
      const targetNode = nodes.find(n => n.id === params.target);
      if (targetNode) {
        const targetType = targetNode.type || '';
        const targetData = targetNode.data as Record<string, unknown> | undefined;
        if (targetType === 'start' || targetType === 'trigger' || targetData?.isStartNode === true) {
          // Start nodes cannot have incoming connections
          return;
        }
      }

      // Validate connection: prevent connections FROM end nodes
      const sourceNode = nodes.find(n => n.id === params.source);
      if (sourceNode) {
        const sourceType = sourceNode.type || '';
        const sourceData = sourceNode.data as Record<string, unknown> | undefined;
        if (sourceType === 'end' || sourceData?.isEndNode === true) {
          // End nodes cannot have outgoing connections
          return;
        }
      }

      const migratedSourceHandle = migrateHandleId(params.sourceHandle, true);
      // Use conditional edge type for true/false handles (from condition nodes)
      const isConditionalEdge = migratedSourceHandle === 'true' ||
                                migratedSourceHandle === 'false';
      const newEdge = {
        ...params,
        ...defaultEdgeOptions,
        id: generateUniqueEdgeId(`${params.source}-${params.target}`),
        type: isConditionalEdge ? 'conditional' : defaultEdgeOptions.type,
        animated: false, // ConditionalEdge has its own animation
        // Migrate handle IDs to ensure consistency
        sourceHandle: migratedSourceHandle,
        targetHandle: migrateHandleId(params.targetHandle, false),
        // Store source handle in data for edge component lookup
        data: {
          sourceHandle: migratedSourceHandle,
        },
      };

      setEdges((eds) => addEdge(newEdge as Edge, eds));
    },
    [setEdges, readOnly, defaultEdgeOptions, nodes]
  );

  // Handle node selection
  const onNodeClick = useCallback((event: React.MouseEvent, node: Node) => {
    if (readOnly || isPreviewMode) return;

    // Check if the click was on a menu button or dropdown element
    const target = event.target as HTMLElement;
    const isMenuClick = target.closest('[data-dropdown-trigger], [data-menu-item], button, [role="button"]');

    // Don't open config panel if clicking on menu buttons or interactive elements
    if (isMenuClick) {
      return;
    }

    setSelectedNode(node);
    setIsConfigPanelOpen(true);
  }, [readOnly, isPreviewMode]);

  // Handle adding new nodes
  const onAddNode = useCallback((nodeType: string, position: { x: number; y: number }) => {
    if (readOnly) return;

    // Triggers and Start nodes are automatically start nodes
    const isStartNodeType = nodeType === 'trigger' || nodeType === 'start';

    // Check if we already have a start node when adding a trigger or start node
    if (isStartNodeType) {
      const existingStartNodes = nodes.filter(node => node.data?.is_start_node);
      if (existingStartNodes.length > 0) {
        confirm({
          title: 'Multiple Start Nodes',
          message: 'A start node already exists. Adding another start node will create multiple entry points. Continue?',
          confirmLabel: 'Add Anyway',
          variant: 'warning',
          onConfirm: async () => {
            addNodeToCanvas(nodeType, position, isStartNodeType);
          }
        });
        return;
      }
    }

    addNodeToCanvas(nodeType, position, isStartNodeType);
  }, [readOnly, nodes, confirm]);

  const addNodeToCanvas = useCallback((nodeType: string, position: { x: number; y: number }, isStartNodeType: boolean) => {

    setNodes((currentNodes) => {
      // Generate unique ID that doesn't conflict with existing nodes
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
          is_start_node: isStartNodeType,
          is_end_node: nodeType === 'end'
        }
      };

      return [...currentNodes, newNode];
    });
  }, [setNodes]);

  // Handle drag and drop from node palette
  const onDragOver = useCallback((event: React.DragEvent) => {
    event.preventDefault();
    event.dataTransfer.dropEffect = 'move';
  }, []);

  const onDrop = useCallback((event: React.DragEvent) => {
    event.preventDefault();

    if (readOnly) return;

    const nodeType = event.dataTransfer.getData('application/reactflow');

    if (nodeType) {
      // Convert screen coordinates to flow coordinates accounting for zoom and pan
      // Get position using the React Flow instance
      const rawPosition = reactFlowInstance.current
        ? reactFlowInstance.current.screenToFlowPosition({
            x: event.clientX,
            y: event.clientY,
          })
        : { x: event.clientX, y: event.clientY };

      // Apply snap-to-grid if enabled
      const position = snapToGridPosition(rawPosition);

      onAddNode(nodeType, position);
    }
  }, [readOnly, onAddNode, snapToGridPosition]);

  // Handle clicks on the React Flow pane (canvas) to ensure dropdowns close
  const onPaneClick = useCallback(() => {
    // Click on the pane should trigger the document click listeners to close dropdowns
    // This is a no-op handler, but ensures the click event propagates properly
  }, []);

  // Handle node updates from config panel
  const onUpdateNode = useCallback((nodeId: string, updates: Partial<NodeDataWithHandles>) => {
    // Check if handle positions are changing
    const currentNode = nodes.find(n => n.id === nodeId);
    const newPositions = updates.handlePositions;
    const currentData = currentNode?.data as NodeDataWithHandles | undefined;
    const currentPositions = currentData?.handlePositions;

    // Deep compare positions to check if they changed
    const positionsChanging = newPositions && JSON.stringify(newPositions) !== JSON.stringify(currentPositions);

    // If positions are changing, we need to remount the node to rebuild handles
    if (positionsChanging && currentNode) {
      const affectedEdges = edges.filter(edge => edge.source === nodeId || edge.target === nodeId);

      // Prepare updated node - handlePositions comes directly from updates
      const updatedNode = {
        ...currentNode,
        data: {
          ...currentNode.data,
          ...updates,
          handlePositions: updates.handlePositions,
          is_start_node: currentNode.data.is_start_node || currentNode.data.node_type === 'trigger' || currentNode.data.node_type === 'start',
          is_end_node: currentNode.data.is_end_node || currentNode.data.node_type === 'end',
        }
      };

      // Step 1: Remove the node and its edges to force React Flow to rebuild
      setNodes((nds) => nds.filter(n => n.id !== nodeId));
      setEdges((eds) => eds.filter(e => e.source !== nodeId && e.target !== nodeId));

      // Step 2: Re-add the node after React Flow processes the removal
      setTimeout(() => {
        setNodes((nds) => [...nds, updatedNode]);

        // Step 3: Re-add edges after node is mounted with new handle positions
        setTimeout(() => {
          const rebuiltEdges = affectedEdges.map(edge => {
            const migratedSourceHandle = migrateHandleId(edge.sourceHandle, true);
            return {
              ...edge,
              id: generateUniqueEdgeId(`${edge.source}-${edge.target}`),
              // Preserve all edge properties including type, style, markers
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
      // Normal update without handle position change
      setNodes((nds) =>
        nds.map((node) => {
          if (node.id === nodeId) {
            const updatedData = { ...node.data, ...updates };

            // Automatically set start/end flags based on node type
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

  // Handle workflow validation
  const handleValidate = useCallback(async () => {
    if (onValidate) {
      const result = await onValidate(nodes, edges);
      setValidationResult(result);
      return result;
    }
    return { valid: true, errors: [], warnings: [] };
  }, [nodes, edges, onValidate]);

  // Handle workflow save
  const handleSave = useCallback(async () => {
    // Validate first
    const validation = await handleValidate();
    if (!validation.valid) {
      return;
    }

    // Convert React Flow nodes/edges back to workflow format (using snake_case for backend)
     
    const workflowNodes: any[] = nodes.map(node => {
      const isStartNode = Boolean(node.data.is_start_node || node.data.node_type === 'trigger' || node.data.node_type === 'start');
      const isEndNode = Boolean(node.data.is_end_node || node.data.node_type === 'end');

      const savedNode = {
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
          // Preserve per-handle positions for proper display after save/reload
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

      return savedNode;
    });

     
    const workflowEdges: any[] = edges.map(edge => ({
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
  }, [nodes, edges, onSave, handleValidate, validationResult]);

  // Auto-arrange nodes with optional orientation override
  const handleArrange = useCallback((orientationOverride?: 'horizontal' | 'vertical') => {
    if (nodes.length === 0) {
      return;
    }

    setIsArranging(true);

    // Use setTimeout to ensure UI updates showing the loading state
    setTimeout(() => {
      try {
        // Use orientation override if provided, otherwise use current preference
        const orientation = orientationOverride || layoutOrientation;
        const layoutOptions = getLayoutOptions(orientation);

        // Calculate new positions for all nodes
        const arrangedNodes = autoArrangeNodes(nodes, edges, layoutOptions);

        // Apply grid snapping to all arranged nodes
        const snappedArrangedNodes = arrangedNodes.map(node => ({
          ...node,
          position: snapToGridPosition(node.position)
        }));

        // Build a position lookup map for quick access
        const nodePositions = new Map<string, { x: number; y: number }>();
        snappedArrangedNodes.forEach(node => {
          nodePositions.set(node.id, node.position);
        });
        // Also include original positions for nodes not in arrangedNodes
        nodes.forEach(node => {
          if (!nodePositions.has(node.id)) {
            nodePositions.set(node.id, node.position);
          }
        });

        // Build handle positions for each node based on its connections
        const calculateNodeHandlePositions = (nodeId: string, nodeData: BaseWorkflowNodeData): HandlePositions => {
          const nodeType = nodeData.node_type || 'default';
          const isStart = nodeData.is_start_node || nodeType === 'start' || nodeType === 'trigger';
          const isEnd = nodeData.is_end_node || nodeType === 'end';

          // Start with default positions
          const positions = getDefaultHandlePositions(nodeType, isStart, isEnd);
          const nodePos = nodePositions.get(nodeId);

          if (!nodePos) return positions;

          // Find all edges connected to this node
          const outgoingEdges = edges.filter(e => e.source === nodeId);
          const incomingEdges = edges.filter(e => e.target === nodeId);

          // Calculate optimal positions for output handles based on where targets are
          outgoingEdges.forEach(edge => {
            const targetPos = nodePositions.get(edge.target);
            if (targetPos && edge.sourceHandle) {
              const handleId = edge.sourceHandle;
              if (positions[handleId] !== undefined) {
                positions[handleId] = calculateOptimalSide(nodePos, targetPos, true);
              }
            }
          });

          // Calculate optimal positions for input handles based on where sources are
          incomingEdges.forEach(edge => {
            const sourcePos = nodePositions.get(edge.source);
            if (sourcePos && edge.targetHandle) {
              const handleId = edge.targetHandle;
              if (positions[handleId] !== undefined) {
                positions[handleId] = calculateOptimalSide(sourcePos, nodePos, false);
              }
            }
          });

          // For nodes without connections, use layout-appropriate defaults
          if (outgoingEdges.length === 0 && incomingEdges.length === 0) {
            if (orientation === 'horizontal') {
              // Swap top/bottom with left/right for horizontal layout
              const horizontalPositions: HandlePositions = {};
              for (const [handleId, position] of Object.entries(positions)) {
                if (position === 'top') horizontalPositions[handleId] = 'left';
                else if (position === 'bottom') horizontalPositions[handleId] = 'right';
                else if (position === 'left') horizontalPositions[handleId] = 'top';
                else if (position === 'right') horizontalPositions[handleId] = 'bottom';
                else horizontalPositions[handleId] = position;
              }
              return horizontalPositions;
            }
          }

          return positions;
        };

        // Apply handle positions to all arranged nodes
        const arrangedNodesWithHandles = snappedArrangedNodes.map(node => ({
          ...node,
          data: {
            ...node.data,
            handlePositions: calculateNodeHandlePositions(node.id, node.data),
            positionsUpdated: Date.now()
          }
        }));

        // Ensure ALL nodes in the workflow get the positions update, even if not rearranged
        const allNodesWithPositions = nodes.map(originalNode => {
          const arrangedNode = arrangedNodesWithHandles.find(an => an.id === originalNode.id);

          if (arrangedNode) {
            return arrangedNode;
          } else {
            return {
              ...originalNode,
              data: {
                ...originalNode.data,
                handlePositions: calculateNodeHandlePositions(originalNode.id, originalNode.data),
                positionsUpdated: Date.now()
              }
            };
          }
        });

        // Store current edges for regeneration
        const currentEdges = edges;

        // Step 1: Remove all nodes and edges to force React Flow to rebuild everything
        setNodes([]);
        setEdges([]);

        // Step 2: Re-add nodes with new positions and handle positions after React Flow processes removal
        setTimeout(() => {
          setNodes(allNodesWithPositions);

          // Step 3: Re-add edges after nodes have fully mounted with new handle positions
          setTimeout(() => {
            const rebuiltEdges = currentEdges.map(edge => {
              const migratedSourceHandle = migrateHandleId(edge.sourceHandle, true);
              return {
                ...edge,
                // Generate new ID to ensure fresh edge rendering
                id: generateUniqueEdgeId(`${edge.source}-${edge.target}`),
                // Preserve all edge properties
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
            setEdges(rebuiltEdges);

            // Mark as changed since we modified positions
            setHasChanges(true);

            // Step 4: Fit view after everything is fully rendered
            setTimeout(() => {
              if (reactFlowInstance.current) {
                reactFlowInstance.current.fitView({
                  padding: 0.2,
                  duration: 800
                });
              }
            }, 100); // Wait for edges to render before fitting view
          }, 100); // Wait for nodes to mount before adding edges
        }, 50); // Wait for React Flow to process removal
      } catch (_error) {
        // Error arranging nodes - layout will not be applied
      } finally {
        setIsArranging(false);
      }
    }, 100);
  }, [nodes, edges, setNodes]);

  // Reset to saved state
  const handleReset = useCallback(() => {
    if (!hasChanges) return;

    confirm({
      title: 'Reset Workflow',
      message: 'Are you sure you want to reset to the last saved state? All unsaved changes will be lost.',
      confirmLabel: 'Reset',
      variant: 'warning',
      onConfirm: async () => {
        // Restore original nodes and edges
        setNodes([...originalNodes]);
        setEdges([...originalEdges]);

        // Clear selection
        setSelectedNode(null);
        setIsConfigPanelOpen(false);

        // Reset change tracking
        setHasChanges(false);
      }
    });
  }, [hasChanges, originalNodes, originalEdges, setNodes, setEdges, confirm]);

  // Chat functionality handlers
  const handleOpenChat = useCallback((nodeId: string) => {
    const node = nodes.find(n => n.id === nodeId);
    if (node) {
      setChatNodeId(nodeId);
      setIsChatOpen(true);
    }
  }, [nodes]);

  const handleCloseChat = useCallback(() => {
    setIsChatOpen(false);
    setChatNodeId(null);
  }, []);

  const handleNodeUpdateFromChat = useCallback((nodeId: string, updates: Partial<AiWorkflowNode>) => {
    // Update the node with the changes from the chat
    setNodes(currentNodes =>
      currentNodes.map(node =>
        node.id === nodeId
          ? { ...node, data: { ...node.data, ...updates } }
          : node
      )
    );
    setHasChanges(true);
  }, [setNodes]);

  // Undo/Redo handlers
  const handleUndo = useCallback(() => {
    const previousState = historyUndo();
    if (previousState) {
      setNodes(previousState.nodes);
      setEdges(previousState.edges);
      setHasChanges(true);
    }
  }, [historyUndo, setNodes, setEdges]);

  const handleRedo = useCallback(() => {
    const nextState = historyRedo();
    if (nextState) {
      setNodes(nextState.nodes);
      setEdges(nextState.edges);
      setHasChanges(true);
    }
  }, [historyRedo, setNodes, setEdges]);

  // Track changes and push to history
  // CRITICAL FIX: Use a ref to track if node changes are from execution updates
  // to prevent execution status updates from flooding the history
  const isExecutionUpdate = useRef(false);
  const lastNodeHash = useRef<string>('');

  useEffect(() => {
    // Skip history updates during execution status changes
    if (isExecutionUpdate.current) {
      isExecutionUpdate.current = false;
      return;
    }

    // Skip if we're currently executing
    if (isExecuting) {
      return;
    }

    // Create a hash of node data to detect actual changes (exclude execution status fields)
    const nodeDataHash = nodes.map(n => ({
      id: n.id,
      position: n.position,
      // Exclude execution-related fields from hash
      data: {
        ...n.data,
        executionStatus: undefined,
        executionDuration: undefined,
        executionError: undefined
      }
    }));
    const currentHash = JSON.stringify(nodeDataHash) + JSON.stringify(edges);

    // Only push if data actually changed (not just execution status)
    if (currentHash !== lastNodeHash.current && (nodes.length > 0 || edges.length > 0)) {
      const timeoutId = setTimeout(() => {
        pushState(nodes, edges, 'Workflow change');
        lastNodeHash.current = currentHash;
      }, 500); // Debounce history updates

      return () => clearTimeout(timeoutId);
    }
  }, [nodes, edges, pushState, isExecuting]);

  // Update node data with execution status
  useEffect(() => {
    if (Object.keys(executionState).length > 0) {
      // Mark that this is an execution update to prevent history push
      isExecutionUpdate.current = true;

      setNodes(currentNodes =>
        currentNodes.map(node => ({
          ...node,
          data: {
            ...node.data,
            executionStatus: executionState[node.id]?.status,
            executionDuration: executionState[node.id]?.duration,
            executionError: executionState[node.id]?.error
          }
        }))
      );
    }
  }, [executionState, setNodes]);

  // Keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (readOnly) return;

      if ((event.ctrlKey || event.metaKey) && event.key === 's') {
        event.preventDefault();
        handleSave();
      }

      // Undo/Redo shortcuts
      if ((event.ctrlKey || event.metaKey) && event.key === 'z' && !event.shiftKey) {
        event.preventDefault();
        handleUndo();
      }

      if ((event.ctrlKey || event.metaKey) && (event.key === 'y' || (event.key === 'z' && event.shiftKey))) {
        event.preventDefault();
        handleRedo();
      }

      if (event.key === 'Delete' && selectedNode) {
        setNodes((nds) => nds.filter((node) => node.id !== selectedNode.id));
        setEdges((eds) => eds.filter((edge) =>
          edge.source !== selectedNode.id && edge.target !== selectedNode.id
        ));
        setSelectedNode(null);
        setIsConfigPanelOpen(false);
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [readOnly, selectedNode, setNodes, setEdges, handleSave, handleUndo, handleRedo]);

  const miniMapStyle = {
    backgroundColor: 'var(--color-surface)',
    border: '1px solid var(--color-border)'
  };

  const workflowContextValue = {
    onOpenChat: handleOpenChat,
    operationsAgent,
    workflowId: workflow?.id,
    onNodeUpdate: handleNodeUpdateFromChat
  };

  return (
    <WorkflowProvider value={workflowContextValue}>
      <div className={`h-full w-full relative ${className}`} style={{ minHeight: '500px' }}>
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onConnect={onConnect}
        onNodeClick={onNodeClick}
        onPaneClick={onPaneClick}
        onDrop={onDrop}
        onDragOver={onDragOver}
        onInit={(instance) => {
          reactFlowInstance.current = instance;
        }}
        // Type assertions needed due to @xyflow/react's strict typing with custom node/edge components
        nodeTypes={nodeTypes as typeof NODE_TYPES}
        edgeTypes={edgeTypes as typeof EDGE_TYPES}
        defaultEdgeOptions={defaultEdgeOptions as typeof DEFAULT_EDGE_OPTIONS}
        connectionLineType={ConnectionLineType.Bezier}
        connectionLineStyle={{
          stroke: 'var(--color-border, #94a3b8)',
          strokeWidth: 2,
        }}
        attributionPosition="bottom-left"
        className="bg-theme-background"
        fitViewOptions={{
          padding: 0.2,
          maxZoom: 1.5,
          minZoom: 0.1,
        }}
        onError={(_id, _error) => {
          // ReactFlow error occurred - error ID and details logged internally
        }}
      >
        {showGrid && (
          <Background
            variant={BackgroundVariant.Dots}
            gap={gridSize}
            size={2}
            color="var(--color-border, #d1d5db)"
          />
        )}
        
        <Controls 
          className="bg-theme-surface border border-theme"
          showInteractive={!readOnly}
        />
        
        <MiniMap 
          style={miniMapStyle}
          nodeColor="var(--color-primary-500)"
          maskColor="rgba(0, 0, 0, 0.1)"
        />

        {!readOnly && (
          <Panel position="top-left">
            <div className="flex items-center gap-2">
              <WorkflowToolbar
                onSave={handleSave}
                onValidate={handleValidate}
                validationResult={validationResult}
                hasChanges={hasChanges}
                isSaving={isSaving}
                showGrid={showGrid}
                onGridToggle={onGridToggle}
                snapToGrid={snapToGrid}
                onSnapToGridToggle={onSnapToGridToggle}
                isPreviewMode={isPreviewMode}
                onPreviewModeToggle={onPreviewModeToggle}
                onArrange={handleArrange}
                isArranging={isArranging}
                onReset={handleReset}
                layoutOrientation={layoutOrientation}
                onLayoutOrientationChange={onLayoutOrientationChange}
              />
              <HistoryControls
                canUndo={canUndo}
                canRedo={canRedo}
                onUndo={handleUndo}
                onRedo={handleRedo}
                historySize={getHistoryStats().size}
                currentIndex={getHistoryStats().currentIndex}
                className="ml-2 bg-theme-surface border border-theme rounded-lg px-2 py-1"
              />
            </div>
          </Panel>
        )}

        {!readOnly && !isPreviewMode && (
          <Panel position="top-right">
            <NodePalette onAddNode={onAddNode} />
          </Panel>
        )}

        {/* Execution Statistics Panel */}
        {Object.keys(executionState).length > 0 && (
          <Panel position="bottom-right">
            <ExecutionStats
              totalNodes={nodes.length}
              completedNodes={Object.values(executionState).filter(s => s.status === 'success').length}
              failedNodes={Object.values(executionState).filter(s => s.status === 'error').length}
              totalDuration={Object.values(executionState).reduce((sum, s) => sum + (s.duration || 0), 0)}
              className="min-w-64"
            />
          </Panel>
        )}

        {/* Empty State Message - Centered */}
        {nodes.length === 0 && (
          <div className="absolute inset-0 flex items-center justify-center pointer-events-none z-10">
            <div className="bg-theme-surface border border-theme rounded-lg p-8 text-center shadow-lg max-w-md pointer-events-auto">
              <div className="flex flex-col items-center gap-4">
                <div className="w-16 h-16 bg-theme-interactive-primary/10 rounded-full flex items-center justify-center">
                  <Workflow className="h-8 w-8 text-theme-interactive-primary" />
                </div>
                <div>
                  <h3 className="text-lg font-semibold text-theme-primary">Start Building Your Workflow</h3>
                  <p className="text-sm text-theme-secondary mt-2 leading-relaxed">
                    Drag nodes from the palette on the right to begin designing your workflow
                  </p>
                </div>
              </div>
            </div>
          </div>
        )}
      </ReactFlow>

      {/* Node Configuration Panel */}
      {!readOnly && !isPreviewMode && isConfigPanelOpen && selectedNode && (
        <NodeConfigPanel
          node={selectedNode}
          onUpdate={onUpdateNode}
          onClose={() => {
            setIsConfigPanelOpen(false);
            setSelectedNode(null);
          }}
        />
      )}

      {/* Node Operations Chat */}
      {isChatOpen && chatNodeId && workflow && (() => {
        const reactFlowNode = nodes.find(n => n.id === chatNodeId);
        const currentNode = reactFlowNode ? {
          ...reactFlowNode.data,
          id: reactFlowNode.id
        } as AiWorkflowNode : undefined;

        return currentNode ? (
          <NodeOperationsChat
            isOpen={isChatOpen}
            onClose={handleCloseChat}
            operationsAgent={operationsAgent || undefined}
            currentNode={currentNode}
            workflowId={workflow.id}
          />
        ) : null;
      })()}
      {ConfirmationDialog}
      </div>
    </WorkflowProvider>
  );
};

// Main component with ReactFlowProvider
export const WorkflowBuilderProvider: React.FC<WorkflowBuilderProps> = (props) => {
  return (
    <ReactFlowProvider>
      <WorkflowBuilder {...props} />
    </ReactFlowProvider>
  );
};