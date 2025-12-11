import React from 'react';
import { NodeProps } from '@xyflow/react';
import { CheckCircle, XCircle, Settings, OctagonX } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { EndNode as EndNodeType, EndNodeData } from '@/shared/types/workflow';

export const EndNode: React.FC<NodeProps<EndNodeType>> = ({ data = {} as EndNodeData, selected }) => {
  const configuration = data?.configuration || {};
  const endType = configuration.end_trigger || 'success';
  const isSuccess = endType === 'success' || configuration.deployment_approved;
  const isFailure = endType === 'failure' || endType === 'error';

  const getEndIcon = (_type: string) => {
    switch (endType) {
      case 'failure':
      case 'error':
        return <XCircle className="h-4 w-4" />;
      case 'success':
      default:
        return <CheckCircle className="h-4 w-4" />;
    }
  };

  const getEndColor = (_type: string) => {
    // All end nodes use themed end node color for consistency
    return 'bg-node-end';
  };

  const getBorderColor = (_type: string) => {
    // All end nodes use red border for consistency
    return 'border-node-end';
  };

  return (
    <div
      className={`
        relative w-64 rounded-lg border-2 shadow-lg transition-all duration-200
        ${selected
          ? 'border-theme-interactive-primary shadow-theme-interactive-primary/20'
          : `border-theme hover:border-theme-interactive-primary/50 ${getBorderColor(endType)}`
        }
        bg-theme-surface
      `}
    >
      {/* Header */}
      <div className={`px-4 py-3 rounded-t-lg ${getEndColor(endType)}`}>
        <div className="flex items-center justify-between text-white">
          <div className="flex items-center gap-2">
            <OctagonX className="h-4 w-4" />
            <span className="font-medium text-sm">END</span>
          </div>
          {getEndIcon(endType)}
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data?.name || 'End Node'}
          </h3>
          {data?.description && (
            <p className="text-sm text-theme-primary mb-3 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        {/* End message */}
        {(configuration.success_message || configuration.failure_message) && (
          <div className="text-xs text-theme-muted p-2 bg-theme-background rounded border">
            {configuration.success_message || configuration.failure_message}
          </div>
        )}

        <div className="flex items-center justify-between">
          <Badge 
            variant={isSuccess ? "success" : isFailure ? "danger" : "outline"} 
            size="sm" 
            className="capitalize"
          >
            {endType}
          </Badge>
          <div className="flex items-center gap-1">
            {configuration.artifacts && configuration.artifacts.length > 0 && (
              <span className="text-xs text-theme-muted" title="Has artifacts">📎</span>
            )}
            {configuration.deployment_approved && (
              <span className="text-xs text-theme-muted" title="Deployment approved">🚀</span>
            )}
            {selected && <Settings className="h-3 w-3 text-theme-muted" />}
          </div>
        </div>
      </div>

      {/* Auto-positioning Handle for End Node */}
      <DynamicNodeHandles
        nodeType="end"
        isEndNode={true}
        handlePositions={data?.handlePositions}
      />
    </div>
  );
};