import React, { useState, useEffect, useCallback } from 'react';
import {
  Plus,
  RefreshCw,
  RotateCcw,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { ralphLoopsApi } from '@/shared/services/ai/RalphLoopsApiService';
import { agentsApi } from '@/shared/services/ai/AgentsApiService';
import { RalphLoopCard } from './RalphLoopCard';
import { cn } from '@/shared/utils/cn';
import type { RalphLoopSummary, RalphLoopFilters, RalphLoopStatus } from '@/shared/services/ai/types/ralph-types';

interface RalphLoopListProps {
  onSelectLoop?: (loop: RalphLoopSummary) => void;
  onCreateLoop?: () => void;
  className?: string;
}

const statusOptions = [
  { value: '', label: 'All Status' },
  { value: 'pending', label: 'Pending' },
  { value: 'running', label: 'Running' },
  { value: 'paused', label: 'Paused' },
  { value: 'completed', label: 'Completed' },
  { value: 'failed', label: 'Failed' },
  { value: 'cancelled', label: 'Cancelled' },
];

interface AgentOption {
  value: string;
  label: string;
}

export const RalphLoopList: React.FC<RalphLoopListProps> = ({
  onSelectLoop,
  onCreateLoop,
  className,
}) => {
  const [loops, setLoops] = useState<RalphLoopSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [agentFilter, setAgentFilter] = useState<string>('');
  const [agentOptions, setAgentOptions] = useState<AgentOption[]>([]);
  const [totalCount, setTotalCount] = useState(0);

  // Load agents for filter dropdown
  useEffect(() => {
    agentsApi.getAgents({ per_page: 100 }).then((res) => {
      const options = (res.items || []).map((a: { id: string; name: string }) => ({
        value: a.id,
        label: a.name,
      }));
      setAgentOptions(options);
    }).catch(() => {});
  }, []);

  const loadLoops = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const filters: RalphLoopFilters = { per_page: 50 };
      if (statusFilter) filters.status = statusFilter as RalphLoopStatus;
      if (agentFilter) filters.default_agent_id = agentFilter;

      const response = await ralphLoopsApi.getLoops(filters);
      setLoops(response.items || []);
      setTotalCount(response.pagination?.total_count || 0);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load loops');
    } finally {
      setLoading(false);
    }
  }, [statusFilter, agentFilter]);

  useEffect(() => {
    loadLoops();
  }, [loadLoops]);

  // Auto-refresh for running loops
  useEffect(() => {
    const hasRunning = loops.some(l => l.status === 'running');
    if (hasRunning) {
      const interval = setInterval(loadLoops, 5000);
      return () => clearInterval(interval);
    }
  }, [loops, loadLoops]);

  const handleStart = async (loop: RalphLoopSummary) => {
    try {
      await ralphLoopsApi.startLoop(loop.id);
      loadLoops();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to start loop');
    }
  };

  const handlePause = async (loop: RalphLoopSummary) => {
    try {
      await ralphLoopsApi.pauseLoop(loop.id);
      loadLoops();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to pause loop');
    }
  };

  const handleResume = async (loop: RalphLoopSummary) => {
    try {
      await ralphLoopsApi.resumeLoop(loop.id);
      loadLoops();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to resume loop');
    }
  };

  if (loading && loops.length === 0) {
    return (
      <div className="flex items-center justify-center p-8">
        <Loading size="lg" />
      </div>
    );
  }

  return (
    <div className={cn('space-y-4', className)}>
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold text-theme-text-primary">Ralph Loops</h2>
          <p className="text-sm text-theme-text-secondary">
            {totalCount} loop{totalCount !== 1 ? 's' : ''}
          </p>
        </div>
        <Button variant="primary" onClick={onCreateLoop}>
          <Plus className="w-4 h-4 mr-2" />
          New Loop
        </Button>
      </div>

      {/* Filters */}
      <div className="flex items-center gap-4">
        <Select
          value={statusFilter}
          onChange={(value) => setStatusFilter(value)}
          className="w-40"
        >
          {statusOptions.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </Select>
        <Select
          value={agentFilter}
          onChange={(value) => setAgentFilter(value)}
          className="w-48"
        >
          <option value="">All Agents</option>
          {agentOptions.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </Select>
        <Button variant="ghost" onClick={loadLoops} disabled={loading}>
          <RefreshCw className={cn('w-4 h-4', loading && 'animate-spin')} />
        </Button>
      </div>

      {/* Error */}
      {error && (
        <div className="p-4 rounded-lg bg-theme-status-error/10 text-theme-status-error">
          {error}
        </div>
      )}

      {/* Loop Grid */}
      {loops.length === 0 ? (
        <EmptyState
          icon={RotateCcw}
          title="No loops found"
          description={
            statusFilter || agentFilter
              ? 'Try adjusting your filters'
              : 'Create your first Ralph loop to start autonomous task execution'
          }
          action={
            !statusFilter && !agentFilter ? (
              <Button variant="primary" onClick={onCreateLoop}>
                <Plus className="w-4 h-4 mr-2" />
                New Loop
              </Button>
            ) : undefined
          }
        />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {loops.map((loop) => (
            <RalphLoopCard
              key={loop.id}
              loop={loop}
              onSelect={onSelectLoop}
              onStart={handleStart}
              onPause={handlePause}
              onResume={handleResume}
            />
          ))}
        </div>
      )}
    </div>
  );
};

export default RalphLoopList;
