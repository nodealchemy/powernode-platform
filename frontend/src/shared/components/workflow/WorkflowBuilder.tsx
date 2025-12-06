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
  ReactFlowInstance
} from '@xyflow/react';
import { Workflow } from 'lucide-react';
import '@xyflow/react/dist/style.css';
import { autoArrangeNodes, getOptimalLayoutOptions } from '@/shared/utils/workflowLayout';
import { useWorkflowHistory } from '@/shared/hooks/useWorkflowHistory';
import { useWorkflowExecution } from '@/shared/hooks/useWorkflowExecution';
import { HistoryControls } from './HistoryControls';
import { ExecutionStats } from './ExecutionOverlay';

// Custom Node Components
import { StartNode } from './nodes/StartNode';
import { EndNode } from './nodes/EndNode';
import { AiAgentNode } from './nodes/AiAgentNode';
import { ApiCallNode } from './nodes/ApiCallNode';
import { ConditionNode } from './nodes/ConditionNode';
import { TriggerNode } from './nodes/TriggerNode';
import { TransformNode } from './nodes/TransformNode';
import { LoopNode } from './nodes/LoopNode';
import { DelayNode } from './nodes/DelayNode';
import { HumanApprovalNode } from './nodes/HumanApprovalNode';
import { SubWorkflowNode } from './nodes/SubWorkflowNode';
import { MergeNode } from './nodes/MergeNode';
import { SplitNode } from './nodes/SplitNode';
import { WebhookNode } from './nodes/WebhookNode';
// Data Manipulation Nodes
import { DatabaseNode } from './nodes/DatabaseNode';
import { EmailNode } from './nodes/EmailNode';
import { FileNode } from './nodes/FileNode';
import { ValidatorNode } from './nodes/ValidatorNode';
// AI-Specific Nodes
import { PromptTemplateNode } from './nodes/PromptTemplateNode';
import { DataProcessorNode } from './nodes/DataProcessorNode';
// Integration Nodes
import { SchedulerNode } from './nodes/SchedulerNode';
import { NotificationNode } from './nodes/NotificationNode';
// Knowledge Base Article Management Nodes
import { KbArticleCreateNode } from './nodes/KbArticleCreateNode';
import { KbArticleReadNode } from './nodes/KbArticleReadNode';
import { KbArticleUpdateNode } from './nodes/KbArticleUpdateNode';
import { KbArticleSearchNode } from './nodes/KbArticleSearchNode';
import { KbArticlePublishNode } from './nodes/KbArticlePublishNode';
// Page Content Management Nodes
import { PageCreateNode } from './nodes/PageCreateNode';
import { PageReadNode } from './nodes/PageReadNode';
import { PageUpdateNode } from './nodes/PageUpdateNode';
import { PagePublishNode } from './nodes/PagePublishNode';
// MCP (Model Context Protocol) Nodes
import { McpToolNode } from './nodes/McpToolNode';
import { McpResourceNode } from './nodes/McpResourceNode';
import { McpPromptNode } from './nodes/McpPromptNode';

// Custom Edge Components
import { ConditionalEdge } from './edges/ConditionalEdge';
import { CurvedEdge } from './edges/CurvedEdge';

// Components
import { NodePalette } from './NodePalette';
import { NodeConfigPanel } from './NodeConfigPanel';
import { WorkflowToolbar } from './WorkflowToolbar';
import { NodeOperationsChat } from './NodeOperationsChat';
import { WorkflowProvider } from './WorkflowContext';

import { AiWorkflow, AiWorkflowNode } from '@/shared/types/workflow';
import { AiAgent } from '@/shared/types/ai';
import { agentsApi } from '@/shared/services/ai';

// Helper function to generate absolutely unique edge IDs
const generateUniqueEdgeId = (baseId: string = 'edge'): string => {
  return `${baseId}-${Date.now()}-${Math.random().toString(36).substr(2, 9)}-${performance.now().toString(36)}`;
};


export interface WorkflowBuilderProps {
  workflow?: AiWorkflow;
  onSave: (workflowData: {
    nodes: any[];
    edges: any[];
    configuration: Record<string, any>;
  }) => void;
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
        } else {
        }
      } catch (error) {
        console.error('[WorkflowBuilder] Failed to load operations agent:', error);
      }
    };

    loadOperationsAgent();
  }, []);

  // Snap to grid utility function - snaps nodes by their top-left corner
  const snapToGridPosition = useCallback((position: { x: number; y: number }) => {
    if (!snapToGrid) return position;

    return {
      x: Math.round(position.x / gridSize) * gridSize,
      y: Math.round(position.y / gridSize) * gridSize
    };
  }, [snapToGrid, gridSize]);

  // Custom node change handler that applies snap-to-grid
  const onNodesChange = useCallback((changes: NodeChange[]) => {
    if (snapToGrid) {
      // Apply snap-to-grid to position changes
      const modifiedChanges = changes.map((change: NodeChange) => {
        if (change.type === 'position' && change.position) {
          const snappedPosition = snapToGridPosition(change.position);
          return {
            ...change,
            position: snappedPosition
          };
        }
        return change;
      });
      onNodesChangeOriginal(modifiedChanges as any);
    } else {
      onNodesChangeOriginal(changes as any);
    }

    // Mark as changed when nodes are modified
    setHasChanges(true);
  }, [onNodesChangeOriginal, snapToGrid, snapToGridPosition]);

  // Memoized node types to prevent Handle component errors
  const nodeTypes = useMemo(() => ({
    // Core Flow Nodes
    start: StartNode,
    end: EndNode,
    trigger: TriggerNode,
    condition: ConditionNode,
    loop: LoopNode,
    delay: DelayNode,
    merge: MergeNode,
    split: SplitNode,
    // AI & Processing Nodes
    ai_agent: AiAgentNode,
    prompt_template: PromptTemplateNode,
    data_processor: DataProcessorNode,
    transform: TransformNode,
    // Data Operations Nodes
    database: DatabaseNode,
    file: FileNode,
    validator: ValidatorNode,
    // Communication Nodes
    email: EmailNode,
    notification: NotificationNode,
    // Integration Nodes
    api_call: ApiCallNode,
    webhook: WebhookNode,
    scheduler: SchedulerNode,
    // Process Nodes
    human_approval: HumanApprovalNode,
    sub_workflow: SubWorkflowNode,
    // Knowledge Base Article Management
    kb_article_create: KbArticleCreateNode,
    kb_article_read: KbArticleReadNode,
    kb_article_update: KbArticleUpdateNode,
    kb_article_search: KbArticleSearchNode,
    kb_article_publish: KbArticlePublishNode,
    // Page Content Management
    page_create: PageCreateNode,
    page_read: PageReadNode,
    page_update: PageUpdateNode,
    page_publish: PagePublishNode,
    // MCP (Model Context Protocol) Nodes
    mcp_tool: McpToolNode,
    mcp_resource: McpResourceNode,
    mcp_prompt: McpPromptNode,
  }), []);

  // Memoized edge types for custom edge components
  const edgeTypes = useMemo(() => ({
    conditional: ConditionalEdge, // Original conditional edge
    bezier: CurvedEdge,
    curved: CurvedEdge,
  }), []);

  // Default edge options with standard curves
  const defaultEdgeOptions = useMemo(() => ({
    type: 'default', // Use default React Flow edge type
    animated: false,
    style: {
      strokeWidth: 2,
      stroke: '#94a3b8', // theme-secondary color
    },
    markerEnd: {
      type: 'arrowclosed' as const,
      width: 8,
      height: 8,
      color: '#94a3b8',
    },
    labelStyle: {
      fill: '#64748b',
      fontSize: 12,
    },
    labelBgStyle: {
      fill: '#ffffff',
      fillOpacity: 0.8,
    },
  }), []);

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

  // Initialize nodes and edges from workflow data
  useEffect(() => {
    if (workflow) {
      // Handle workflow with nodes and edges
      if (workflow.nodes && workflow.edges) {
        // Check for duplicate node_ids in source data
        const nodeIds = workflow.nodes.map(n => n.node_id);
        const _duplicateNodeIds = nodeIds.filter((id, index) => nodeIds.indexOf(id) !== index);
        if (_duplicateNodeIds.length > 0) {
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

            // Extract position from separate columns (backend uses position_x and position_y)
            const positionX = Number(node.position_x) || 0;
            const positionY = Number(node.position_y) || 0;

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
                // Restore handle orientation from saved metadata
                handleOrientation: node.metadata?.handleOrientation || 'vertical'
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

            return {
            id: edgeId,
            source: edge.source_node_id,
            target: edge.target_node_id,
            type: edge.is_conditional ? 'conditional' : 'default',
            animated: edge.is_conditional || false,
            // Explicitly set handle IDs to ensure proper connections - use 'default' for compatibility
            sourceHandle: 'default', // Backend doesn't store handle IDs
            targetHandle: 'default', // Backend doesn't store handle IDs
            style: {
              strokeWidth: 2,
              stroke: edge.is_conditional ? '#f59e0b' : '#94a3b8', // Orange for conditional, gray for normal
            },
            markerEnd: {
              type: 'arrowclosed' as const,
              width: 8,
              height: 8,
              color: edge.is_conditional ? '#f59e0b' : '#94a3b8',
            },
            data: {
              condition_type: edge.condition_type,
              condition_value: edge.condition_value,
              metadata: edge.metadata || {},
              edge_type: edge.edge_type || 'default'
            },
            label: edge.condition_type ? `${edge.condition_type}: ${edge.condition_value}` : undefined
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
      } else {
        // Initialize empty workflow with clean slate
        setNodes([]);
        setEdges([]);
        setOriginalNodes([]);
        setOriginalEdges([]);
        setHasChanges(false);
      }
    }
  }, [workflow, setNodes, setEdges]);

  // Initialize start/end flags for new nodes only (preserves user selections)
  useEffect(() => {
    if (workflow && nodes.length > 0) {
      const nodesNeedingInitialization = nodes.filter(node => {
        // Only initialize flags for nodes that don't have them set yet
        const hasFlags = node.data.hasOwnProperty('is_start_node') && node.data.hasOwnProperty('is_end_node');
        return !hasFlags;
      });

      if (nodesNeedingInitialization.length > 0) {
        setNodes((currentNodes) =>
          currentNodes.map(node => {
            // Only set flags for nodes that need initialization
            const needsInitialization = !node.data.hasOwnProperty('is_start_node') || !node.data.hasOwnProperty('is_end_node');

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

      const newEdge = {
        ...params,
        ...defaultEdgeOptions,
        id: generateUniqueEdgeId(`${params.source}-${params.target}`),
        // Force handle IDs if not provided - use 'default' for compatibility with backend
        sourceHandle: params.sourceHandle || 'default',
        targetHandle: params.targetHandle || 'default',
      };

      setEdges((eds) => addEdge(newEdge as any, eds));
    },
    [setEdges, readOnly, defaultEdgeOptions]
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
        const confirmAdd = window.confirm(
          'A start node already exists. Adding another start node will create multiple entry points. Continue?'
        );
        if (!confirmAdd) return;
      }
    }

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
          is_start_node: nodeType === 'trigger' || nodeType === 'start',
          is_end_node: nodeType === 'end'
        }
      };

      return [...currentNodes, newNode];
    });
  }, [readOnly, nodes]);

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
  const onUpdateNode = useCallback((nodeId: string, updates: Partial<Node['data']>) => {
    // Check if orientation is changing
    const currentNode = nodes.find(n => n.id === nodeId);
    const newOrientation = (updates as any).metadata?.handleOrientation;
    const currentOrientation = (currentNode?.data as any)?.metadata?.handleOrientation || (currentNode?.data as any)?.handleOrientation;
    const orientationChanging = newOrientation && newOrientation !== currentOrientation;

    // If orientation is changing, we need to remount the node to rebuild handles
    if (orientationChanging && currentNode) {
      const affectedEdges = edges.filter(edge => edge.source === nodeId || edge.target === nodeId);

      // Prepare updated node
      const updatedNode = {
        ...currentNode,
        data: {
          ...currentNode.data,
          ...updates,
          handleOrientation: newOrientation,
          is_start_node: currentNode.data.is_start_node || currentNode.data.node_type === 'trigger' || currentNode.data.node_type === 'start',
          is_end_node: currentNode.data.is_end_node || currentNode.data.node_type === 'end',
        }
      };

      // Extract orientation from metadata if present
      if ((updatedNode.data as any).metadata?.handleOrientation) {
        (updatedNode.data as any).handleOrientation = (updatedNode.data as any).metadata.handleOrientation;
      }

      // Step 1: Remove the node and its edges to force React Flow to rebuild
      setNodes((nds) => nds.filter(n => n.id !== nodeId));
      setEdges((eds) => eds.filter(e => e.source !== nodeId && e.target !== nodeId));

      // Step 2: Re-add the node after React Flow processes the removal
      setTimeout(() => {
        setNodes((nds) => [...nds, updatedNode]);

        // Step 3: Re-add edges after node is mounted with new handle positions
        setTimeout(() => {
          const rebuiltEdges = affectedEdges.map(edge => ({
            ...edge,
            id: generateUniqueEdgeId(`${edge.source}-${edge.target}`),
            // Preserve all edge properties including type, style, markers
            type: edge.type,
            animated: edge.animated,
            style: edge.style,
            markerEnd: edge.markerEnd,
            label: edge.label,
            data: edge.data,
            sourceHandle: edge.sourceHandle || 'default',
            targetHandle: edge.targetHandle || 'default',
          }));
          setEdges((eds) => [...eds, ...rebuiltEdges]);
        }, 100);
      }, 50);
    } else {
      // Normal update without orientation change
      setNodes((nds) =>
        nds.map((node) => {
          if (node.id === nodeId) {
            const updatedData = { ...node.data, ...updates };

            // Automatically set start/end flags based on node type
            if (updatedData.node_type) {
              updatedData.is_start_node = updatedData.is_start_node || updatedData.node_type === 'trigger' || updatedData.node_type === 'start';
              updatedData.is_end_node = updatedData.is_end_node || updatedData.node_type === 'end';
            }

            // Extract handleOrientation from metadata and put it directly in data for easy access
            if ((updatedData as any).metadata?.handleOrientation) {
              (updatedData as any).handleOrientation = (updatedData as any).metadata.handleOrientation;
            } else if ((updates as any).metadata?.handleOrientation) {
              (updatedData as any).handleOrientation = (updates as any).metadata.handleOrientation;
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
      const isStartNode = node.data.is_start_node || node.data.node_type === 'trigger' || node.data.node_type === 'start';
      const isEndNode = node.data.is_end_node || node.data.node_type === 'end';

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
          // Preserve handle orientation for proper display after save/reload
          handleOrientation: node.data.handleOrientation || 'vertical'
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
      source_handle: edge.sourceHandle || 'default',
      target_handle: edge.targetHandle || 'default',
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
        // Get optimal layout options based on workflow size
        const layoutOptions = getOptimalLayoutOptions(nodes.length, edges.length);

        // Use orientation override if provided, otherwise use current preference
        const orientation = orientationOverride || layoutOrientation;
        // 'vertical' = top-to-bottom flow (TB), 'horizontal' = left-to-right flow (LR)
        layoutOptions.direction = orientation === 'horizontal' ? 'LR' : 'TB';

        // Optimize spacing configuration based on orientation
        if (orientation === 'horizontal') {
          // For horizontal (LR) flow: optimize for left-to-right reading
          // Increase vertical spacing between rows (ranksep) for better vertical separation
          // Decrease horizontal spacing (nodesep) for more compact horizontal flow
          layoutOptions.ranksep = (layoutOptions.ranksep || 60) * 1.5; // More vertical space between columns
          layoutOptions.nodesep = (layoutOptions.nodesep || 50) * 0.8; // Less horizontal space between nodes
          layoutOptions.nodeWidth = 200; // Slightly narrower nodes for horizontal flow
          layoutOptions.nodeHeight = 140; // Slightly taller nodes for better readability
        } else {
          // For vertical (TB) flow: optimize for top-to-bottom reading
          // Increase horizontal spacing between columns (nodesep) for better horizontal separation
          // Increase vertical spacing (ranksep) for better visual separation between rows
          layoutOptions.nodesep = (layoutOptions.nodesep || 50) * 1.2; // More horizontal space between columns
          layoutOptions.ranksep = (layoutOptions.ranksep || 60) * 2.0; // More vertical space between rows (120px)
          layoutOptions.nodeWidth = 220; // Standard width for vertical flow
          layoutOptions.nodeHeight = 120; // Standard height for vertical flow
        }

        // Get default canvas dimensions for centering (canvas can expand beyond these)
        const defaultCanvasWidth = 1200;
        const defaultCanvasHeight = 800;

        // Calculate new positions for all nodes, centered on default canvas size
        const arrangedNodes = autoArrangeNodes(nodes, edges, layoutOptions, defaultCanvasWidth, defaultCanvasHeight);

        // Apply grid snapping to all arranged nodes and configure handle orientation for ALL nodes
        const snappedArrangedNodes = arrangedNodes.map(node => ({
          ...node,
          position: snapToGridPosition(node.position),
          data: {
            ...node.data,
            // Add handle orientation configuration based on layout direction
            handleOrientation: orientation === 'horizontal' ? 'horizontal' : 'vertical',
            // Force re-render by updating a timestamp when orientation changes
            orientationUpdated: Date.now()
          }
        }));

        // Ensure ALL nodes in the workflow get the orientation update, even if not rearranged
        // This handles nodes that might not have been processed by autoArrangeNodes
        const allNodesWithOrientation = nodes.map(originalNode => {
          // Find the corresponding arranged node
          const arrangedNode = snappedArrangedNodes.find(an => an.id === originalNode.id);

          if (arrangedNode) {
            // Use the arranged node (with new position and orientation)
            return arrangedNode;
          } else {
            // For nodes not processed by arrangement, just update orientation
            return {
              ...originalNode,
              data: {
                ...originalNode.data,
                handleOrientation: orientation === 'horizontal' ? 'horizontal' : 'vertical',
                orientationUpdated: Date.now()
              }
            };
          }
        });

        // Store current edges for regeneration
        const currentEdges = edges;

        // Step 1: Remove all nodes and edges to force React Flow to rebuild everything
        setNodes([]);
        setEdges([]);

        // Step 2: Re-add nodes with new positions and orientations after React Flow processes removal
        setTimeout(() => {
          setNodes(allNodesWithOrientation);

          // Step 3: Re-add edges after nodes have fully mounted with new handle positions
          setTimeout(() => {
            const rebuiltEdges = currentEdges.map(edge => ({
              ...edge,
              // Generate new ID to ensure fresh edge rendering
              id: generateUniqueEdgeId(`${edge.source}-${edge.target}`),
              // Preserve all edge properties
              type: edge.type,
              animated: edge.animated,
              style: edge.style,
              markerEnd: edge.markerEnd,
              label: edge.label,
              data: edge.data,
              sourceHandle: edge.sourceHandle || 'default',
              targetHandle: edge.targetHandle || 'default',
            }));
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
      } catch (error) {
        console.error('Error arranging nodes:', error);
      } finally {
        setIsArranging(false);
      }
    }, 100);
  }, [nodes, edges, setNodes]);

  // Reset to saved state
  const handleReset = useCallback(() => {
    if (!hasChanges) return;

    // Show confirmation dialog
    const confirmed = window.confirm(
      'Are you sure you want to reset to the last saved state? All unsaved changes will be lost.'
    );

    if (confirmed) {
      // Restore original nodes and edges
      setNodes([...originalNodes]);
      setEdges([...originalEdges]);

      // Clear selection
      setSelectedNode(null);
      setIsConfigPanelOpen(false);

      // Reset change tracking
      setHasChanges(false);

      // Preserve saved positions - don't auto-fit view
      // setTimeout(() => {
      //   if (reactFlowInstance.current) {
      //     reactFlowInstance.current.fitView({
      //       padding: 0.2,
      //       duration: 800
      //     });
      //   }
      // }, 100);
    }
  }, [hasChanges, originalNodes, originalEdges, setNodes, setEdges]);

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
        nodeTypes={nodeTypes as any}
        edgeTypes={edgeTypes as any}
        defaultEdgeOptions={defaultEdgeOptions as any}
        connectionLineType={"default" as any}
        connectionLineStyle={{
          stroke: '#94a3b8',
          strokeWidth: 2,
        }}
        attributionPosition="bottom-left"
        className="bg-theme-background"
        fitViewOptions={{
          padding: 0.2,
          maxZoom: 1.5,
          minZoom: 0.1,
        }}
        onError={(id, error) => {
          console.error('ReactFlow error:', id, error);
        }}
      >
        {showGrid && (
          <Background
            variant={BackgroundVariant.Dots}
            gap={gridSize}
            size={2}
            color="#d1d5db"
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