import React from 'react';
import { EdgeProps, getSmoothStepPath } from '@xyflow/react';

/**
 * SmartEdge - An enhanced edge component that routes around nodes
 * Uses smoothstep algorithm with additional offset to avoid overlapping nodes
 */
export const SmartEdge: React.FC<EdgeProps> = ({
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
  data
}) => {
  // Calculate path with smoothstep algorithm
  // The borderRadius and offset help the edge route around nodes
  const [edgePath, labelX, labelY] = getSmoothStepPath({
    sourceX,
    sourceY,
    sourcePosition,
    targetX,
    targetY,
    targetPosition,
    borderRadius: (data?.borderRadius as number) || 12, // Rounded corners
    offset: (data?.offset as number) || 30, // Distance from nodes
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

/**
 * ConditionalSmartEdge - Special variant for conditional edges
 * Shows additional visual indicators for conditional flow
 */
export const ConditionalSmartEdge: React.FC<EdgeProps> = (props) => {
  return (
    <SmartEdge
      {...props}
      data={{
        ...props.data,
        is_conditional: true,
        borderRadius: 16, // Larger radius for conditional edges
        offset: 35, // More offset for visibility
      }}
      style={{
        ...props.style,
        stroke: '#f59e0b',
        strokeWidth: 2.5,
      }}
    />
  );
};