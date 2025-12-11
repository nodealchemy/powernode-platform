import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Play, Settings, Globe, Clock, Link } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { StartNode as StartNodeType } from '@/shared/types/workflow';

export const StartNode: React.FC<NodeProps<StartNodeType>> = ({ data, selected }) => {
  const configuration = data?.configuration || {};
  const triggerType = configuration.start_trigger || configuration.trigger_type || 'manual';
  
  const getTriggerIcon = (type: string) => {
    switch (type) {
      case 'webhook':
        return <Globe className="h-4 w-4" />;
      case 'schedule':
        return <Clock className="h-4 w-4" />;
      case 'api':
        return <Link className="h-4 w-4" />;
      case 'manual':
      default:
        return <Play className="h-4 w-4" />;
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
        return 'bg-node-start';
    }
  };

  return (
    <div
      className={`
        relative w-64 rounded-lg border-2 shadow-lg transition-all duration-200
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
            {getTriggerIcon(triggerType)}
            <span className="font-medium text-sm">START</span>
          </div>
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
        isStartNode={true}
        handlePositions={data?.handlePositions}
      />
    </div>
  );
};