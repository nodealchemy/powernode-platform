import React from 'react';
import { CheckCircle, XCircle, HelpCircle } from 'lucide-react';

type ComplianceStatus = 'compliant' | 'non_compliant' | 'unknown' | 'pending';

interface ComplianceBadgeProps {
  status: ComplianceStatus;
  label?: string;
  size?: 'sm' | 'md';
}

const statusConfig: Record<
  ComplianceStatus,
  { bg: string; text: string; icon: typeof CheckCircle; defaultLabel: string }
> = {
  compliant: {
    bg: 'bg-theme-success/10',
    text: 'text-theme-success',
    icon: CheckCircle,
    defaultLabel: 'Compliant',
  },
  non_compliant: {
    bg: 'bg-theme-error/10',
    text: 'text-theme-error',
    icon: XCircle,
    defaultLabel: 'Non-Compliant',
  },
  unknown: {
    bg: 'bg-theme-muted/10',
    text: 'text-theme-muted',
    icon: HelpCircle,
    defaultLabel: 'Unknown',
  },
  pending: {
    bg: 'bg-theme-info/10',
    text: 'text-theme-info',
    icon: HelpCircle,
    defaultLabel: 'Pending',
  },
};

export const ComplianceBadge: React.FC<ComplianceBadgeProps> = ({
  status,
  label,
  size = 'md',
}) => {
  const config = statusConfig[status];
  const Icon = config.icon;
  const sizeClasses = size === 'sm' ? 'px-1.5 py-0.5 text-xs' : 'px-2 py-1 text-xs';
  const iconSize = size === 'sm' ? 'w-3 h-3' : 'w-3.5 h-3.5';

  return (
    <span className={`inline-flex items-center gap-1 rounded-full font-medium ${config.bg} ${config.text} ${sizeClasses}`}>
      <Icon className={iconSize} />
      {label || config.defaultLabel}
    </span>
  );
};
