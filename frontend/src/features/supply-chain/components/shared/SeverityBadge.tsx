import React from 'react';

type Severity = 'critical' | 'high' | 'medium' | 'low';

interface SeverityBadgeProps {
  severity: Severity;
  showLabel?: boolean;
  size?: 'sm' | 'md';
}

const severityConfig: Record<Severity, { bg: string; text: string; dot: string; label: string }> = {
  critical: { bg: 'bg-theme-error/10', text: 'text-theme-error', dot: 'bg-theme-error', label: 'Critical' },
  high: { bg: 'bg-theme-warning/10', text: 'text-theme-warning', dot: 'bg-theme-warning', label: 'High' },
  medium: { bg: 'bg-theme-info/10', text: 'text-theme-info', dot: 'bg-theme-info', label: 'Medium' },
  low: { bg: 'bg-theme-success/10', text: 'text-theme-success', dot: 'bg-theme-success', label: 'Low' },
};

export const SeverityBadge: React.FC<SeverityBadgeProps> = ({
  severity,
  showLabel = true,
  size = 'md',
}) => {
  const config = severityConfig[severity];
  const sizeClasses = size === 'sm' ? 'px-1.5 py-0.5 text-xs' : 'px-2 py-1 text-xs';

  return (
    <span
      className={`inline-flex items-center gap-1 rounded-full font-medium ${config.bg} ${config.text} ${sizeClasses}`}
    >
      <span className={`w-1.5 h-1.5 rounded-full ${config.dot}`} />
      {showLabel && config.label}
    </span>
  );
};
