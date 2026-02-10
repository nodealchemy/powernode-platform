import React from 'react';
import { Zap, Clock, Database, Share2 } from 'lucide-react';
import { cn } from '@/shared/utils/cn';
import type { MemoryTier, MemoryStats } from '../types/memory';

interface MemoryTierTabsProps {
  activeTier: MemoryTier;
  onTierChange: (tier: MemoryTier) => void;
  stats: MemoryStats | null;
  className?: string;
}

const TIER_CONFIG: Record<MemoryTier, { label: string; icon: React.FC<{ className?: string }> }> = {
  working: { label: 'Working', icon: Zap },
  short_term: { label: 'Short-Term', icon: Clock },
  long_term: { label: 'Long-Term', icon: Database },
  shared: { label: 'Shared', icon: Share2 },
};

function getTierCount(tier: MemoryTier, stats: MemoryStats | null): number {
  if (!stats) return 0;
  switch (tier) {
    case 'working':
      return stats.working.count;
    case 'short_term':
      return stats.short_term.total;
    case 'long_term':
      return stats.long_term.total;
    case 'shared':
      return stats.shared.total;
  }
}

const TIERS: MemoryTier[] = ['working', 'short_term', 'long_term', 'shared'];

export const MemoryTierTabs: React.FC<MemoryTierTabsProps> = ({
  activeTier,
  onTierChange,
  stats,
  className,
}) => {
  return (
    <div className={cn('flex border-b border-theme', className)}>
      {TIERS.map((tier) => {
        const config = TIER_CONFIG[tier];
        const Icon = config.icon;
        const count = getTierCount(tier, stats);
        const isActive = activeTier === tier;

        return (
          <button
            key={tier}
            type="button"
            onClick={() => onTierChange(tier)}
            className={cn(
              'flex items-center gap-2 px-4 py-3 text-sm font-medium border-b-2 transition-colors',
              isActive
                ? 'border-theme-primary text-theme-primary'
                : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme-border'
            )}
          >
            <Icon className="h-4 w-4" />
            {config.label}
            <span
              className={cn(
                'px-1.5 py-0.5 text-xs rounded-full',
                isActive
                  ? 'bg-theme-primary/10 text-theme-primary'
                  : 'bg-theme-surface text-theme-muted'
              )}
            >
              {count}
            </span>
          </button>
        );
      })}
    </div>
  );
};
