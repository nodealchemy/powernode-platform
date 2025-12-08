import React from 'react';
import { Handle, Position, NodeProps } from '@xyflow/react';
import { Clock, Calendar, Play, Pause, RotateCcw, Timer } from 'lucide-react';

export const SchedulerNode: React.FC<NodeProps<any>> = ({
  data,
  selected
}) => {
  const getScheduleIcon = () => {
    switch (data.configuration?.scheduleType) {
      case 'cron':
        return <Calendar className="h-4 w-4" />;
      case 'interval':
        return <RotateCcw className="h-4 w-4" />;
      case 'once':
        return <Timer className="h-4 w-4" />;
      case 'manual':
        return <Play className="h-4 w-4" />;
      default:
        return <Clock className="h-4 w-4" />;
    }
  };

  const getScheduleColor = () => {
    switch (data.configuration?.scheduleType) {
      case 'cron':
        return 'text-theme-info bg-theme-info/20';
      case 'interval':
        return 'text-theme-success bg-theme-success/20';
      case 'once':
        return 'text-theme-warning bg-theme-warning/20';
      case 'manual':
        return 'text-theme-interactive-primary bg-theme-interactive-primary/20';
      default:
        return 'text-theme-info bg-theme-info/20';
    }
  };

  const getScheduleLabel = () => {
    switch (data.configuration?.scheduleType) {
      case 'cron':
        return 'CRON';
      case 'interval':
        return 'INTERVAL';
      case 'once':
        return 'ONE-TIME';
      case 'manual':
        return 'MANUAL';
      default:
        return 'SCHEDULE';
    }
  };

  const getScheduleDisplay = () => {
    const config = data.configuration;
    if (!config) return 'No schedule configured';

    if (config.scheduleType === 'cron' && config.cronExpression) {
      return config.cronExpression;
    }

    if (config.scheduleType === 'interval' && config.interval) {
      const unit = config.intervalUnit || 'minutes';
      return `Every ${config.interval} ${unit}`;
    }

    if (config.scheduleType === 'once' && config.startTime) {
      try {
        const date = new Date(config.startTime);
        return date.toLocaleString();
      } catch {
        return config.startTime;
      }
    }

    if (config.scheduleType === 'manual') {
      return 'Manual trigger only';
    }

    return 'Custom schedule';
  };

  const getStatusIcon = () => {
    if (data.configuration?.enabled === false) {
      return <Pause className="h-3 w-3 text-theme-muted" />;
    }
    return <Play className="h-3 w-3 text-theme-success" />;
  };

  const getStatusColor = () => {
    if (data.configuration?.enabled === false) {
      return 'bg-theme-surface0';
    }
    return 'bg-cyan-500';
  };

  return (
    <div className={`
      relative bg-theme-surface border-2 rounded-lg p-4 w-48 shadow-lg
      ${selected ? 'border-theme-interactive-primary ring-2 ring-theme-interactive-primary/20' : 'border-cyan-500'}
      hover:shadow-xl transition-all duration-200
      ${data.configuration?.enabled === false ? 'opacity-75' : ''}
    `}>
      {/* Header */}
      <div className="flex items-center gap-3 mb-3">
        <div className={`w-8 h-8 ${getStatusColor()} rounded-lg flex items-center justify-center text-white`}>
          <Clock className="h-4 w-4" />
        </div>
        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-theme-primary truncate">
            {data.name || 'Scheduler'}
          </h3>
          <div className="flex items-center gap-2">
            {data.configuration?.scheduleType && (
              <span className={`
                text-xs font-medium px-2 py-0.5 rounded-full
                ${getScheduleColor()}
              `}>
                {getScheduleLabel()}
              </span>
            )}
            <div className="flex items-center gap-1">
              {getStatusIcon()}
              <span className={`text-xs font-medium ${data.configuration?.enabled === false ? 'text-theme-muted' : 'text-theme-success'}`}>
                {data.configuration?.enabled === false ? 'PAUSED' : 'ACTIVE'}
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Description */}
      {data.description && (
        <p className="text-sm text-theme-primary mb-3 line-clamp-2">
          {data.description}
        </p>
      )}

      {/* Schedule Display */}
      <div className="mb-3 p-2 bg-theme-background border border-theme-border rounded">
        <div className="text-xs text-theme-muted mb-1">Schedule:</div>
        <div className="text-sm text-theme-secondary font-mono">
          {getScheduleDisplay()}
        </div>
      </div>

      {/* Configuration Details */}
      <div className="space-y-1 text-xs">
        {data.configuration?.timezone && (
          <div>
            <span className="text-theme-muted">Timezone:</span>
            <span className="ml-1 text-theme-secondary">
              {data.configuration.timezone}
            </span>
          </div>
        )}
        {data.configuration?.startTime && data.configuration?.endTime && (
          <div>
            <span className="text-theme-muted">Active period:</span>
            <span className="ml-1 text-theme-secondary">
              {new Date(data.configuration.startTime).toLocaleDateString()} - {new Date(data.configuration.endTime).toLocaleDateString()}
            </span>
          </div>
        )}
      </div>

      {/* Schedule Type Icon Indicator */}
      <div className="absolute top-2 right-2">
        <div className="w-6 h-6 bg-cyan-500/10 rounded-full flex items-center justify-center text-cyan-600">
          {getScheduleIcon()}
        </div>
      </div>

      {/* Processing Indicator */}
      <div className="absolute bottom-2 right-2">
        <div className="flex space-x-1">
          <div className={`w-1 h-3 ${getStatusColor()} rounded-full animate-pulse`} style={{ animationDelay: '0ms' }} />
          <div className={`w-1 h-3 ${getStatusColor()} rounded-full animate-pulse`} style={{ animationDelay: '100ms' }} />
          <div className={`w-1 h-3 ${getStatusColor()} rounded-full animate-pulse`} style={{ animationDelay: '200ms' }} />
        </div>
      </div>

      {/* Trigger Handle (Manual) - orientation-aware */}
      <Handle
        type="target"
        position={data.handleOrientation === 'horizontal' ? Position.Left : Position.Top}
        id="trigger"
        className={`w-3 h-3 ${getStatusColor()} border-2 border-theme-surface`}
        style={data.handleOrientation === 'horizontal' ? { left: -6, top: '30%' } : { top: -6, left: '30%' }}
      />

      {/* Data Input Handle - orientation-aware */}
      <Handle
        type="target"
        position={data.handleOrientation === 'horizontal' ? Position.Left : Position.Top}
        id="data"
        className={`w-3 h-3 ${getStatusColor()} border-2 border-theme-surface`}
        style={data.handleOrientation === 'horizontal' ? { left: -6, top: '70%' } : { top: -6, left: '70%' }}
      />

      {/* Output Handle - orientation-aware */}
      <Handle
        type="source"
        position={data.handleOrientation === 'horizontal' ? Position.Right : Position.Bottom}
        className={`w-3 h-3 ${getStatusColor()} border-2 border-theme-surface`}
        style={data.handleOrientation === 'horizontal' ? { right: -6 } : { bottom: -6 }}
      />
    </div>
  );
};