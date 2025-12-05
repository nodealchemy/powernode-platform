import React from 'react';
import { Handle, Position } from '@xyflow/react';

interface NodeHandlesProps {
  nodeColor?: string;
  isStartNode?: boolean;
  isEndNode?: boolean;
}

/**
 * Provides handles on all four sides of a node for smart connection routing
 * React Flow will automatically choose the closest connection points
 */
export const NodeHandles: React.FC<NodeHandlesProps> = ({
  nodeColor = 'bg-theme-interactive-primary',
  isStartNode = false,
  isEndNode = false
}) => {
  const handleClass = `w-3 h-3 ${nodeColor} border-2 border-theme-surface transition-all hover:scale-125`;

  return (
    <>
      {/* Top Handle - Target */}
      {!isStartNode && (
        <Handle
          type="target"
          position={Position.Top}
          id="t-top"
          className={handleClass}
          style={{ top: -6 }}
        />
      )}

      {/* Bottom Handle - Source */}
      {!isEndNode && (
        <Handle
          type="source"
          position={Position.Bottom}
          id="s-bottom"
          className={handleClass}
          style={{ bottom: -6 }}
        />
      )}

      {/* Left Handle - Target */}
      {!isStartNode && (
        <Handle
          type="target"
          position={Position.Left}
          id="t-left"
          className={handleClass}
          style={{ left: -6 }}
        />
      )}

      {/* Right Handle - Source */}
      {!isEndNode && (
        <Handle
          type="source"
          position={Position.Right}
          id="s-right"
          className={handleClass}
          style={{ right: -6 }}
        />
      )}
    </>
  );
};

/**
 * Specialized handles for start nodes (only source handles)
 */
export const StartNodeHandles: React.FC<{ nodeColor?: string }> = ({
  nodeColor = 'bg-theme-success'
}) => {
  const handleClass = `w-3 h-3 ${nodeColor} border-2 border-theme-surface transition-all hover:scale-125`;

  return (
    <>
      <Handle
        type="source"
        position={Position.Bottom}
        id="s-bottom"
        className={handleClass}
        style={{ bottom: -6 }}
      />
      <Handle
        type="source"
        position={Position.Right}
        id="s-right"
        className={handleClass}
        style={{ right: -6 }}
      />
    </>
  );
};

/**
 * Specialized handles for end nodes (only target handles)
 */
export const EndNodeHandles: React.FC<{ nodeColor?: string }> = ({
  nodeColor = 'bg-theme-danger'
}) => {
  const handleClass = `w-3 h-3 ${nodeColor} border-2 border-theme-surface transition-all hover:scale-125`;

  return (
    <>
      <Handle
        type="target"
        position={Position.Top}
        id="t-top"
        className={handleClass}
        style={{ top: -6 }}
      />
      <Handle
        type="target"
        position={Position.Left}
        id="t-left"
        className={handleClass}
        style={{ left: -6 }}
      />
    </>
  );
};