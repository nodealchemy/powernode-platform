import React, { useState, useEffect } from 'react';
import {
  Brain,
  Lightbulb,
  Activity,
  CheckCircle,
  XCircle,
  HelpCircle,
  BarChart3,
  RefreshCw,
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Loading } from '@/shared/components/ui/Loading';
import { memoryApiService } from '@/shared/services/ai';
import { cn } from '@/shared/utils/cn';
import { formatDate } from '@/shared/utils/formatters';
import type { MemoryStatsResponse } from '@/shared/services/ai/types/memory-types';

interface MemoryStatsProps {
  agentId: string;
  className?: string;
}

export const MemoryStats: React.FC<MemoryStatsProps> = ({ agentId, className }) => {
  const [stats, setStats] = useState<MemoryStatsResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadStats = async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await memoryApiService.getStats(agentId);
      setStats(response);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load stats');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadStats();
  }, [agentId]);

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

  const byType = stats.by_type || { factual: 0, experiential: 0, working: 0 };
  const byOutcome = stats.by_outcome || { success: 0, failure: 0, unknown: 0 };
  const totalEntries = stats.total_entries ?? (stats as unknown as Record<string, unknown>).entry_count ?? 0;
  const avgImportance = stats.avg_importance ?? 0;

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

        {/* By type breakdown */}
        <div>
          <h4 className="text-sm font-medium text-theme-secondary mb-3">By Type</h4>
          <div className="grid grid-cols-3 gap-3">
            <div className="p-3 bg-theme-info/10 rounded-lg text-center">
              <Brain className="h-5 w-5 text-theme-info mx-auto mb-1" />
              <div className="text-lg font-semibold text-theme-primary">
                {byType.factual ?? 0}
              </div>
              <div className="text-xs text-theme-muted">Factual</div>
            </div>
            <div className="p-3 bg-theme-warning/10 rounded-lg text-center">
              <Lightbulb className="h-5 w-5 text-theme-warning mx-auto mb-1" />
              <div className="text-lg font-semibold text-theme-primary">
                {byType.experiential ?? 0}
              </div>
              <div className="text-xs text-theme-muted">Experiential</div>
            </div>
            <div className="p-3 bg-theme-success/10 rounded-lg text-center">
              <Activity className="h-5 w-5 text-theme-success mx-auto mb-1" />
              <div className="text-lg font-semibold text-theme-primary">
                {byType.working ?? 0}
              </div>
              <div className="text-xs text-theme-muted">Working</div>
            </div>
          </div>
        </div>

        {/* By outcome breakdown */}
        <div>
          <h4 className="text-sm font-medium text-theme-secondary mb-3">By Outcome</h4>
          <div className="grid grid-cols-3 gap-3">
            <div className="p-3 bg-theme-success/10 rounded-lg text-center">
              <CheckCircle className="h-5 w-5 text-theme-success mx-auto mb-1" />
              <div className="text-lg font-semibold text-theme-primary">
                {byOutcome.success ?? 0}
              </div>
              <div className="text-xs text-theme-muted">Success</div>
            </div>
            <div className="p-3 bg-theme-danger/10 rounded-lg text-center">
              <XCircle className="h-5 w-5 text-theme-danger mx-auto mb-1" />
              <div className="text-lg font-semibold text-theme-primary">
                {byOutcome.failure ?? 0}
              </div>
              <div className="text-xs text-theme-muted">Failure</div>
            </div>
            <div className="p-3 bg-theme-muted/10 rounded-lg text-center">
              <HelpCircle className="h-5 w-5 text-theme-muted mx-auto mb-1" />
              <div className="text-lg font-semibold text-theme-primary">
                {byOutcome.unknown ?? 0}
              </div>
              <div className="text-xs text-theme-muted">Unknown</div>
            </div>
          </div>
        </div>

        {/* Additional stats */}
        <div className="space-y-3 pt-3 border-t border-theme">
          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-secondary">Average Importance</span>
            <span className="text-theme-primary font-medium">
              {Math.round(avgImportance * 100)}%
            </span>
          </div>
          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-secondary">Oldest Entry</span>
            <span className="text-theme-primary">{stats.oldest_entry ? formatDate(stats.oldest_entry) : 'N/A'}</span>
          </div>
          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-secondary">Newest Entry</span>
            <span className="text-theme-primary">{stats.newest_entry ? formatDate(stats.newest_entry) : 'N/A'}</span>
          </div>
        </div>
      </CardContent>
    </Card>
  );
};

export default MemoryStats;
