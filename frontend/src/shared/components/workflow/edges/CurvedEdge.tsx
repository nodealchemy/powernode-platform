import React from 'react';
import { EdgeProps, getBezierPath } from '@xyflow/react';

export const CurvedEdge: React.FC<EdgeProps> = ({
  id,
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
  style = {},
  markerEnd,
  label,
  labelStyle,
  labelBgStyle,
}) => {
  // Get the bezier path with standard curvature
  const [edgePath, labelX, labelY] = getBezierPath({
    sourceX,
    sourceY,
    sourcePosition,
    targetX,
    targetY,
    targetPosition,
  });

  return (
    <>
      <path
        id={id}
        style={style}
        className="react-flow__edge-path"
        d={edgePath}
        markerEnd={markerEnd}
      />
      {label && (
        <foreignObject
          x={labelX - 40}
          y={labelY - 10}
          width={80}
          height={20}
          className="react-flow__edge-label"
        >
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              height: '100%',
              background: labelBgStyle?.fill || 'var(--color-bg-surface, #ffffff)',
              borderRadius: '3px',
              padding: '2px 6px',
              fontSize: labelStyle?.fontSize || 11,
              color: labelStyle?.fill || 'var(--color-text-secondary, #64748b)',
              opacity: labelBgStyle?.fillOpacity || 0.9,
              boxShadow: '0 1px 2px rgba(0,0,0,0.1)',
            }}
          >
            {label}
          </div>
        </foreignObject>
      )}
    </>
  );
};