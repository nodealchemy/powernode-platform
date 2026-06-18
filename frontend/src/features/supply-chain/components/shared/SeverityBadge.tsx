import React from 'react';

type Severity = 'critical' | 'high' | 'medium' | 'low';

interface SeverityBadgeProps {
  severity: Severity;
  showLabel?: boolean;
  size?: 'sm' | 'md';
}

const severityConfig: Record<Severity, { bg: string; text: string; dot: string; label: string }> = {
  critical: { bg: 'bg-theme-error-fg/10', text: 'text-theme-error-fg', dot: 'bg-theme-error-bg', label: 'Critical' },
  high: { bg: 'bg-theme-warning-fg/10', text: 'text-theme-warning-fg', dot: 'bg-theme-warning-bg', label: 'High' },
  medium: { bg: 'bg-theme-info-fg/10', text: 'text-theme-info-fg', dot: 'bg-theme-info-bg', label: 'Medium' },
  low: { bg: 'bg-theme-success-fg/10', text: 'text-theme-success-fg', dot: 'bg-theme-success-bg', label: 'Low' },
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
