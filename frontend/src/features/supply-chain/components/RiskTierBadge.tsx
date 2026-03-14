import React from 'react';
import { Badge } from '@/shared/components/ui/Badge';

type RiskTier = 'critical' | 'high' | 'medium' | 'low';

interface RiskTierBadgeProps {
  tier: RiskTier;
  className?: string;
}

export const RiskTierBadge: React.FC<RiskTierBadgeProps> = ({ tier, className }) => {
  const variantMap: Record<RiskTier, 'danger' | 'warning' | 'info' | 'success'> = {
    critical: 'danger',
    high: 'warning',
    medium: 'info',
    low: 'success',
  };

  const labelMap: Record<RiskTier, string> = {
    critical: 'Critical',
    high: 'High',
    medium: 'Medium',
    low: 'Low',
  };

  return (
    <Badge variant={variantMap[tier]} size="sm" className={className}>
      {labelMap[tier]}
    </Badge>
  );
};
