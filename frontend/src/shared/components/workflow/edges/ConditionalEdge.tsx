import {
  EdgeProps,
  getStraightPath,
  EdgeLabelRenderer,
  BaseEdge,
  MarkerType
} from '@xyflow/react';

export interface ConditionalEdgeData {
  conditionType?: string;
  conditionValue?: any;
  edgeType?: string;
  metadata?: Record<string, any>;
}

export const ConditionalEdge = ({
  id: _id,
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

  const pathParams = {
    sourceX,
    sourceY,
    targetX,
    targetY
  } as any;

  if (sourcePosition) pathParams.sourcePosition = sourcePosition;
  if (targetPosition) pathParams.targetPosition = targetPosition;

  const [edgePath, labelX, labelY] = getStraightPath(pathParams);

  const getConditionLabel = () => {
    if (edgeData.conditionType && edgeData.conditionValue !== undefined) {
      return `${edgeData.conditionType}: ${edgeData.conditionValue}`;
    }
    if (edgeData.edgeType && edgeData.edgeType !== 'default') {
      return edgeData.edgeType.toUpperCase() || 'IF';
    }
    return 'IF';
  };

  const getConditionColor = () => {
    if (edgeData.edgeType) {
      switch (edgeData.edgeType) {
        case 'success':
          return 'bg-theme-success border-theme-success text-white';
        case 'error':
          return 'bg-theme-danger border-theme-danger text-white';
        case 'conditional':
        default:
          return 'bg-theme-info border-theme-info text-white';
      }
    }
    return 'bg-theme-info border-theme-info text-white';
  };

  return (
    <>
      <BaseEdge
        path={edgePath}
        markerEnd={markerEnd || MarkerType.ArrowClosed}
        className={`
          transition-all duration-200
          ${selected 
            ? 'stroke-theme-interactive-primary stroke-2' 
            : 'stroke-blue-500 hover:stroke-blue-600 stroke-2'
          }
        `}
        style={{
          strokeDasharray: '5,5',
          animation: 'dash 1s linear infinite'
        }}
      />
      
      <EdgeLabelRenderer>
        <div
          style={{
            position: 'absolute',
            transform: `translate(-50%, -50%) translate(${labelX}px,${labelY}px)`,
            pointerEvents: 'all',
          }}
          className="nodrag nopan"
        >
          <div className={`
            px-2 py-1 rounded text-xs font-medium border shadow-sm whitespace-nowrap
            ${getConditionColor()}
            ${selected ? 'ring-2 ring-theme-interactive-primary ring-offset-1' : ''}
            transition-all duration-200 hover:shadow-md
          `}>
            {getConditionLabel()}
          </div>
        </div>
      </EdgeLabelRenderer>
    </>
  );
};