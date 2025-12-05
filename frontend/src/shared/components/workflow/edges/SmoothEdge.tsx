import React from 'react';
import { EdgeProps, getBezierPath } from '@xyflow/react';

/**
 * SmoothEdge - A custom edge with increased bend radius for smoother curves
 */
export const SmoothEdge: React.FC<EdgeProps> = ({
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
  data,
}) => {
  // Calculate the distance between source and target
  const deltaX = Math.abs(targetX - sourceX);
  const deltaY = Math.abs(targetY - sourceY);

  // Increase curvature for smoother bends
  // The curvature factor determines how far the control points are from the nodes
  const curvatureFactor = 0.5; // Increase this for larger bend radius (default is ~0.25)
  const controlPointOffset = Math.max(deltaX, deltaY) * curvatureFactor;

  // Get the bezier path with increased curvature
  const [edgePath, labelX, labelY] = getBezierPath({
    sourceX,
    sourceY,
    sourcePosition,
    targetX,
    targetY,
    targetPosition,
    curvature: controlPointOffset,
  });

  // Determine if this is a conditional edge
  const isConditional = data?.condition_type || data?.is_conditional;

  // Style adjustments for different edge types
  const edgeStyle = {
    ...style,
    stroke: isConditional ? '#f59e0b' : (style.stroke || '#94a3b8'),
    strokeWidth: style.strokeWidth || 2,
    strokeDasharray: data?.isDashed ? '5,5' : undefined,
  };

  return (
    <>
      {/* The actual edge path */}
      <path
        id={id}
        style={edgeStyle}
        className="react-flow__edge-path"
        d={edgePath}
        markerEnd={markerEnd}
      />

      {/* Optional label */}
      {label && (
        <foreignObject
          x={labelX - 50}
          y={labelY - 12}
          width={100}
          height={24}
          className="react-flow__edge-label"
        >
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              height: '100%',
              background: labelBgStyle?.fill || '#ffffff',
              borderRadius: '4px',
              padding: '2px 8px',
              fontSize: labelStyle?.fontSize || 11,
              color: labelStyle?.fill || '#64748b',
              opacity: labelBgStyle?.fillOpacity || 0.95,
              boxShadow: '0 1px 3px rgba(0,0,0,0.15)',
              border: isConditional ? '1px solid #f59e0b' : '1px solid #e2e8f0',
            }}
          >
            {label}
          </div>
        </foreignObject>
      )}

      {/* Interactive path for better click targets */}
      <path
        style={{
          ...edgeStyle,
          strokeWidth: 20,
          stroke: 'transparent',
          fill: 'none',
          cursor: 'pointer',
        }}
        d={edgePath}
        className="react-flow__edge-interaction"
      />
    </>
  );
};