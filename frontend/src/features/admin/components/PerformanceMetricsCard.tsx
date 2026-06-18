
import { TrendingUp, TrendingDown } from 'lucide-react';

interface PerformanceMetricsCardProps {
  title: string;
  value: string | number;
  unit?: string;
  icon: React.ReactNode;
  status: 'good' | 'warning' | 'critical';
  trend?: number;
  description?: string;
  className?: string;
}

export const PerformanceMetricsCard: React.FC<PerformanceMetricsCardProps> = ({
  title,
  value,
  unit,
  icon,
  status,
  trend,
  description,
  className = ''
}) => {
  const statusConfig = {
    good: {
      border: 'border-theme-success-border',
      background: 'bg-theme-success-bg',
      text: 'text-theme-success-fg',
      iconBg: 'bg-theme-success-bg'
    },
    warning: {
      border: 'border-theme-warning-border',
      background: 'bg-theme-warning-bg', 
      text: 'text-theme-warning-fg',
      iconBg: 'bg-theme-warning-bg'
    },
    critical: {
      border: 'border-theme-error-border',
      background: 'bg-theme-error-bg',
      text: 'text-theme-error-fg',
      iconBg: 'bg-theme-error-bg'
    }
  } as const;

  const config = statusConfig[status as keyof typeof statusConfig];

  return (
    <div className={`rounded-lg border-2 p-6 ${config.border} ${config.background} ${className}`}>
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-4">
          <div className={`p-3 rounded-lg ${config.iconBg} ${config.text}`}>
            {icon}
          </div>
          <div>
            <p className="text-sm font-medium text-theme-secondary mb-1">{title}</p>
            <p className={`text-3xl font-bold ${config.text}`}>
              {typeof value === 'number' ? value.toLocaleString() : value}
              {unit && <span className="text-lg ml-1">{unit}</span>}
            </p>
            {description && (
              <p className="text-xs text-theme-secondary mt-1">{description}</p>
            )}
          </div>
        </div>
        
        {trend !== undefined && (
          <div className={`flex items-center gap-2 px-3 py-1 rounded-full text-sm font-medium ${
            trend >= 0 
              ? 'bg-theme-success-bg text-theme-success-fg'
              : 'bg-theme-error-bg text-theme-error-fg'
          }`}>
            {trend >= 0 ? (
              <TrendingUp className="w-4 h-4" />
            ) : (
              <TrendingDown className="w-4 h-4" />
            )}
            <span>{Math.abs(trend).toFixed(1)}%</span>
          </div>
        )}
      </div>
    </div>
  );
};

