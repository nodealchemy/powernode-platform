import React from 'react';
import { NodeProps, useEdges } from '@xyflow/react';
import { Play, Settings } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { DynamicNodeHandles } from './DynamicNodeHandles';

export interface StartNodeData extends Record<string, unknown> {
  name?: string;
  description?: string;
  nodeType: 'start';
  configuration?: {
    start_trigger?: string;
    trigger_type?: string;
    webhook_url?: string;
    schedule?: string;
    orientation?: 'horizontal' | 'vertical';
  };
  metadata?: Record<string, any>;
  isStartNode?: boolean;
  isEndNode?: boolean;
  isErrorHandler?: boolean;
  timeoutSeconds?: number;
  retryCount?: number;
  handleOrientation?: 'horizontal' | 'vertical';
}

export const StartNode: React.FC<NodeProps<any>> = ({ id, data = {} as StartNodeData, selected }) => {
  const edges = useEdges();
  const hasOutboundConnection = edges.some(edge => edge.source === id);
  const configuration = data?.configuration || {};
  const triggerType = configuration.start_trigger || configuration.trigger_type || 'manual';
  
  const getTriggerIcon = (type: string) => {
    switch (type) {
      case 'webhook':
        return '🌐';
      case 'schedule':
        return '⏰';
      case 'api':
        return '🔗';
      case 'manual':
      default:
        return '▶️';
    }
  };

  const getTriggerColor = (type: string) => {
    switch (type) {
      case 'webhook':
        return 'bg-theme-info';
      case 'schedule':
        return 'bg-theme-success';
      case 'api':
        return 'bg-theme-interactive-primary';
      case 'manual':
      default:
        return 'bg-emerald-500';
    }
  };

  return (
    <div
      className={`
        relative w-48 rounded-lg border-2 shadow-lg transition-all duration-200
        ${selected 
          ? 'border-theme-interactive-primary shadow-theme-interactive-primary/20' 
          : 'border-theme hover:border-theme-interactive-primary/50'
        }
        bg-theme-surface
      `}
    >
      {/* Header */}
      <div className={`px-4 py-3 rounded-t-lg ${getTriggerColor(triggerType)}`}>
        <div className="flex items-center justify-between text-white">
          <div className="flex items-center gap-2">
            <span className="text-lg">{getTriggerIcon(triggerType)}</span>
            <span className="font-medium text-sm">START</span>
          </div>
          <Play className="h-4 w-4" />
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data?.name || 'Start Node'}
          </h3>
          {data?.description && (
            <p className="text-sm text-theme-primary mb-3 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        <div className="flex items-center justify-between">
          <Badge variant="outline" size="sm" className="capitalize">
            {triggerType}
          </Badge>
          <div className="flex items-center gap-1">
            {configuration.webhook_url && (
              <span className="text-xs text-theme-muted">🌐</span>
            )}
            {configuration.schedule && (
              <span className="text-xs text-theme-muted">⏰</span>
            )}
            {selected && <Settings className="h-3 w-3 text-theme-muted" />}
          </div>
        </div>
      </div>

      {/* Auto-positioning Handle for Start Node */}
      <DynamicNodeHandles
        nodeType="start"
        nodeColor="bg-emerald-500"
        isStartNode={true}
        hasOutboundConnection={hasOutboundConnection}
        orientation={data?.handleOrientation || data?.configuration?.orientation || 'vertical'}
      />
    </div>
  );
};