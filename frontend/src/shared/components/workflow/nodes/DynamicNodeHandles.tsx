import React from 'react';
import { Handle, Position } from '@xyflow/react';

interface DynamicNodeHandlesProps {
  nodeType?: string;
  nodeColor?: string;
  isStartNode?: boolean;
  isEndNode?: boolean;
  hasOutboundConnection?: boolean;
  orientation?: 'horizontal' | 'vertical';
}

/**
 * Dynamic handle positioning based on node type
 * Most nodes: 1 input (target) and 1 output (source)
 * Conditional nodes: 1 input and multiple outputs
 * Split nodes: 1 input and multiple outputs
 * Merge nodes: Multiple inputs and 1 output
 */
/**
 * Use SmartNodeHandles for nodes that need flexible positioning
 * Use DynamicNodeHandles for nodes with fixed positioning requirements
 */

export const DynamicNodeHandles: React.FC<DynamicNodeHandlesProps> = ({
  nodeType = 'default',
  nodeColor = 'bg-theme-interactive-primary',
  isStartNode = false,
  isEndNode = false,
  orientation = 'vertical'
}) => {
  // Handle styles - larger size for easier clicking with invisible click area
  const handleClass = `w-4 h-4 ${nodeColor} border-2 border-theme-surface transition-all hover:scale-150 cursor-pointer`;

  // Start nodes - only output (orientation-aware)
  if (isStartNode) {
    return (
      <Handle
        type="source"
        position={orientation === 'horizontal' ? Position.Right : Position.Bottom}
        id="default"
        className={handleClass}
      />
    );
  }

  // End nodes - only input (orientation-aware)
  if (isEndNode) {
    return (
      <Handle
        type="target"
        position={orientation === 'horizontal' ? Position.Left : Position.Top}
        id="default"
        className={handleClass}
      />
    );
  }

  // Conditional nodes - one input, two outputs (true/false branches) - orientation-aware
  if (nodeType === 'condition') {
    if (orientation === 'horizontal') {
      return (
        <>
          {/* Input */}
          <Handle
            type="target"
            position={Position.Left}
            id="default"
            className={handleClass}
          />
          {/* True output */}
          <Handle
            type="source"
            position={Position.Right}
            id="true"
            className={`${handleClass} !bg-theme-success`}
            style={{ top: '30%' }}
          />
          {/* False output */}
          <Handle
            type="source"
            position={Position.Right}
            id="false"
            className={`${handleClass} !bg-theme-danger`}
            style={{ top: '70%' }}
          />
        </>
      );
    } else {
      return (
        <>
          {/* Input */}
          <Handle
            type="target"
            position={Position.Top}
            id="default"
            className={handleClass}
          />
          {/* True output */}
          <Handle
            type="source"
            position={Position.Bottom}
            id="true"
            className={`${handleClass} !bg-theme-success`}
            style={{ left: '30%' }}
          />
          {/* False output */}
          <Handle
            type="source"
            position={Position.Bottom}
            id="false"
            className={`${handleClass} !bg-theme-danger`}
            style={{ left: '70%' }}
          />
        </>
      );
    }
  }

  // Split nodes - one input, multiple outputs (orientation-aware)
  if (nodeType === 'split') {
    if (orientation === 'horizontal') {
      return (
        <>
          {/* Input */}
          <Handle
            type="target"
            position={Position.Left}
            className={handleClass}
          />
          {/* Multiple outputs */}
          <Handle
            type="source"
            position={Position.Right}
            id="out1"
            className={handleClass}
            style={{ top: '25%' }}
          />
          <Handle
            type="source"
            position={Position.Right}
            id="out2"
            className={handleClass}
            style={{ top: '50%' }}
          />
          <Handle
            type="source"
            position={Position.Right}
            id="out3"
            className={handleClass}
            style={{ top: '75%' }}
          />
        </>
      );
    } else {
      return (
        <>
          {/* Input */}
          <Handle
            type="target"
            position={Position.Top}
            className={handleClass}
          />
          {/* Multiple outputs */}
          <Handle
            type="source"
            position={Position.Bottom}
            id="out1"
            className={handleClass}
            style={{ left: '25%' }}
          />
          <Handle
            type="source"
            position={Position.Bottom}
            id="out2"
            className={handleClass}
            style={{ left: '50%' }}
          />
          <Handle
            type="source"
            position={Position.Bottom}
            id="out3"
            className={handleClass}
            style={{ left: '75%' }}
          />
        </>
      );
    }
  }

  // Merge nodes - multiple inputs, one output (orientation-aware)
  if (nodeType === 'merge') {
    if (orientation === 'horizontal') {
      return (
        <>
          {/* Multiple inputs */}
          <Handle
            type="target"
            position={Position.Left}
            id="in1"
            className={handleClass}
            style={{ top: '25%' }}
          />
          <Handle
            type="target"
            position={Position.Left}
            id="in2"
            className={handleClass}
            style={{ top: '50%' }}
          />
          <Handle
            type="target"
            position={Position.Left}
            id="in3"
            className={handleClass}
            style={{ top: '75%' }}
          />
          {/* Output */}
          <Handle
            type="source"
            position={Position.Right}
            className={handleClass}
          />
        </>
      );
    } else {
      return (
        <>
          {/* Multiple inputs */}
          <Handle
            type="target"
            position={Position.Top}
            id="in1"
            className={handleClass}
            style={{ left: '25%' }}
          />
          <Handle
            type="target"
            position={Position.Top}
            id="in2"
            className={handleClass}
            style={{ left: '50%' }}
          />
          <Handle
            type="target"
            position={Position.Top}
            id="in3"
            className={handleClass}
            style={{ left: '75%' }}
          />
          {/* Output */}
          <Handle
            type="source"
            position={Position.Bottom}
            className={handleClass}
          />
        </>
      );
    }
  }

  // Loop nodes - special handling for loop back connection (orientation-aware)
  if (nodeType === 'loop') {
    if (orientation === 'horizontal') {
      return (
        <>
          {/* Main input */}
          <Handle
            type="target"
            position={Position.Left}
            id="input"
            className={handleClass}
            style={{ top: '30%' }}
          />
          {/* Loop input (from loop end) */}
          <Handle
            type="target"
            position={Position.Left}
            id="loop-back"
            className={`${handleClass} !bg-theme-warning`}
            style={{ top: '70%' }}
          />
          {/* Main output (to loop body) */}
          <Handle
            type="source"
            position={Position.Right}
            id="output"
            className={handleClass}
            style={{ top: '30%' }}
          />
          {/* Loop continue output */}
          <Handle
            type="source"
            position={Position.Right}
            id="loop-continue"
            className={`${handleClass} !bg-theme-warning`}
            style={{ top: '70%' }}
          />
        </>
      );
    } else {
      return (
        <>
          {/* Main input */}
          <Handle
            type="target"
            position={Position.Top}
            id="input"
            className={handleClass}
            style={{ left: '30%' }}
          />
          {/* Loop input (from loop end) */}
          <Handle
            type="target"
            position={Position.Top}
            id="loop-back"
            className={`${handleClass} !bg-theme-warning`}
            style={{ left: '70%' }}
          />
          {/* Main output (to loop body) */}
          <Handle
            type="source"
            position={Position.Bottom}
            id="output"
            className={handleClass}
            style={{ left: '30%' }}
          />
          {/* Loop continue output */}
          <Handle
            type="source"
            position={Position.Bottom}
            id="loop-continue"
            className={`${handleClass} !bg-theme-warning`}
            style={{ left: '70%' }}
          />
        </>
      );
    }
  }

  // Default nodes - orientation-aware input/output positioning
  if (orientation === 'horizontal') {
    return (
      <>
        {/* Input on left */}
        <Handle
          type="target"
          position={Position.Left}
          id="default"
          className={handleClass}
        />
        {/* Output on right */}
        <Handle
          type="source"
          position={Position.Right}
          id="default"
          className={handleClass}
        />
      </>
    );
  } else {
    return (
      <>
        {/* Input on top */}
        <Handle
          type="target"
          position={Position.Top}
          id="default"
          className={handleClass}
        />
        {/* Output on bottom */}
        <Handle
          type="source"
          position={Position.Bottom}
          id="default"
          className={handleClass}
        />
      </>
    );
  }
};

