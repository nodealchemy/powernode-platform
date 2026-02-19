import React, { useState, useCallback, useEffect } from 'react';
import { Box, Filter } from 'lucide-react';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { fetchSandboxes, pauseSandbox, resumeSandbox, destroySandbox } from '../api/sandboxApi';
import { SandboxCard } from './SandboxCard';
import type { SandboxInstance, SandboxStatus } from '../types/sandbox';

const STATUS_FILTERS: { label: string; value: SandboxStatus | '' }[] = [
  { label: 'All', value: '' },
  { label: 'Running', value: 'running' },
  { label: 'Paused', value: 'paused' },
  { label: 'Completed', value: 'completed' },
  { label: 'Failed', value: 'failed' },
];

interface SandboxListProps {
  refreshKey?: number;
}

export const SandboxList: React.FC<SandboxListProps> = ({ refreshKey }) => {
  const [sandboxes, setSandboxes] = useState<SandboxInstance[]>([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState<SandboxStatus | ''>('');
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const { addNotification } = useNotifications();

  const loadSandboxes = useCallback(async () => {
    try {
      setLoading(true);
      const data = await fetchSandboxes();
      setSandboxes(data);
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to load sandboxes' });
    } finally {
      setLoading(false);
    }
  }, [addNotification]);

  useEffect(() => {
    loadSandboxes();
  }, [loadSandboxes, refreshKey]);

  const handlePause = async (id: string) => {
    try {
      setActionLoading(id);
      await pauseSandbox(id);
      addNotification({ type: 'success', message: 'Sandbox paused' });
      loadSandboxes();
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to pause sandbox' });
    } finally {
      setActionLoading(null);
    }
  };

  const handleResume = async (id: string) => {
    try {
      setActionLoading(id);
      await resumeSandbox(id);
      addNotification({ type: 'success', message: 'Sandbox resumed' });
      loadSandboxes();
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to resume sandbox' });
    } finally {
      setActionLoading(null);
    }
  };

  const handleDestroy = async (id: string) => {
    try {
      setActionLoading(id);
      await destroySandbox(id);
      addNotification({ type: 'success', message: 'Sandbox destroyed' });
      loadSandboxes();
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to destroy sandbox' });
    } finally {
      setActionLoading(null);
    }
  };

  const filtered = statusFilter
    ? sandboxes.filter((s) => s.status === statusFilter)
    : sandboxes;

  if (loading) {
    return <LoadingSpinner size="lg" className="py-12" message="Loading sandboxes..." />;
  }

  return (
    <div className="space-y-4">
      {/* Status filter */}
      <Card>
        <CardContent className="p-4">
          <div className="flex items-center gap-3">
            <Filter className="w-4 h-4 text-theme-muted" />
            <div className="flex flex-wrap gap-2">
              {STATUS_FILTERS.map((f) => (
                <button
                  key={f.value}
                  onClick={() => setStatusFilter(f.value)}
                  className={`px-3 py-1.5 text-sm rounded transition-colors ${
                    statusFilter === f.value
                      ? 'bg-theme-interactive-primary/10 text-theme-accent'
                      : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover'
                  }`}
                >
                  {f.label}
                </button>
              ))}
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Results */}
      {filtered.length === 0 ? (
        <EmptyState
          icon={Box}
          title="No sandboxes found"
          description={
            statusFilter
              ? `No sandboxes with status "${statusFilter}". Try a different filter.`
              : 'No agent sandboxes have been created yet.'
          }
        />
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          {filtered.map((sandbox) => (
            <SandboxCard
              key={sandbox.id}
              sandbox={sandbox}
              onPause={handlePause}
              onResume={handleResume}
              onDestroy={handleDestroy}
              actionLoading={actionLoading}
            />
          ))}
        </div>
      )}
    </div>
  );
};
