// Helper function to generate absolutely unique edge IDs
export const generateUniqueEdgeId = (baseId: string = 'edge'): string => {
  return `${baseId}-${Date.now()}-${Math.random().toString(36).substr(2, 9)}-${performance.now().toString(36)}`;
};

// Migrate obsolete handle IDs to new utilitarian IDs
export const migrateHandleId = (handleId: string | null | undefined, isSource: boolean): string => {
  // Map obsolete IDs to new IDs
  const sourceMap: Record<string, string> = {
    'default': 'output',
    'out1': 'branch-1',
    'out2': 'branch-2',
    'out3': 'branch-3',
    'loop-continue': 'exit',
  };
  const targetMap: Record<string, string> = {
    'default': 'input',
    'in1': 'merge-1',
    'in2': 'merge-2',
    'in3': 'merge-3',
  };

  if (!handleId) {
    return isSource ? 'output' : 'input';
  }

  const map = isSource ? sourceMap : targetMap;
  return map[handleId] || handleId;
};

// Calculate optimal handle position based on relative node positions
export const calculateOptimalSide = (
  sourcePos: { x: number; y: number },
  targetPos: { x: number; y: number },
  isSource: boolean
): 'top' | 'bottom' | 'left' | 'right' => {
  const dx = targetPos.x - sourcePos.x;
  const dy = targetPos.y - sourcePos.y;

  // Determine the dominant direction
  if (Math.abs(dx) > Math.abs(dy)) {
    // Horizontal relationship is stronger
    if (dx > 0) {
      // Target is to the right of source
      return isSource ? 'right' : 'left';
    } else {
      // Target is to the left of source
      return isSource ? 'left' : 'right';
    }
  } else {
    // Vertical relationship is stronger
    if (dy > 0) {
      // Target is below source
      return isSource ? 'bottom' : 'top';
    } else {
      // Target is above source
      return isSource ? 'top' : 'bottom';
    }
  }
};

// Snap position to grid
export const snapToGridPosition = (
  position: { x: number; y: number },
  snapToGrid: boolean,
  gridSize: number
): { x: number; y: number } => {
  if (!snapToGrid) return position;

  return {
    x: Math.round(position.x / gridSize) * gridSize,
    y: Math.round(position.y / gridSize) * gridSize
  };
};
