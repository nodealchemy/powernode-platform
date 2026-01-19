import { sortNodesInExecutionOrder, getNodeExecutionLevels, formatNodeType } from '../workflowUtils';
import { AiWorkflowNode, AiWorkflowEdge } from '@/shared/types/workflow';

describe('workflowUtils', () => {
  describe('sortNodesInExecutionOrder', () => {
    it('should sort nodes with start node first and end node last', () => {
      const nodes: AiWorkflowNode[] = [
        {
          id: '3',
          node_id: 'node-3',
          name: 'End Node',
          node_type: 'ai_agent',
          description: '',
          position_x: 0,
          position_y: 0,
          configuration: {},
          metadata: {},
          is_end_node: true,
          created_at: '',
          updated_at: ''
        },
        {
          id: '1',
          node_id: 'node-1',
          name: 'Start Node',
          node_type: 'ai_agent',
          description: '',
          position_x: 0,
          position_y: 0,
          configuration: {},
          metadata: {},
          is_start_node: true,
          created_at: '',
          updated_at: ''
        },
        {
          id: '2',
          node_id: 'node-2',
          name: 'Middle Node',
          node_type: 'api_call',
          description: '',
          position_x: 0,
          position_y: 0,
          configuration: {},
          metadata: {},
          created_at: '',
          updated_at: ''
        }
      ];

      const edges: AiWorkflowEdge[] = [
        {
          id: '1',
          edge_id: 'edge-1',
          source_node_id: 'node-1',
          target_node_id: 'node-2',
          metadata: {}
        },
        {
          id: '2',
          edge_id: 'edge-2',
          source_node_id: 'node-2',
          target_node_id: 'node-3',
          metadata: {}
        }
      ];

      const sorted = sortNodesInExecutionOrder(nodes, edges);

      expect(sorted[0].node_id).toBe('node-1'); // Start node first
      expect(sorted[1].node_id).toBe('node-2'); // Middle node
      expect(sorted[2].node_id).toBe('node-3'); // End node last
    });

    it('should handle nodes with no edges', () => {
      const nodes: AiWorkflowNode[] = [
        {
          id: '2',
          node_id: 'node-2',
          name: 'Regular Node',
          node_type: 'ai_agent',
          description: '',
          position_x: 0,
          position_y: 0,
          configuration: {},
          metadata: {},
          created_at: '',
          updated_at: ''
        },
        {
          id: '1',
          node_id: 'node-1',
          name: 'Start Node',
          node_type: 'ai_agent',
          description: '',
          position_x: 0,
          position_y: 0,
          configuration: {},
          metadata: {},
          is_start_node: true,
          created_at: '',
          updated_at: ''
        }
      ];

      const sorted = sortNodesInExecutionOrder(nodes, []);

      expect(sorted[0].is_start_node).toBe(true); // Start nodes should be first
    });

    it('should handle parallel execution paths', () => {
      const nodes: AiWorkflowNode[] = [
        {
          id: '1',
          node_id: 'start',
          name: 'Start',
          node_type: 'ai_agent',
          description: '',
          position_x: 0,
          position_y: 0,
          configuration: {},
          metadata: {},
          is_start_node: true,
          created_at: '',
          updated_at: ''
        },
        {
          id: '2',
          node_id: 'parallel-1',
          name: 'Parallel 1',
          node_type: 'api_call',
          description: '',
          position_x: 0,
          position_y: 0,
          configuration: {},
          metadata: {},
          created_at: '',
          updated_at: ''
        },
        {
          id: '3',
          node_id: 'parallel-2',
          name: 'Parallel 2',
          node_type: 'api_call',
          description: '',
          position_x: 0,
          position_y: 0,
          configuration: {},
          metadata: {},
          created_at: '',
          updated_at: ''
        },
        {
          id: '4',
          node_id: 'merge',
          name: 'Merge',
          node_type: 'merge',
          description: '',
          position_x: 0,
          position_y: 0,
          configuration: {},
          metadata: {},
          is_end_node: true,
          created_at: '',
          updated_at: ''
        }
      ];

      const edges: AiWorkflowEdge[] = [
        {
          id: '1',
          edge_id: 'edge-1',
          source_node_id: 'start',
          target_node_id: 'parallel-1',
          metadata: {}
        },
        {
          id: '2',
          edge_id: 'edge-2',
          source_node_id: 'start',
          target_node_id: 'parallel-2',
          metadata: {}
        },
        {
          id: '3',
          edge_id: 'edge-3',
          source_node_id: 'parallel-1',
          target_node_id: 'merge',
          metadata: {}
        },
        {
          id: '4',
          edge_id: 'edge-4',
          source_node_id: 'parallel-2',
          target_node_id: 'merge',
          metadata: {}
        }
      ];

      const sorted = sortNodesInExecutionOrder(nodes, edges);

      expect(sorted[0].node_id).toBe('start'); // Start node first
      expect(sorted[sorted.length - 1].node_id).toBe('merge'); // Merge node last
      // Parallel nodes should be in the middle (order may vary)
      expect(sorted.slice(1, 3).map(n => n.node_id).sort()).toEqual(['parallel-1', 'parallel-2'].sort());
    });
  });

  describe('getNodeExecutionLevels', () => {
    it('should calculate execution levels correctly', () => {
      const nodes: AiWorkflowNode[] = [
        {
          id: '1',
          node_id: 'node-1',
          name: 'Start',
          node_type: 'ai_agent',
          description: '',
          position_x: 0,
          position_y: 0,
          configuration: {},
          metadata: {},
          is_start_node: true,
          created_at: '',
          updated_at: ''
        },
        {
          id: '2',
          node_id: 'node-2',
          name: 'Middle',
          node_type: 'api_call',
          description: '',
          position_x: 0,
          position_y: 0,
          configuration: {},
          metadata: {},
          created_at: '',
          updated_at: ''
        },
        {
          id: '3',
          node_id: 'node-3',
          name: 'End',
          node_type: 'ai_agent',
          description: '',
          position_x: 0,
          position_y: 0,
          configuration: {},
          metadata: {},
          is_end_node: true,
          created_at: '',
          updated_at: ''
        }
      ];

      const edges: AiWorkflowEdge[] = [
        {
          id: '1',
          edge_id: 'edge-1',
          source_node_id: 'node-1',
          target_node_id: 'node-2',
          metadata: {}
        },
        {
          id: '2',
          edge_id: 'edge-2',
          source_node_id: 'node-2',
          target_node_id: 'node-3',
          metadata: {}
        }
      ];

      const levels = getNodeExecutionLevels(nodes, edges);

      expect(levels.get('node-1')).toBe(0); // Start node at level 0
      expect(levels.get('node-2')).toBe(1); // Middle node at level 1
      expect(levels.get('node-3')).toBe(2); // End node at level 2
    });
  });

  describe('formatNodeType', () => {
    it('should format node types correctly', () => {
      expect(formatNodeType('ai_agent')).toBe('Ai Agent');
      expect(formatNodeType('api_call')).toBe('Api Call');
      expect(formatNodeType('human_approval')).toBe('Human Approval');
      expect(formatNodeType('sub_workflow')).toBe('Sub Workflow');
    });
  });
});