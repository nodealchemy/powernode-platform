import { useMemo } from 'react';
import {
  EdgeProps,
  getSmoothStepPath,
  EdgeLabelRenderer,
} from '@xyflow/react';

export interface ColoredEdgeData {
  conditionType?: string;
  conditionValue?: string;
  edgeType?: string;
  metadata?: Record<string, unknown>;
  sourceHandleType?: string;
  sourceHandle?: string; // Store source handle ID for color lookup
  label?: string;
}

// Edge color configuration based on source handle type
// Uses CSS variables defined in themes.css for theme-awareness
const EDGE_COLORS: Record<string, { strokeVar: string; label: string; bgClass: string }> = {
  // Standard flow
  output: { strokeVar: '--edge-flow', label: 'Flow', bgClass: 'bg-theme-edge-flow' },
  input: { strokeVar: '--edge-flow', label: 'Flow', bgClass: 'bg-theme-edge-flow' },

  // Conditional branches (true/false)
  true: { strokeVar: '--edge-true', label: 'True', bgClass: 'bg-theme-edge-true' },
  false: { strokeVar: '--edge-false', label: 'False', bgClass: 'bg-theme-edge-false' },

  // Loop handles
  body: { strokeVar: '--edge-loop', label: 'Loop', bgClass: 'bg-theme-edge-loop' },
  exit: { strokeVar: '--edge-exit', label: 'Exit', bgClass: 'bg-theme-edge-exit' },
  'loop-back': { strokeVar: '--edge-loop', label: 'Continue', bgClass: 'bg-theme-edge-loop' },

  // Split/branch handles
  'branch-1': { strokeVar: '--edge-branch-1', label: 'Branch 1', bgClass: 'bg-theme-edge-branch-1' },
  'branch-2': { strokeVar: '--edge-branch-2', label: 'Branch 2', bgClass: 'bg-theme-edge-branch-2' },
  'branch-3': { strokeVar: '--edge-branch-3', label: 'Branch 3', bgClass: 'bg-theme-edge-branch-3' },

  // Merge handles
  'merge-1': { strokeVar: '--edge-branch-1', label: 'Merge', bgClass: 'bg-theme-edge-branch-1' },
  'merge-2': { strokeVar: '--edge-branch-2', label: 'Merge', bgClass: 'bg-theme-edge-branch-2' },
  'merge-3': { strokeVar: '--edge-branch-3', label: 'Merge', bgClass: 'bg-theme-edge-branch-3' },

  // Success/Error (from edge type)
  success: { strokeVar: '--edge-success', label: 'Success', bgClass: 'bg-theme-edge-success' },
  error: { strokeVar: '--edge-error', label: 'Error', bgClass: 'bg-theme-edge-error' },

  // Default
  default: { strokeVar: '--edge-default', label: '', bgClass: 'bg-theme-edge-default' },
};

function getEdgeConfig(
  sourceHandle: string | null | undefined,
  edgeType?: string,
  dataSourceHandle?: string
): { strokeVar: string; label: string; bgClass: string } {
  // First check edge type (success/error take precedence)
  if (edgeType && EDGE_COLORS[edgeType]) {
    return EDGE_COLORS[edgeType];
  }

  // Then check source handle from EdgeProps (ReactFlow provides this)
  if (sourceHandle && EDGE_COLORS[sourceHandle]) {
    return EDGE_COLORS[sourceHandle];
  }

  // Fallback: check source handle from edge data (stored when edge was created)
  if (dataSourceHandle && EDGE_COLORS[dataSourceHandle]) {
    return EDGE_COLORS[dataSourceHandle];
  }

  return EDGE_COLORS.default;
}

export const ColoredEdge = ({
  id,
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
  sourceHandleId,
  data,
  selected,
  markerEnd,
}: EdgeProps) => {
  const edgeData = (data || {}) as ColoredEdgeData;
  const edgeConfig = getEdgeConfig(sourceHandleId, edgeData.edgeType, edgeData.sourceHandle);

  // Generate stable unique ID for this edge's SVG definitions
  const animationId = useMemo(() => `colored-edge-${id || 'unknown'}`, [id]);

  // Calculate offset to help edges route around nodes
  // The offset pushes the edge's bend point away from the nodes
  const offset = 50;

  const [edgePath, labelX, labelY] = getSmoothStepPath({
    sourceX,
    sourceY,
    sourcePosition,
    targetX,
    targetY,
    targetPosition,
    borderRadius: 16, // Rounded corners for smoother appearance
    offset, // Distance from node before first bend
  });

  // Determine if we should show a label
  const showLabel = edgeConfig.label && sourceHandleId && sourceHandleId !== 'output';
  const labelText = edgeData.label || edgeConfig.label;

  // Get stroke color for particle effect
  const strokeColor = `var(${edgeConfig.strokeVar})`;

  // Only show animations if we have a valid path
  const hasValidPath = edgePath && edgePath.length > 0;

  return (
    <>
      {/* SVG definitions for glow filter */}
      <defs>
        <filter id={`${animationId}-glow`} x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation="1.5" result="coloredBlur"/>
          <feMerge>
            <feMergeNode in="coloredBlur"/>
            <feMergeNode in="SourceGraphic"/>
          </feMerge>
        </filter>
      </defs>

      {/* Background path for subtle glow effect */}
      <path
        d={edgePath}
        fill="none"
        stroke={strokeColor}
        strokeWidth={selected ? 6 : 4}
        strokeOpacity={selected ? 0.3 : 0.15}
        style={{
          filter: `url(#${animationId}-glow)`,
        }}
      />

      {/* Main edge path */}
      <path
        id={id}
        d={edgePath}
        fill="none"
        stroke={strokeColor}
        strokeWidth={selected ? 3 : 2}
        strokeLinecap="round"
        markerEnd={markerEnd}
        style={{
          transition: 'stroke 0.2s ease, stroke-width 0.2s ease',
        }}
      />

      {/* Animated particles flowing along the edge - only if path is valid */}
      {hasValidPath && (
        <>
          <circle r={selected ? 3.5 : 2.5} fill={strokeColor} opacity={0.9}>
            <animateMotion
              dur="1.5s"
              repeatCount="indefinite"
              path={edgePath}
            />
          </circle>
          <circle r={selected ? 2.5 : 1.5} fill={strokeColor} opacity={0.5}>
            <animateMotion
              dur="1.5s"
              repeatCount="indefinite"
              path={edgePath}
              begin="0.75s"
            />
          </circle>
        </>
      )}

      {showLabel && labelText && (
        <EdgeLabelRenderer>
          <div
            style={{
              position: 'absolute',
              transform: `translate(-50%, -50%) translate(${labelX}px, ${labelY}px)`,
              pointerEvents: 'all',
            }}
            className="nodrag nopan"
          >
            <div
              className={`
                px-2 py-0.5 rounded text-xs font-medium text-white shadow-sm
                ${edgeConfig.bgClass}
                ${selected ? 'ring-2 ring-white ring-offset-1' : ''}
                transition-all duration-200
              `}
            >
              {labelText}
            </div>
          </div>
        </EdgeLabelRenderer>
      )}
    </>
  );
};

export default ColoredEdge;
