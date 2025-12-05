import React from 'react';
import { Handle, Position, NodeProps } from '@xyflow/react';
import { Bell, MessageSquare, Smartphone, Mail, Megaphone, Users, User } from 'lucide-react';

export const NotificationNode: React.FC<NodeProps<any>> = ({
  data,
  selected
}) => {
  const getChannelIcon = () => {
    switch (data.configuration?.channel) {
      case 'email':
        return <Mail className="h-4 w-4" />;
      case 'sms':
        return <Smartphone className="h-4 w-4" />;
      case 'push':
        return <Bell className="h-4 w-4" />;
      case 'slack':
        return <MessageSquare className="h-4 w-4" />;
      case 'webhook':
        return <Megaphone className="h-4 w-4" />;
      default:
        return <Bell className="h-4 w-4" />;
    }
  };

  const getAudienceIcon = () => {
    switch (data.configuration?.audience) {
      case 'single':
        return <User className="h-4 w-4" />;
      case 'group':
      case 'broadcast':
        return <Users className="h-4 w-4" />;
      default:
        return <User className="h-4 w-4" />;
    }
  };

  const getChannelColor = () => {
    switch (data.configuration?.channel) {
      case 'email':
        return 'text-theme-info bg-blue-100';
      case 'sms':
        return 'text-theme-success bg-green-100';
      case 'push':
        return 'text-theme-interactive-primary bg-purple-100';
      case 'slack':
        return 'text-theme-warning bg-orange-100';
      case 'webhook':
        return 'text-teal-600 bg-teal-100';
      default:
        return 'text-pink-600 bg-pink-100';
    }
  };

  const getPriorityColor = () => {
    switch (data.configuration?.priority) {
      case 'high':
      case 'urgent':
        return 'text-theme-danger';
      case 'medium':
      case 'normal':
        return 'text-theme-warning';
      case 'low':
        return 'text-theme-success';
      default:
        return 'text-theme-info';
    }
  };

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
      relative bg-theme-surface border-2 rounded-lg p-4 w-48 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-pink-500'}
      hover:shadow-xl transition-all duration-200
    `}>
      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className="w-8 h-8 bg-pink-500 rounded-lg flex items-center justify-center text-white">
          <Bell className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'Notification'}
          </h3>
          <div className="flex items-center gap-2">
            {data.configuration?.channel && (
              <span className={`
                text-xs font-medium px-2 py-0.5 rounded-full
                ${getChannelColor()}
              `}>
                {getChannelLabel()}
              </span>
            )}
            {data.configuration?.priority && data.configuration.priority !== 'normal' && (
              <span className={`text-xs font-medium ${getPriorityColor()}`}>
                {data.configuration.priority.toUpperCase()}
              </span>
            )}
            {data.configuration?.batchEnabled && (
              <span className="text-xs text-theme-warning font-medium">BATCH</span>
            )}
          </div>
        </div>
      </div>

      {/* Description */}
      {data.description && (
        <p className="text-sm text-theme-primary mb-3 line-clamp-2">
          {data.description}
        </p>
      )}

      {/* Audience Display */}
      {data.configuration?.audience && (
        <div className="mb-3 p-2 bg-theme-background border border-theme-border rounded">
          <div className="flex items-center gap-2">
            {getAudienceIcon()}
            <div>
              <div className="text-xs text-theme-muted">Audience:</div>
              <div className="text-sm text-theme-secondary">
                {getAudienceLabel()}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Configuration Details */}
      <div className="space-y-1 text-xs">
        {data.configuration?.template && (
          <div>
            <span className="text-theme-muted">Template:</span>
            <span className="ml-1 text-theme-secondary">
              {data.configuration.template}
            </span>
          </div>
        )}
        {data.configuration?.retryAttempts && (
          <div>
            <span className="text-theme-muted">Retries:</span>
            <span className="ml-1 text-theme-secondary">
              {data.configuration.retryAttempts}
            </span>
          </div>
        )}
      </div>

      {/* Channel Icon Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-6 h-6 bg-pink-500/10 rounded-full flex items-center justify-center text-pink-600">
          {getChannelIcon()}
        </div>
      </div>

      {/* Priority Indicator */}
      {data.configuration?.priority && data.configuration.priority === 'high' && (
        <div className="absolute top-2 right-9">
          <div className="w-6 h-6 bg-theme-danger/10 rounded-full flex items-center justify-center text-theme-danger">
            <Megaphone className="h-4 w-4" />
          </div>
        </div>
      )}

      {/* Processing Indicator */}
      <div className="absolute bottom-2 right-2">
        <div className="flex space-x-1">
          <div className="w-1 h-3 bg-pink-500 rounded-full animate-pulse" style={{ animationDelay: '0ms' }} />
          <div className="w-1 h-3 bg-pink-500 rounded-full animate-pulse" style={{ animationDelay: '100ms' }} />
          <div className="w-1 h-3 bg-pink-500 rounded-full animate-pulse" style={{ animationDelay: '200ms' }} />
        </div>
      </div>

      {/* Handles - orientation-aware */}
      <Handle
        type="target"
        position={data.handleOrientation === 'horizontal' ? Position.Left : Position.Top}
        className="w-3 h-3 bg-pink-500 border-2 border-theme-surface"
        style={data.handleOrientation === 'horizontal' ? { left: -6 } : { top: -6 }}
      />

      {/* Success Handle - orientation-aware */}
      <Handle
        type="source"
        position={data.handleOrientation === 'horizontal' ? Position.Right : Position.Bottom}
        id="success"
        className="w-3 h-3 bg-theme-success border-2 border-theme-surface"
        style={data.handleOrientation === 'horizontal' ? { right: -6, top: '30%' } : { bottom: -6, left: '30%' }}
      />

      {/* Failure Handle - orientation-aware */}
      <Handle
        type="source"
        position={data.handleOrientation === 'horizontal' ? Position.Right : Position.Bottom}
        id="failure"
        className="w-3 h-3 bg-theme-danger border-2 border-theme-surface"
        style={data.handleOrientation === 'horizontal' ? { right: -6, top: '70%' } : { bottom: -6, left: '70%' }}
      />
    </div>
  );
};