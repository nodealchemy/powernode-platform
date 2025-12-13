import React from 'react';
import { Handle, Position } from '@xyflow/react';

/**
 * Handle position options - each handle can be positioned on any side
 */
export type HandlePosition = 'top' | 'bottom' | 'left' | 'right';

/**
 * Map of handle IDs to their positions
 */
export type HandlePositions = Record<string, HandlePosition>;

interface DynamicNodeHandlesProps {
  nodeType?: string;
  isStartNode?: boolean;
  isEndNode?: boolean;
  handlePositions?: HandlePositions;
}

/**
 * Convert HandlePosition to ReactFlow Position enum
 */
const toReactFlowPosition = (pos: HandlePosition): Position => {
  switch (pos) {
    case 'top': return Position.Top;
    case 'bottom': return Position.Bottom;
    case 'left': return Position.Left;
    case 'right': return Position.Right;
  }
};

/**
 * Get default handle positions for each node type
 */
export const getDefaultHandlePositions = (nodeType: string, isStartNode?: boolean, isEndNode?: boolean): HandlePositions => {
  if (isStartNode) {
    return { output: 'bottom' };
  }

  if (isEndNode) {
    return { input: 'top' };
  }

  switch (nodeType) {
    case 'condition':
      return {
        input: 'top',
        true: 'bottom',
        false: 'bottom'
      };
    case 'split':
      return {
        input: 'top',
        'branch-1': 'bottom',
        'branch-2': 'bottom',
        'branch-3': 'bottom'
      };
    case 'merge':
      return {
        'merge-1': 'top',
        'merge-2': 'top',
        'merge-3': 'top',
        output: 'bottom'
      };
    case 'loop':
      return {
        input: 'top',
        'loop-back': 'top',
        body: 'bottom',
        exit: 'bottom'
      };
    default:
      return {
        input: 'top',
        output: 'bottom'
      };
  }
};

/**
 * Handle type as used in ReactFlow Handle component
 * - 'source' = output handle (edges flow OUT from this handle)
 * - 'target' = input handle (edges flow IN to this handle)
 */
export type HandleType = 'source' | 'target';

/**
 * Get handle IDs for a node type (used for config panel)
 * Returns handle info with ReactFlow-compatible type ('source' | 'target')
 */
export const getHandleIdsForNodeType = (nodeType: string, isStartNode?: boolean, isEndNode?: boolean): { id: string; label: string; type: HandleType }[] => {
  if (isStartNode) {
    return [{ id: 'output', label: 'Output', type: 'source' }];
  }

  if (isEndNode) {
    return [{ id: 'input', label: 'Input', type: 'target' }];
  }

  switch (nodeType) {
    case 'condition':
      return [
        { id: 'input', label: 'Input', type: 'target' },
        { id: 'true', label: 'True Output', type: 'source' },
        { id: 'false', label: 'False Output', type: 'source' }
      ];
    case 'split':
      return [
        { id: 'input', label: 'Input', type: 'target' },
        { id: 'branch-1', label: 'Branch 1', type: 'source' },
        { id: 'branch-2', label: 'Branch 2', type: 'source' },
        { id: 'branch-3', label: 'Branch 3', type: 'source' }
      ];
    case 'merge':
      return [
        { id: 'merge-1', label: 'Input 1', type: 'target' },
        { id: 'merge-2', label: 'Input 2', type: 'target' },
        { id: 'merge-3', label: 'Input 3', type: 'target' },
        { id: 'output', label: 'Output', type: 'source' }
      ];
    case 'loop':
      return [
        { id: 'input', label: 'Input', type: 'target' },
        { id: 'loop-back', label: 'Loop Back', type: 'target' },
        { id: 'body', label: 'Body', type: 'source' },
        { id: 'exit', label: 'Exit', type: 'source' }
      ];
    default:
      return [
        { id: 'input', label: 'Input', type: 'target' },
        { id: 'output', label: 'Output', type: 'source' }
      ];
  }
};

/**
 * Check if a position is horizontal (left or right)
 */
const isHorizontalPosition = (pos: HandlePosition): boolean =>
  pos === 'left' || pos === 'right';

/**
 * Get offset style for a handle based on its position in a group sharing the same edge
 * @param position - The edge position (top, bottom, left, right)
 * @param index - The handle's index in the group (0-based)
 * @param total - Total number of handles on this edge
 */
const getOffsetStyle = (position: HandlePosition, index: number, total: number): React.CSSProperties => {
  if (total <= 1) {
    return {}; // Single handle, center it (default behavior)
  }

  // Calculate evenly spaced positions
  // For 2 handles: 33%, 67% (positions at 1/3 and 2/3)
  // For 3 handles: 25%, 50%, 75% (positions at 1/4, 2/4, 3/4)
  // For 4 handles: 20%, 40%, 60%, 80%
  const offset = ((index + 1) / (total + 1)) * 100;

  if (isHorizontalPosition(position)) {
    return { top: `${offset}%` };
  }
  return { left: `${offset}%` };
};

/**
 * Define handle ordering priority for each edge
 * Lower priority = lower percentage position (top for vertical, left for horizontal)
 * Higher priority = higher percentage position (bottom for vertical, right for horizontal)
 */
const getHandlePriority = (handleId: string): number => {
  const priorities: Record<string, number> = {
    // Condition node: false before true (false=top/left, true=bottom/right)
    'false': 0,
    'true': 1,
    // Input handles generally come before outputs when on same edge
    'input': 0,
    // Merge inputs
    'merge-1': 0,
    'merge-2': 1,
    'merge-3': 2,
    // Split branches
    'branch-1': 0,
    'branch-2': 1,
    'branch-3': 2,
    // Loop handles
    'loop-back': 1,
    'body': 0,
    'exit': 1,
    // Default output
    'output': 1
  };
  return priorities[handleId] ?? 0;
};

/**
 * Calculate offset for handles grouped by their edge position
 * Returns a map of handleId -> { index, total } for handles sharing the same edge
 */
const calculateHandleOffsets = (
  handleIds: string[],
  positions: HandlePositions
): Record<string, { index: number; total: number }> => {
  // Group handles by their edge position
  const edgeGroups: Record<HandlePosition, string[]> = {
    top: [],
    bottom: [],
    left: [],
    right: []
  };

  for (const handleId of handleIds) {
    const pos = positions[handleId] || 'bottom';
    edgeGroups[pos].push(handleId);
  }

  // Build offset map
  const offsets: Record<string, { index: number; total: number }> = {};

  for (const edge of Object.keys(edgeGroups) as HandlePosition[]) {
    const handles = edgeGroups[edge];
    // Sort handles by priority (lower priority = lower offset)
    const sortedHandles = [...handles].sort((a, b) => getHandlePriority(a) - getHandlePriority(b));
    sortedHandles.forEach((handleId, index) => {
      offsets[handleId] = { index, total: handles.length };
    });
  }

  return offsets;
};

export const DynamicNodeHandles: React.FC<DynamicNodeHandlesProps> = ({
  nodeType = 'default',
  isStartNode = false,
  isEndNode = false,
  handlePositions
}) => {
  // Handle styles - prominent connection points brought to front
  const handleClass = `w-6 h-6 border-[3px] border-white shadow-lg ring-2 ring-black/20 transition-all hover:scale-150 hover:shadow-xl hover:ring-black/40 cursor-pointer`;

  // Base style with high z-index and default black background
  const baseStyle: React.CSSProperties = { zIndex: 100, backgroundColor: 'var(--handle-default)' };

  // Get positions - merge user overrides with defaults
  const defaults = getDefaultHandlePositions(nodeType, isStartNode, isEndNode);
  const positions = { ...defaults, ...handlePositions };

  // Helper to get position for a handle
  const getPos = (handleId: string): Position =>
    toReactFlowPosition(positions[handleId] || 'bottom');

  // Start nodes - only output
  if (isStartNode) {
    return (
      <Handle
        type="source"
        position={getPos('output')}
        id="output"
        className={handleClass}
        style={baseStyle}
      />
    );
  }

  // End nodes - only input
  if (isEndNode) {
    return (
      <Handle
        type="target"
        position={getPos('input')}
        id="input"
        className={handleClass}
        style={baseStyle}
      />
    );
  }

  // Conditional nodes - one input, two outputs (true/false branches)
  if (nodeType === 'condition') {
    const handleIds = ['input', 'true', 'false'];
    const offsets = calculateHandleOffsets(handleIds, positions);

    return (
      <>
        <Handle
          type="target"
          position={getPos('input')}
          id="input"
          className={handleClass}
          style={{
            ...baseStyle,
            ...getOffsetStyle(positions['input'] || 'top', offsets['input'].index, offsets['input'].total)
          }}
        />
        <Handle
          type="source"
          position={getPos('false')}
          id="false"
          className={handleClass}
          style={{
            ...baseStyle,
            ...getOffsetStyle(positions['false'] || 'bottom', offsets['false'].index, offsets['false'].total),
            backgroundColor: 'var(--handle-false)'
          }}
        />
        <Handle
          type="source"
          position={getPos('true')}
          id="true"
          className={handleClass}
          style={{
            ...baseStyle,
            ...getOffsetStyle(positions['true'] || 'bottom', offsets['true'].index, offsets['true'].total),
            backgroundColor: 'var(--handle-true)'
          }}
        />
      </>
    );
  }

  // Split nodes - one input, multiple outputs
  if (nodeType === 'split') {
    const handleIds = ['input', 'branch-1', 'branch-2', 'branch-3'];
    const offsets = calculateHandleOffsets(handleIds, positions);

    return (
      <>
        <Handle
          type="target"
          position={getPos('input')}
          id="input"
          className={handleClass}
          style={{
            ...baseStyle,
            ...getOffsetStyle(positions['input'] || 'top', offsets['input'].index, offsets['input'].total)
          }}
        />
        <Handle
          type="source"
          position={getPos('branch-1')}
          id="branch-1"
          className={handleClass}
          style={{
            ...baseStyle,
            ...getOffsetStyle(positions['branch-1'] || 'bottom', offsets['branch-1'].index, offsets['branch-1'].total)
          }}
        />
        <Handle
          type="source"
          position={getPos('branch-2')}
          id="branch-2"
          className={handleClass}
          style={{
            ...baseStyle,
            ...getOffsetStyle(positions['branch-2'] || 'bottom', offsets['branch-2'].index, offsets['branch-2'].total)
          }}
        />
        <Handle
          type="source"
          position={getPos('branch-3')}
          id="branch-3"
          className={handleClass}
          style={{
            ...baseStyle,
            ...getOffsetStyle(positions['branch-3'] || 'bottom', offsets['branch-3'].index, offsets['branch-3'].total)
          }}
        />
      </>
    );
  }

  // Merge nodes - multiple inputs, one output
  if (nodeType === 'merge') {
    const handleIds = ['merge-1', 'merge-2', 'merge-3', 'output'];
    const offsets = calculateHandleOffsets(handleIds, positions);

    return (
      <>
        <Handle
          type="target"
          position={getPos('merge-1')}
          id="merge-1"
          className={handleClass}
          style={{
            ...baseStyle,
            ...getOffsetStyle(positions['merge-1'] || 'top', offsets['merge-1'].index, offsets['merge-1'].total)
          }}
        />
        <Handle
          type="target"
          position={getPos('merge-2')}
          id="merge-2"
          className={handleClass}
          style={{
            ...baseStyle,
            ...getOffsetStyle(positions['merge-2'] || 'top', offsets['merge-2'].index, offsets['merge-2'].total)
          }}
        />
        <Handle
          type="target"
          position={getPos('merge-3')}
          id="merge-3"
          className={handleClass}
          style={{
            ...baseStyle,
            ...getOffsetStyle(positions['merge-3'] || 'top', offsets['merge-3'].index, offsets['merge-3'].total)
          }}
        />
        <Handle
          type="source"
          position={getPos('output')}
          id="output"
          className={handleClass}
          style={{
            ...baseStyle,
            ...getOffsetStyle(positions['output'] || 'bottom', offsets['output'].index, offsets['output'].total)
          }}
        />
      </>
    );
  }

  // Loop nodes - special handling for loop back connection
  if (nodeType === 'loop') {
    const handleIds = ['input', 'loop-back', 'body', 'exit'];
    const offsets = calculateHandleOffsets(handleIds, positions);

    return (
      <>
        <Handle
          type="target"
          position={getPos('input')}
          id="input"
          className={handleClass}
          style={{
            ...baseStyle,
            ...getOffsetStyle(positions['input'] || 'top', offsets['input'].index, offsets['input'].total)
          }}
        />
        <Handle
          type="target"
          position={getPos('loop-back')}
          id="loop-back"
          className={handleClass}
          style={{
            ...baseStyle,
            ...getOffsetStyle(positions['loop-back'] || 'top', offsets['loop-back'].index, offsets['loop-back'].total),
            backgroundColor: 'var(--handle-loop-back)'
          }}
        />
        <Handle
          type="source"
          position={getPos('body')}
          id="body"
          className={handleClass}
          style={{
            ...baseStyle,
            ...getOffsetStyle(positions['body'] || 'bottom', offsets['body'].index, offsets['body'].total)
          }}
        />
        <Handle
          type="source"
          position={getPos('exit')}
          id="exit"
          className={handleClass}
          style={{
            ...baseStyle,
            ...getOffsetStyle(positions['exit'] || 'bottom', offsets['exit'].index, offsets['exit'].total),
            backgroundColor: 'var(--handle-loop-exit)'
          }}
        />
      </>
    );
  }

  // Default nodes - one input, one output
  const handleIds = ['input', 'output'];
  const offsets = calculateHandleOffsets(handleIds, positions);

  return (
    <>
      <Handle
        type="target"
        position={getPos('input')}
        id="input"
        className={handleClass}
        style={{
          ...baseStyle,
          ...getOffsetStyle(positions['input'] || 'top', offsets['input'].index, offsets['input'].total)
        }}
      />
      <Handle
        type="source"
        position={getPos('output')}
        id="output"
        className={handleClass}
        style={{
          ...baseStyle,
          ...getOffsetStyle(positions['output'] || 'bottom', offsets['output'].index, offsets['output'].total)
        }}
      />
    </>
  );
};
