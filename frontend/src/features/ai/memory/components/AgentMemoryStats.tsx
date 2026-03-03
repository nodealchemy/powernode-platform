import React, { useState, useEffect, useCallback } from 'react';
import {
  Zap,
  Clock,
  Database,
  Share2,
  BarChart3,
  RefreshCw,
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Loading } from '@/shared/components/ui/Loading';
import { cn } from '@/shared/utils/cn';
import { fetchMemoryStats } from '../api/memoryApi';
import type { MemoryStats as MemoryStatsType, MemoryTier } from '../types/memory';

interface MemoryStatsProps {
  agentId: string;
  stats?: MemoryStatsType;
  onTierClick?: (tier: MemoryTier) => void;
  className?: string;
}

export const MemoryStats: React.FC<MemoryStatsProps> = ({
  agentId,
  stats: externalStats,
  onTierClick,
  className,
}) => {
  const [internalStats, setInternalStats] = useState<MemoryStatsType | null>(null);
  const [loading, setLoading] = useState(!externalStats);
  const [error, setError] = useState<string | null>(null);

  // Use externally-provided stats when available, fall back to internal fetch
  const stats = externalStats || internalStats;

  const loadStats = useCallback(async () => {
    if (externalStats) return; // Parent provides stats — skip redundant fetch
    try {
      setLoading(true);
      setError(null);
      const response = await fetchMemoryStats(agentId);
      setInternalStats(response);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load stats');
    } finally {
      setLoading(false);
    }
  }, [agentId, externalStats]);

  useEffect(() => {
    loadStats();
  }, [loadStats]);

  if (loading && !stats) {
    return (
      <Card className={className}>
        <CardContent className="flex items-center justify-center py-8">
          <Loading size="md" message="Loading stats..." />
        </CardContent>
      </Card>
    );
  }

  if (error && !stats) {
    return (
      <Card className={className}>
        <CardContent className="py-8 text-center text-theme-danger">
          {error || 'Failed to load stats'}
        </CardContent>
      </Card>
    );
  }

  if (!stats) return null;

  const totalEntries =
    stats.working.count +
    stats.short_term.total +
    stats.long_term.total +
    stats.shared.total;

  return (
    <Card className={className}>
      <CardHeader
        title="Memory Statistics"
        icon={<BarChart3 className="h-5 w-5" />}
        action={
          <Button variant="ghost" size="sm" onClick={loadStats} disabled={loading}>
            <RefreshCw className={cn('h-4 w-4', loading && 'animate-spin')} />
          </Button>
        }
      />
      <CardContent className="space-y-6">
        {/* Total count */}
        <div className="text-center p-4 bg-theme-surface rounded-lg">
          <div className="text-3xl font-bold text-theme-primary">{totalEntries}</div>
          <div className="text-sm text-theme-muted">Total Memories</div>
        </div>

        {/* By tier breakdown */}
        <div>
          <h4 className="text-sm font-medium text-theme-secondary mb-3">By Tier</h4>
          <div className="grid grid-cols-2 gap-3">
            <div
              className={cn(
                'p-3 bg-theme-warning/10 rounded-lg text-center transition-colors',
                onTierClick && 'cursor-pointer hover:ring-1 hover:ring-theme-warning/50'
              )}
              onClick={() => onTierClick?.('working')}
            >
              <Zap className="h-5 w-5 text-theme-warning mx-auto mb-1" />
              <div className="text-lg font-semibold text-theme-primary">
                {stats.working.count}
              </div>
              <div className="text-xs text-theme-muted">Working</div>
            </div>
            <div
              className={cn(
                'p-3 bg-theme-info/10 rounded-lg text-center transition-colors',
                onTierClick && 'cursor-pointer hover:ring-1 hover:ring-theme-info/50'
              )}
              onClick={() => onTierClick?.('short_term')}
            >
              <Clock className="h-5 w-5 text-theme-info mx-auto mb-1" />
              <div className="text-lg font-semibold text-theme-primary">
                {stats.short_term.total}
              </div>
              <div className="text-xs text-theme-muted">Short-Term</div>
              <div className="text-xs text-theme-muted">
                {stats.short_term.active} active / {stats.short_term.expired} expired
              </div>
            </div>
            <div
              className={cn(
                'p-3 bg-theme-success/10 rounded-lg text-center transition-colors',
                onTierClick && 'cursor-pointer hover:ring-1 hover:ring-theme-success/50'
              )}
              onClick={() => onTierClick?.('long_term')}
            >
              <Database className="h-5 w-5 text-theme-success mx-auto mb-1" />
              <div className="text-lg font-semibold text-theme-primary">
                {stats.long_term.total}
              </div>
              <div className="text-xs text-theme-muted">Long-Term</div>
              <div className="text-xs text-theme-muted">
                {stats.long_term.active} active
              </div>
            </div>
            <div
              className={cn(
                'p-3 bg-theme-primary/10 rounded-lg text-center transition-colors',
                onTierClick && 'cursor-pointer hover:ring-1 hover:ring-theme-primary/50'
              )}
              onClick={() => onTierClick?.('shared')}
            >
              <Share2 className="h-5 w-5 text-theme-primary mx-auto mb-1" />
              <div className="text-lg font-semibold text-theme-primary">
                {stats.shared.total}
              </div>
              <div className="text-xs text-theme-muted">Shared</div>
              <div className="text-xs text-theme-muted">
                {stats.shared.with_embedding} with embedding
              </div>
            </div>
          </div>
        </div>
      </CardContent>
    </Card>
  );
};

export default MemoryStats;
