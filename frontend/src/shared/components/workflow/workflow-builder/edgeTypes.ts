// Custom Edge Components
import { ConditionalEdge } from '../edges/ConditionalEdge';
import { CurvedEdge } from '../edges/CurvedEdge';
import { ColoredEdge } from '../edges/ColoredEdge';

// Edge types mapping for React Flow
export const EDGE_TYPES = {
  default: ColoredEdge, // Color-coded edges based on handle type
  colored: ColoredEdge, // Explicit colored edge
  conditional: ConditionalEdge, // Dashed conditional edge with label
  bezier: CurvedEdge,
  curved: CurvedEdge,
} as const;

// Default edge options - ColoredEdge handles styling based on handle type
export const DEFAULT_EDGE_OPTIONS = {
  type: 'default', // Uses ColoredEdge component for color-coded edges
  animated: false,
  markerEnd: {
    type: 'arrowclosed' as const,
    width: 8,
    height: 8,
  },
} as const;
