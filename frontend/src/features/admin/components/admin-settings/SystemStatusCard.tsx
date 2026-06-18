import React from 'react';

export interface SystemStatusCardProps {
  title: string;
  status: 'healthy' | 'warning' | 'error' | 'maintenance';
  value: string;
  description: string;
  action?: {
    label: string;
    onClick: () => void;
  };
}

const statusConfig = {
  healthy: {
    color: 'text-theme-success-fg',
    bgColor: 'bg-theme-success-bg',
    borderColor: 'border-theme-success-border',
    icon: '+'
  },
  warning: {
    color: 'text-theme-warning-fg',
    bgColor: 'bg-theme-warning-bg',
    borderColor: 'border-theme-warning-border',
    icon: '!'
  },
  error: {
    color: 'text-theme-error-fg',
    bgColor: 'bg-theme-error-bg',
    borderColor: 'border-theme-error-border',
    icon: 'X'
  },
  maintenance: {
    color: 'text-theme-warning-fg',
    bgColor: 'bg-theme-warning-bg',
    borderColor: 'border-theme-warning-border',
    icon: 'M'
  }
};

export const SystemStatusCard: React.FC<SystemStatusCardProps> = ({
  title,
  status,
  value,
  description,
  action
}) => {
  const config = statusConfig[status];

  return (
    <div className="group p-6 rounded-xl border border-theme bg-theme-surface hover:bg-theme-surface-hover transition-all duration-200 cursor-default">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-3">
          <div className="w-12 h-12 bg-theme-background rounded-lg flex items-center justify-center flex-shrink-0">
            <span className="text-xl">{config.icon}</span>
          </div>
          <h3 className="font-semibold text-theme-primary">{title}</h3>
        </div>
        <div className={`w-3 h-3 rounded-full ${
          status === 'healthy' ? 'bg-theme-success-bg' :
          status === 'warning' ? 'bg-theme-warning-bg' :
          status === 'error' ? 'bg-theme-error-bg' :
          'bg-theme-warning-bg'
        } shadow-sm`} />
      </div>
      <div className={`text-2xl font-bold ${config.color} mb-2`}>
        {value}
      </div>
      <p className="text-sm text-theme-secondary mb-4">{description}</p>
      {action && (
        <button
          onClick={action.onClick}
          className={`text-sm font-medium ${config.color} hover:underline transition-colors duration-200`}
        >
          {action.label}
        </button>
      )}
    </div>
  );
};
