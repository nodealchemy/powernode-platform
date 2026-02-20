import { useState, useEffect, useCallback } from 'react';
import { Wrench, Loader2, RefreshCw } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { skillLifecycleApi } from '../services/skillLifecycleApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { SkillHealthMetrics } from './SkillHealthMetrics';
import { ConsolidationSuggestionCard } from './ConsolidationSuggestionCard';
import type { SkillConflict } from '../types/lifecycle';

export function OptimizationDashboard() {
  const { showNotification } = useNotifications();
  const [conflicts, setConflicts] = useState<SkillConflict[]>([]);
  const [loadingConflicts, setLoadingConflicts] = useState(true);
  const [scanning, setScanning] = useState(false);
  const [optimizing, setOptimizing] = useState(false);

  const loadConflicts = useCallback(async () => {
    setLoadingConflicts(true);
    const response = await skillLifecycleApi.getConflicts();
    if (response.success && response.data) {
      setConflicts(response.data.conflicts);
    }
    setLoadingConflicts(false);
  }, []);

  useEffect(() => {
    loadConflicts();
  }, [loadConflicts]);

  const handleScan = async () => {
    setScanning(true);
    const response = await skillLifecycleApi.scanConflicts();
    if (response.success) {
      const summary = response.data?.summary;
      const total = summary ? Object.values(summary).reduce((a, b) => a + b, 0) : 0;
      showNotification(`Scan complete: ${total} conflict(s) found`, 'success');
      loadConflicts();
    } else {
      showNotification(response.error || 'Scan failed', 'error');
    }
    setScanning(false);
  };

  const handleOptimize = async () => {
    setOptimizing(true);
    const response = await skillLifecycleApi.runOptimization('full');
    if (response.success) {
      showNotification('Optimization complete', 'success');
      loadConflicts();
    } else {
      showNotification(response.error || 'Optimization failed', 'error');
    }
    setOptimizing(false);
  };

  return (
    <div className="space-y-6" data-testid="optimization-dashboard">
      {/* Actions */}
      <div className="flex gap-3">
        <Button variant="secondary" size="sm" onClick={handleScan} disabled={scanning}>
          {scanning ? <Loader2 className="w-3.5 h-3.5 mr-1.5 animate-spin" /> : <RefreshCw className="w-3.5 h-3.5 mr-1.5" />}
          Scan for Conflicts
        </Button>
        <Button variant="primary" size="sm" onClick={handleOptimize} disabled={optimizing}>
          {optimizing ? <Loader2 className="w-3.5 h-3.5 mr-1.5 animate-spin" /> : <Wrench className="w-3.5 h-3.5 mr-1.5" />}
          Run Optimization
        </Button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Health Metrics */}
        <div>
          <h3 className="text-sm font-medium text-theme-primary mb-3">Health Score</h3>
          <SkillHealthMetrics />
        </div>

        {/* Conflicts */}
        <div>
          <h3 className="text-sm font-medium text-theme-primary mb-3">
            Active Conflicts ({conflicts.length})
          </h3>
          {loadingConflicts ? (
            <div className="flex justify-center py-8">
              <LoadingSpinner />
            </div>
          ) : conflicts.length === 0 ? (
            <EmptyState
              title="No conflicts"
              description="The skill graph is healthy. Run a scan to check for new issues."
            />
          ) : (
            <div className="space-y-2 max-h-[500px] overflow-y-auto pr-1">
              {conflicts.map((conflict) => (
                <ConsolidationSuggestionCard
                  key={conflict.id}
                  conflict={conflict}
                  onResolved={loadConflicts}
                />
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
