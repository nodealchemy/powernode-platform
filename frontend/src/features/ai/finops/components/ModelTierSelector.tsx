import React from 'react';
import { Zap, Star, Crown } from 'lucide-react';
import type { ModelTier } from '../types/finops';

interface ModelTierSelectorProps {
  value: ModelTier | undefined;
  onChange: (tier: ModelTier | undefined) => void;
  className?: string;
}

const TIERS: { id: ModelTier | undefined; label: string; icon: React.FC<{ className?: string }>; description: string }[] = [
  {
    id: undefined,
    label: 'All Tiers',
    icon: Star,
    description: 'Show all model tiers',
  },
  {
    id: 'economy',
    label: 'Economy',
    icon: Zap,
    description: 'Low cost, basic models',
  },
  {
    id: 'standard',
    label: 'Standard',
    icon: Star,
    description: 'Balanced performance',
  },
  {
    id: 'premium',
    label: 'Premium',
    icon: Crown,
    description: 'Highest capability',
  },
];

export const ModelTierSelector: React.FC<ModelTierSelectorProps> = ({
  value,
  onChange,
  className = '',
}) => {
  return (
    <div className={`flex items-center gap-2 ${className}`}>
      {TIERS.map((tier) => {
        const Icon = tier.icon;
        const isSelected = value === tier.id;

        return (
          <button
            key={tier.label}
            onClick={() => onChange(tier.id)}
            className={`
              flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors
              ${isSelected
                ? 'bg-theme-interactive-primary text-white'
                : 'bg-theme-surface border border-theme text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover'
              }
            `}
            title={tier.description}
          >
            <Icon className="h-3.5 w-3.5" />
            <span>{tier.label}</span>
          </button>
        );
      })}
    </div>
  );
};
