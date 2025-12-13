import { useMemo } from 'react';
import {
  EdgeProps,
  getSmoothStepPath,
  EdgeLabelRenderer,
  MarkerType
} from '@xyflow/react';

export interface ConditionalEdgeData {
  conditionType?: string;
  conditionValue?: string | number | boolean;
  edgeType?: string;
  metadata?: Record<string, unknown>;
  sourceHandle?: string;
}

export const ConditionalEdge = ({
  id,
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
  data = { conditionType: undefined, conditionValue: undefined, edgeType: undefined, metadata: undefined },
  markerEnd,
  selected
}: EdgeProps) => {
  // Create a properly-typed local variable to work around type inference issues
  const edgeData: ConditionalEdgeData = data || { conditionType: undefined, conditionValue: undefined, edgeType: undefined, metadata: undefined };

  // Generate stable unique ID for this edge's SVG definitions
  const gradientId = useMemo(() => `conditional-edge-${id || 'unknown'}`, [id]);

  const [edgePath, labelX, labelY] = getSmoothStepPath({
    sourceX,
    sourceY,
    targetX,
    targetY,
    sourcePosition,
    targetPosition,
    borderRadius: 16,
    offset: 50,
  });

  // Determine edge type based on source handle or explicit type
  const getEdgeType = (): 'true' | 'false' | 'success' | 'error' | 'conditional' => {
    if (edgeData.sourceHandle === 'true') return 'true';
    if (edgeData.sourceHandle === 'false') return 'false';
    if (edgeData.edgeType === 'success') return 'success';
    if (edgeData.edgeType === 'error') return 'error';
    return 'conditional';
  };

  const edgeType = getEdgeType();

  const getConditionLabel = () => {
    if (edgeData.conditionType && edgeData.conditionValue !== undefined) {
      return `${edgeData.conditionType}: ${edgeData.conditionValue}`;
    }
    // Check for True/False source handle from condition nodes
    if (edgeType === 'true') return '✓ True';
    if (edgeType === 'false') return '✗ False';
    if (edgeType === 'success') return '✓ Success';
    if (edgeType === 'error') return '✗ Error';
    return 'IF';
  };

  // Get colors based on edge type using CSS variables
  const getEdgeColors = () => {
    switch (edgeType) {
      case 'true':
      case 'success':
        return {
          stroke: 'var(--edge-true)',
          labelBg: 'bg-theme-edge-true',
          labelText: 'text-white',
          glow: 'rgba(34, 197, 94, 0.4)', // green glow
          particle: 'rgba(34, 197, 94, 0.8)'
        };
      case 'false':
      case 'error':
        return {
          stroke: 'var(--edge-false)',
          labelBg: 'bg-theme-edge-false',
          labelText: 'text-white',
          glow: 'rgba(239, 68, 68, 0.4)', // red glow
          particle: 'rgba(239, 68, 68, 0.8)'
        };
      default:
        return {
          stroke: 'var(--color-info)',
          labelBg: 'bg-theme-info',
          labelText: 'text-white',
          glow: 'rgba(59, 130, 246, 0.4)', // blue glow
          particle: 'rgba(59, 130, 246, 0.8)'
        };
    }
  };

  const colors = getEdgeColors();

  // Only show animations if we have a valid path
  const hasValidPath = edgePath && edgePath.length > 0;

  return (
    <>
      {/* SVG definitions for gradient and animation */}
      <defs>
        {/* Animated gradient for flow effect */}
        <linearGradient id={gradientId} gradientUnits="userSpaceOnUse" x1={sourceX} y1={sourceY} x2={targetX} y2={targetY}>
          <stop offset="0%" stopColor={colors.stroke} stopOpacity="0.3">
            <animate
              attributeName="offset"
              values="-0.5;1"
              dur="1.5s"
              repeatCount="indefinite"
            />
          </stop>
          <stop offset="50%" stopColor={colors.stroke} stopOpacity="1">
            <animate
              attributeName="offset"
              values="0;1.5"
              dur="1.5s"
              repeatCount="indefinite"
            />
          </stop>
          <stop offset="100%" stopColor={colors.stroke} stopOpacity="0.3">
            <animate
              attributeName="offset"
              values="0.5;2"
              dur="1.5s"
              repeatCount="indefinite"
            />
          </stop>
        </linearGradient>

        {/* Glow filter */}
        <filter id={`${gradientId}-glow`} x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation="2" result="coloredBlur"/>
          <feMerge>
            <feMergeNode in="coloredBlur"/>
            <feMergeNode in="SourceGraphic"/>
          </feMerge>
        </filter>
      </defs>

      {/* Background glow path */}
      <path
        d={edgePath}
        fill="none"
        stroke={colors.glow}
        strokeWidth={selected ? 8 : 6}
        style={{
          filter: `url(#${gradientId}-glow)`,
          opacity: selected ? 0.8 : 0.5
        }}
      />

      {/* Main edge path with dashed animation */}
      <path
        d={edgePath}
        fill="none"
        stroke={colors.stroke}
        strokeWidth={selected ? 3 : 2}
        strokeDasharray="8 4"
        strokeLinecap="round"
        markerEnd={markerEnd || `url(#${MarkerType.ArrowClosed})`}
        style={{
          strokeDashoffset: 0,
          animation: `conditionalEdgeDash 0.8s linear infinite`,
          transition: 'stroke-width 0.2s ease'
        }}
      />

      {/* Animated particles along the path - only if path is valid */}
      {hasValidPath && (
        <>
          <circle r={selected ? 4 : 3} fill={colors.particle}>
            <animateMotion
              dur="2s"
              repeatCount="indefinite"
              path={edgePath}
            />
          </circle>
          <circle r={selected ? 3 : 2} fill={colors.particle} opacity="0.6">
            <animateMotion
              dur="2s"
              repeatCount="indefinite"
              path={edgePath}
              begin="1s"
            />
          </circle>
        </>
      )}

      <EdgeLabelRenderer>
        <div
          style={{
            position: 'absolute',
            transform: `translate(-50%, -50%) translate(${labelX}px,${labelY}px)`,
            pointerEvents: 'all',
          }}
          className="nodrag nopan"
        >
          <div
            className={`
              px-3 py-1.5 rounded-full text-xs font-semibold shadow-lg whitespace-nowrap
              ${colors.labelBg} ${colors.labelText}
              ${selected ? 'ring-2 ring-white ring-offset-2 ring-offset-theme-bg-surface scale-110' : ''}
              transition-all duration-300 hover:shadow-xl hover:scale-105
            `}
            style={{
              boxShadow: selected
                ? `0 4px 20px ${colors.glow}, 0 0 10px ${colors.glow}`
                : `0 2px 10px ${colors.glow}`
            }}
          >
            {getConditionLabel()}
          </div>
        </div>
      </EdgeLabelRenderer>

      {/* Add keyframes style */}
      <style>
        {`
          @keyframes conditionalEdgeDash {
            to {
              stroke-dashoffset: -12;
            }
          }
        `}
      </style>
    </>
  );
};