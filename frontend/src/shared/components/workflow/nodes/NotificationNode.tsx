import React from 'react';
import { NodeProps } from '@xyflow/react';
import { Bell } from 'lucide-react';
import { DynamicNodeHandles } from './DynamicNodeHandles';
import { NotificationNode as NotificationNodeType } from '@/shared/types/workflow';

export const NotificationNode: React.FC<NodeProps<NotificationNodeType>> = ({
  data,
  selected
}) => {

  const getChannelLabel = () => {
    switch (data.configuration?.channel) {
      case 'email':
        return 'EMAIL';
      case 'sms':
        return 'SMS';
      case 'push':
        return 'PUSH';
      case 'slack':
        return 'SLACK';
      case 'webhook':
        return 'WEBHOOK';
      default:
        return 'NOTIFY';
    }
  };

  const getAudienceLabel = () => {
    switch (data.configuration?.audience) {
      case 'single':
        return 'Single recipient';
      case 'group':
        return 'Group notification';
      case 'broadcast':
        return 'Broadcast to all';
      default:
        return 'Custom audience';
    }
  };

  return (
    <div className={`
      relative bg-theme-surface border-2 rounded-lg w-64 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-theme hover:border-theme-interactive-primary/50'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="px-4 py-3 rounded-t-lg bg-node-notification">
        <div className="flex items-center justify-between text-white">
          <div className="flex items-center gap-2">
            <Bell className="h-4 w-4" />
            <span className="font-medium text-sm">NOTIFICATION</span>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-medium text-theme-primary text-sm truncate">
            {data.name || 'Notification'}
          </h3>
          {data.description && (
            <p className="text-sm text-theme-muted mt-1 line-clamp-2">
              {data.description}
            </p>
          )}
        </div>

        <div className="space-y-2 text-xs">
          {data.configuration?.channel && (
            <div>
              <span className="text-theme-muted">Channel:</span>
              <span className="ml-2 text-theme-primary font-medium">
                {getChannelLabel()}
              </span>
            </div>
          )}

          {data.configuration?.audience && (
            <div>
              <span className="text-theme-muted">Audience:</span>
              <span className="ml-2 text-theme-primary font-medium">
                {getAudienceLabel()}
              </span>
            </div>
          )}

          {data.configuration?.template && (
            <div>
              <span className="text-theme-muted">Template:</span>
              <span className="ml-2 text-theme-primary truncate">
                {data.configuration.template}
              </span>
            </div>
          )}
        </div>
      </div>

      {/* Dynamic Handles */}
      <DynamicNodeHandles
        nodeType="notification"
        handlePositions={data?.handlePositions}
      />
    </div>
  );
};