// Workflow builder utilities and constants
export { NODE_TYPES, type NodeTypeKey } from '@/shared/components/workflow/workflow-builder/nodeTypes';
export { EDGE_TYPES, DEFAULT_EDGE_OPTIONS } from '@/shared/components/workflow/workflow-builder/edgeTypes';
export {
  generateUniqueEdgeId,
  migrateHandleId,
  calculateOptimalSide,
  snapToGridPosition
} from '@/shared/components/workflow/workflow-builder/utils';
