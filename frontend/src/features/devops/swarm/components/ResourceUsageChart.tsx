import React from 'react';

interface ResourceBar {
  label: string;
  used: number;
  total: number;
  unit?: string;
}

interface ResourceUsageChartProps {
  resources: ResourceBar[];
  title?: string;
}

export const ResourceUsageChart: React.FC<ResourceUsageChartProps> = ({ resources, title }) => {
  return (
    <div className="space-y-3">
      {title && <h4 className="text-sm font-semibold text-theme-primary">{title}</h4>}

      {resources.map((resource) => {
        const percentage = resource.total > 0 ? Math.min(100, (resource.used / resource.total) * 100) : 0;
        const color = percentage >= 90 ? 'bg-theme-error' : percentage >= 70 ? 'bg-theme-warning' : 'bg-theme-success';

        return (
          <div key={resource.label}>
            <div className="flex items-center justify-between mb-1">
              <span className="text-xs text-theme-secondary">{resource.label}</span>
              <span className="text-xs text-theme-primary font-medium">
                {resource.used}{resource.unit || ''} / {resource.total}{resource.unit || ''}
                <span className="text-theme-tertiary ml-1">({Math.round(percentage)}%)</span>
              </span>
            </div>
            <div className="w-full h-2 bg-theme-surface rounded-full overflow-hidden">
              <div className={`h-full rounded-full transition-all ${color}`} style={{ width: `${percentage}%` }} />
            </div>
          </div>
        );
      })}
    </div>
  );
};
