import React from 'react';

type RiskTier = 'critical' | 'high' | 'medium' | 'low';

interface RiskTierBadgeProps {
  tier: RiskTier;
  size?: 'sm' | 'md';
}

const tierConfig: Record<RiskTier, { bg: string; text: string; label: string }> = {
  critical: {
    bg: 'bg-theme-error/10',
    text: 'text-theme-error',
    label: 'Critical Risk',
  },
  high: {
    bg: 'bg-theme-warning/10',
    text: 'text-theme-warning',
    label: 'High Risk',
  },
  medium: {
    bg: 'bg-theme-info/10',
    text: 'text-theme-info',
    label: 'Medium Risk',
  },
  low: {
    bg: 'bg-theme-success/10',
    text: 'text-theme-success',
    label: 'Low Risk',
  },
};

export const RiskTierBadge: React.FC<RiskTierBadgeProps> = ({ tier, size = 'md' }) => {
  const config = tierConfig[tier];
  const sizeClasses = size === 'sm' ? 'px-1.5 py-0.5 text-xs' : 'px-2 py-1 text-xs';

  return (
    <span className={`inline-flex items-center rounded-full font-medium ${config.bg} ${config.text} ${sizeClasses}`}>
      {config.label}
    </span>
  );
};
