
import { TrendingUp, TrendingDown, Minus } from 'lucide-react';

interface AuditLogMetricsProps {
  title: string;
  value: number;
  icon: React.ReactNode;
  trend?: string;
  color: 'blue' | 'green' | 'red' | 'yellow' | 'purple';
  loading?: boolean;
}

const colorMap = {
  blue: 'text-theme-link bg-theme-link-background',
  green: 'text-theme-success bg-theme-success-background',
  red: 'text-theme-error bg-theme-error-background',
  yellow: 'text-theme-warning bg-theme-warning-background',
  purple: 'text-theme-info bg-theme-info-background'
};

// const trendColorMap = {
//   blue: 'text-theme-link',
//   green: 'text-theme-success',
//   red: 'text-theme-error',
//   yellow: 'text-theme-warning',
//   purple: 'text-theme-info'
// };

export const AuditLogMetrics: React.FC<AuditLogMetricsProps> = ({
  title,
  value,
  icon,
  trend,
  color,
  loading = false
}) => {
  const getTrendIcon = (trendText?: string) => {
    if (!trendText) return null;
    
    if (trendText.startsWith('+')) {
      return <TrendingUp className="w-3 h-3" />;
    } else if (trendText.startsWith('-')) {
      return <TrendingDown className="w-3 h-3" />;
    } else {
      return <Minus className="w-3 h-3" />;
    }
  };

  const getTrendColor = (trendText?: string) => {
    if (!trendText) return 'text-theme-tertiary';
    
    if (trendText.startsWith('+')) {
      return color === 'red' ? 'text-theme-error' : 'text-theme-success';
    } else if (trendText.startsWith('-')) {
      return color === 'red' ? 'text-theme-success' : 'text-theme-error';
    } else {
      return 'text-theme-tertiary';
    }
  };

  if (loading) {
    return (
      <div className="bg-theme-surface rounded-lg border border-theme p-4 animate-pulse">
        <div className="flex items-center justify-between mb-3">
          <div className="h-4 bg-theme-background rounded w-20"></div>
          <div className="h-5 w-5 bg-theme-background rounded"></div>
        </div>
        <div className="h-8 bg-theme-background rounded w-16 mb-2"></div>
        <div className="h-3 bg-theme-background rounded w-24"></div>
      </div>
    );
  }

  return (
    <div className="bg-theme-surface rounded-lg border border-theme p-4 hover:shadow-md transition-shadow duration-200">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-medium text-theme-secondary">{title}</h3>
        {/* eslint-disable-next-line security/detect-object-injection */}
        <div className={`p-1 rounded ${colorMap[color]}`}>
          {icon}
        </div>
      </div>
      
      <div className="text-2xl font-bold text-theme-primary mb-1">
        {value.toLocaleString()}
      </div>
      
      {trend && (
        <div className={`flex items-center gap-1 text-xs ${getTrendColor(trend)}`}>
          {getTrendIcon(trend)}
          <span>{trend}</span>
        </div>
      )}
    </div>
  );
};