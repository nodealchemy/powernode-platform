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
import type { MemoryStats as MemoryStatsType } from '../types/memory';

interface MemoryStatsProps {
  agentId: string;
  className?: string;
}

export const MemoryStats: React.FC<MemoryStatsProps> = ({ agentId, className }) => {
  const [stats, setStats] = useState<MemoryStatsType | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadStats = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await fetchMemoryStats(agentId);
      setStats(response);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load stats');
    } finally {
      setLoading(false);
    }
  }, [agentId]);

  useEffect(() => {
    loadStats();
  }, [loadStats]);

  if (loading) {
    return (
      <Card className={className}>
        <CardContent className="flex items-center justify-center py-8">
          <Loading size="md" message="Loading stats..." />
        </CardContent>
      </Card>
    );
  }

  if (error || !stats) {
    return (
      <Card className={className}>
        <CardContent className="py-8 text-center text-theme-danger">
          {error || 'Failed to load stats'}
        </CardContent>
      </Card>
    );
  }

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
            <div className="p-3 bg-theme-warning/10 rounded-lg text-center">
              <Zap className="h-5 w-5 text-theme-warning mx-auto mb-1" />
              <div className="text-lg font-semibold text-theme-primary">
                {stats.working.count}
              </div>
              <div className="text-xs text-theme-muted">Working</div>
            </div>
            <div className="p-3 bg-theme-info/10 rounded-lg text-center">
              <Clock className="h-5 w-5 text-theme-info mx-auto mb-1" />
              <div className="text-lg font-semibold text-theme-primary">
                {stats.short_term.total}
              </div>
              <div className="text-xs text-theme-muted">Short-Term</div>
              <div className="text-xs text-theme-muted">
                {stats.short_term.active} active / {stats.short_term.expired} expired
              </div>
            </div>
            <div className="p-3 bg-theme-success/10 rounded-lg text-center">
              <Database className="h-5 w-5 text-theme-success mx-auto mb-1" />
              <div className="text-lg font-semibold text-theme-primary">
                {stats.long_term.total}
              </div>
              <div className="text-xs text-theme-muted">Long-Term</div>
              <div className="text-xs text-theme-muted">
                {stats.long_term.active} active
              </div>
            </div>
            <div className="p-3 bg-theme-primary/10 rounded-lg text-center">
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
