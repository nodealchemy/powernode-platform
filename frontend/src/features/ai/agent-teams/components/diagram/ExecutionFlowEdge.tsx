// Custom animated edge for team execution diagram
import {
  getSmoothStepPath,
  EdgeProps,
  EdgeTypes,
  BaseEdge,
} from '@xyflow/react';
import type { ExecutionFlowEdgeData } from './executionDiagramTypes';

const statusStyles = {
  idle: {
    stroke: 'var(--color-text-tertiary)',
    strokeWidth: 1.5,
    opacity: 0.4,
  },
  active: {
    stroke: 'var(--color-info)',
    strokeWidth: 2.5,
    opacity: 1,
  },
  completed: {
    stroke: 'var(--color-success)',
    strokeWidth: 2,
    opacity: 0.8,
  },
  failed: {
    stroke: 'var(--color-danger)',
    strokeWidth: 2,
    opacity: 0.8,
  },
};

function ExecutionFlowEdge({
  id,
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
  data,
}: EdgeProps) {
  const edgeData = data as ExecutionFlowEdgeData | undefined;
  const status = edgeData?.status || 'idle';
  const style = statusStyles[status] || statusStyles.idle;

  const [edgePath] = getSmoothStepPath({
    sourceX,
    sourceY,
    targetX,
    targetY,
    sourcePosition,
    targetPosition,
    borderRadius: 12,
  });

  return (
    <>
      {/* Glow filter for active edges */}
      {status === 'active' && (
        <defs>
          <filter id={`glow-${id}`} x="-20%" y="-20%" width="140%" height="140%">
            <feGaussianBlur stdDeviation="3" result="blur" />
            <feFlood floodColor="var(--color-info)" floodOpacity="0.4" result="color" />
            <feComposite in="color" in2="blur" operator="in" result="glow" />
            <feMerge>
              <feMergeNode in="glow" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>
      )}

      <BaseEdge
        id={id}
        path={edgePath}
        style={{
          stroke: style.stroke,
          strokeWidth: style.strokeWidth,
          opacity: style.opacity,
          filter: status === 'active' ? `url(#glow-${id})` : undefined,
        }}
      />

      {/* Animated dot traveling along path for active edges */}
      {status === 'active' && (
        <circle r="3" fill="var(--color-info)">
          <animateMotion dur="1.5s" repeatCount="indefinite" path={edgePath} />
        </circle>
      )}

      {/* Arrow marker */}
      <defs>
        <marker
          id={`arrow-${id}`}
          viewBox="0 0 10 10"
          refX="8"
          refY="5"
          markerWidth="6"
          markerHeight="6"
          orient="auto-start-reverse"
        >
          <path d="M 0 0 L 10 5 L 0 10 z" fill={style.stroke} opacity={style.opacity} />
        </marker>
      </defs>
    </>
  );
}

export const executionEdgeTypes: EdgeTypes = {
  executionFlow: ExecutionFlowEdge,
};
