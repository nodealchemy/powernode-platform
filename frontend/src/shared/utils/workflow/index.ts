// Workflow Utilities - Barrel Export
// Re-exports from modular files for convenience

// Performance utilities
export {
  isDeepEqual,
  createNodeMap,
  createEdgeMap,
  createEdgesBySourceMap,
  createEdgesByTargetMap,
  haveNodesChanged,
  haveEdgesChanged,
  debounce,
  throttle,
  batchUpdates,
  scheduleSequentialUpdates
} from '@/shared/utils/workflow/performance-utils';

// Graph utilities
export {
  sortNodesByType,
  sortNodesInExecutionOrder,
  getNodeExecutionLevels,
  formatNodeType,
  getNodeTypeVariant
} from '@/shared/utils/workflow/graph-utils';

// Edge validation utilities
export {
  validateEdgeConnection,
  validateWorkflowEdges,
  getMaxOutgoingConnections,
  getMaxIncomingConnections
} from '@/shared/utils/workflow/edge-validation-utils';

// Types
export type {
  EdgeValidationResult,
  NodeForValidation,
  EdgeForValidation
} from '@/shared/utils/workflow/edge-validation-utils';
