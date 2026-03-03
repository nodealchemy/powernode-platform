import React from 'react';
import { Zap, Clock, Database, Share2 } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import type { MemoryStats, MemoryTier } from '../types/memory';

interface MemoryStatsBarProps {
  stats: MemoryStats | null;
  loading?: boolean;
  className?: string;
  onTierClick?: (tier: MemoryTier) => void;
}

export const MemoryStatsBar: React.FC<MemoryStatsBarProps> = ({ stats, loading, className, onTierClick }) => {
  if (loading || !stats) {
    return (
      <div className={className}>
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          {[0, 1, 2, 3].map((i) => (
            <Card key={i} className="p-4 animate-pulse">
              <div className="h-12 bg-theme-surface rounded" />
            </Card>
          ))}
        </div>
      </div>
    );
  }

  const cards: Array<{
    label: string;
    value: number;
    subtitle?: string;
    icon: typeof Zap;
    bgColor: string;
    iconColor: string;
    tier: MemoryTier;
  }> = [
    {
      label: 'Working Memory',
      value: stats.working.count,
      icon: Zap,
      bgColor: 'bg-theme-warning/10',
      iconColor: 'text-theme-warning',
      tier: 'working',
    },
    {
      label: 'Short-Term',
      value: stats.short_term.total,
      subtitle: `${stats.short_term.active} active, ${stats.short_term.expired} expired`,
      icon: Clock,
      bgColor: 'bg-theme-info/10',
      iconColor: 'text-theme-info',
      tier: 'short_term',
    },
    {
      label: 'Long-Term',
      value: stats.long_term.total,
      subtitle: `${stats.long_term.active} active`,
      icon: Database,
      bgColor: 'bg-theme-success/10',
      iconColor: 'text-theme-success',
      tier: 'long_term',
    },
    {
      label: 'Shared Knowledge',
      value: stats.shared.total,
      subtitle: `${stats.shared.with_embedding} with embedding`,
      icon: Share2,
      bgColor: 'bg-theme-primary/10',
      iconColor: 'text-theme-primary',
      tier: 'shared',
    },
  ];

  return (
    <div className={className}>
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        {cards.map((card) => {
          const Icon = card.icon;
          return (
            <Card
              key={card.label}
              className={`p-4${onTierClick ? ' cursor-pointer hover:border-theme-primary/30 transition-colors' : ''}`}
              onClick={() => onTierClick?.(card.tier)}
            >
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-theme-tertiary">{card.label}</p>
                  <p className="text-2xl font-semibold text-theme-primary">{card.value}</p>
                  {card.subtitle && (
                    <p className="text-xs text-theme-muted mt-0.5">{card.subtitle}</p>
                  )}
                </div>
                <div className={`h-10 w-10 ${card.bgColor} rounded-lg flex items-center justify-center`}>
                  <Icon className={`h-5 w-5 ${card.iconColor}`} />
                </div>
              </div>
            </Card>
          );
        })}
      </div>
    </div>
  );
};
