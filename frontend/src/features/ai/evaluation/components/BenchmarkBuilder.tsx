import React, { useState, useCallback, useEffect } from 'react';
import { Plus, Play, Pause, Archive, RefreshCw } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { fetchBenchmarks, createBenchmark, runBenchmark } from '../api/evaluationApi';
import type { PerformanceBenchmark } from '../types/evaluation';
import { apiClient } from '@/shared/services/apiClient';

interface Agent {
  id: string;
  name: string;
}

export const BenchmarkBuilder: React.FC = () => {
  const [loading, setLoading] = useState(true);
  const [benchmarks, setBenchmarks] = useState<PerformanceBenchmark[]>([]);
  const [agents, setAgents] = useState<Agent[]>([]);
  const [showCreate, setShowCreate] = useState(false);
  const [creating, setCreating] = useState(false);
  const [runningId, setRunningId] = useState<string | null>(null);
  const [formName, setFormName] = useState('');
  const [formAgentId, setFormAgentId] = useState('');
  const { addNotification } = useNotifications();

  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      const [benchData, agentRes] = await Promise.all([
        fetchBenchmarks(),
        apiClient.get('/ai/agents', { params: { status: 'active', limit: 100 } }),
      ]);
      setBenchmarks(benchData);
      setAgents(agentRes.data?.agents || []);
    } catch {
      addNotification({ type: 'error', message: 'Failed to load benchmarks' });
    } finally {
      setLoading(false);
    }
  }, [addNotification]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const handleCreate = async () => {
    if (!formName.trim()) return;
    try {
      setCreating(true);
      await createBenchmark({
        name: formName,
        agent_id: formAgentId || undefined,
        thresholds: { correctness: 3.0, completeness: 3.0, helpfulness: 3.0, safety: 4.0 },
      });
      addNotification({ type: 'success', message: 'Benchmark created' });
      setShowCreate(false);
      setFormName('');
      setFormAgentId('');
      loadData();
    } catch {
      addNotification({ type: 'error', message: 'Failed to create benchmark' });
    } finally {
      setCreating(false);
    }
  };

  const handleRun = async (id: string) => {
    try {
      setRunningId(id);
      await runBenchmark(id);
      addNotification({ type: 'success', message: 'Benchmark run complete' });
      loadData();
    } catch {
      addNotification({ type: 'error', message: 'Failed to run benchmark' });
    } finally {
      setRunningId(null);
    }
  };

  if (loading) return <LoadingSpinner />;

  const statusVariant = (status: string) => {
    switch (status) {
      case 'active': return 'success' as const;
      case 'paused': return 'warning' as const;
      case 'archived': return 'default' as const;
      default: return 'default' as const;
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-medium text-theme-primary">Benchmarks ({benchmarks.length})</h3>
        <button
          onClick={() => setShowCreate(!showCreate)}
          className="flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium bg-theme-primary text-white rounded-md hover:opacity-90"
        >
          <Plus className="w-4 h-4" />
          New Benchmark
        </button>
      </div>

      {showCreate && (
        <Card>
          <CardHeader title="Create Benchmark" />
          <CardContent>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-theme-secondary mb-1">Name</label>
                <input
                  type="text"
                  value={formName}
                  onChange={(e) => setFormName(e.target.value)}
                  placeholder="e.g., Weekly Agent Quality Check"
                  className="w-full px-3 py-2 text-sm bg-theme-surface border border-theme-border rounded-md text-theme-primary"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-secondary mb-1">Target Agent</label>
                <select
                  value={formAgentId}
                  onChange={(e) => setFormAgentId(e.target.value)}
                  className="w-full px-3 py-2 text-sm bg-theme-surface border border-theme-border rounded-md text-theme-primary"
                >
                  <option value="">Select an agent</option>
                  {agents.map((a) => (
                    <option key={a.id} value={a.id}>{a.name}</option>
                  ))}
                </select>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={handleCreate}
                  disabled={creating || !formName.trim()}
                  className="px-4 py-2 text-sm font-medium bg-theme-primary text-white rounded-md hover:opacity-90 disabled:opacity-50"
                >
                  {creating ? 'Creating...' : 'Create'}
                </button>
                <button
                  onClick={() => setShowCreate(false)}
                  className="px-4 py-2 text-sm font-medium bg-theme-surface border border-theme-border rounded-md hover:bg-theme-surface-hover"
                >
                  Cancel
                </button>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {benchmarks.length === 0 ? (
        <Card>
          <CardContent className="p-8 text-center text-theme-muted">
            <RefreshCw className="w-12 h-12 mx-auto mb-3 opacity-30" />
            <p>No benchmarks created yet. Create one to start tracking agent quality over time.</p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-3">
          {benchmarks.map((bench) => (
            <Card key={bench.id}>
              <CardContent className="p-4">
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <div className="flex items-center gap-2 mb-1">
                      <span className="font-medium text-theme-primary">{bench.name}</span>
                      <Badge variant={statusVariant(bench.status)}>{bench.status}</Badge>
                      {bench.trend && (
                        <Badge variant={
                          bench.trend === 'improving' ? 'success' :
                          bench.trend === 'declining' ? 'danger' : 'default'
                        }>
                          {bench.trend}
                        </Badge>
                      )}
                    </div>
                    <div className="flex items-center gap-4 text-xs text-theme-muted mt-1">
                      {bench.latest_score !== null && (
                        <span>Latest Score: {bench.latest_score}</span>
                      )}
                      {bench.last_run_at && (
                        <span>Last Run: {new Date(bench.last_run_at).toLocaleDateString()}</span>
                      )}
                      <span>Created: {new Date(bench.created_at).toLocaleDateString()}</span>
                    </div>
                    {bench.thresholds && Object.keys(bench.thresholds).length > 0 && (
                      <div className="flex items-center gap-2 mt-2">
                        {Object.entries(bench.thresholds).map(([key, val]) => (
                          <span key={key} className="text-xs px-1.5 py-0.5 rounded bg-theme-surface-hover text-theme-muted">
                            {key}: {val}
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                  <div className="flex items-center gap-1 ml-4">
                    {bench.status === 'active' && (
                      <button
                        onClick={() => handleRun(bench.id)}
                        disabled={runningId === bench.id}
                        className="p-1.5 rounded-md hover:bg-theme-surface-hover text-theme-secondary"
                        title="Run benchmark"
                      >
                        {runningId === bench.id ? (
                          <RefreshCw className="w-4 h-4 animate-spin" />
                        ) : (
                          <Play className="w-4 h-4" />
                        )}
                      </button>
                    )}
                    <button
                      className="p-1.5 rounded-md hover:bg-theme-surface-hover text-theme-muted"
                      title={bench.status === 'active' ? 'Pause' : 'Archive'}
                    >
                      {bench.status === 'active' ? (
                        <Pause className="w-4 h-4" />
                      ) : (
                        <Archive className="w-4 h-4" />
                      )}
                    </button>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
};
