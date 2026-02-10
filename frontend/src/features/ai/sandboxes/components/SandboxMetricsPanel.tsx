import React, { useState, useCallback, useEffect, useRef } from 'react';
import { Activity, HardDrive, Wifi, Clock } from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { Progress } from '@/shared/components/ui/Progress';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { fetchSandboxMetrics } from '../api/sandboxApi';
import type { SandboxMetrics } from '../types/sandbox';

interface SandboxMetricsPanelProps {
  sandboxId: string;
}

const formatBytes = (bytes: number): string => {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
};

const formatUptime = (seconds: number): string => {
  const hrs = Math.floor(seconds / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;
  if (hrs > 0) return `${hrs}h ${mins}m ${secs}s`;
  if (mins > 0) return `${mins}m ${secs}s`;
  return `${secs}s`;
};

export const SandboxMetricsPanel: React.FC<SandboxMetricsPanelProps> = ({ sandboxId }) => {
  const [metrics, setMetrics] = useState<SandboxMetrics | null>(null);
  const [loading, setLoading] = useState(true);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const loadMetrics = useCallback(async () => {
    try {
      const data = await fetchSandboxMetrics(sandboxId);
      setMetrics(data);
    } catch {
      // Silently fail on poll — don't spam notifications
    } finally {
      setLoading(false);
    }
  }, [sandboxId]);

  useEffect(() => {
    loadMetrics();
    intervalRef.current = setInterval(loadMetrics, 5000);
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [loadMetrics]);

  if (loading) return <LoadingSpinner />;
  if (!metrics) return null;

  return (
    <Card>
      <CardHeader title="Real-time Metrics" icon={<Activity className="h-5 w-5" />} />
      <CardContent>
        <div className="space-y-4">
          {/* CPU */}
          {metrics.cpu_used_millicores !== undefined && (
            <div className="space-y-1">
              <div className="flex items-center justify-between text-sm">
                <span className="text-theme-secondary flex items-center gap-1.5">
                  <Activity className="h-3.5 w-3.5" /> CPU
                </span>
                <span className="text-theme-primary font-medium">
                  {metrics.cpu_used_millicores}m / 1000m
                </span>
              </div>
              <Progress
                value={metrics.cpu_used_millicores}
                max={1000}
                size="md"
                variant={
                  metrics.cpu_used_millicores > 800
                    ? 'error'
                    : metrics.cpu_used_millicores > 500
                      ? 'warning'
                      : 'default'
                }
              />
            </div>
          )}

          {/* Memory */}
          {metrics.memory_used_mb !== undefined && (
            <div className="space-y-1">
              <div className="flex items-center justify-between text-sm">
                <span className="text-theme-secondary flex items-center gap-1.5">
                  <HardDrive className="h-3.5 w-3.5" /> Memory
                </span>
                <span className="text-theme-primary font-medium">
                  {metrics.memory_used_mb} MB / 512 MB
                </span>
              </div>
              <Progress
                value={metrics.memory_used_mb}
                max={512}
                size="md"
                variant={
                  metrics.memory_used_mb > 400
                    ? 'error'
                    : metrics.memory_used_mb > 256
                      ? 'warning'
                      : 'default'
                }
              />
            </div>
          )}

          {/* Storage */}
          {metrics.storage_used_bytes !== undefined && (
            <div className="space-y-1">
              <div className="flex items-center justify-between text-sm">
                <span className="text-theme-secondary flex items-center gap-1.5">
                  <HardDrive className="h-3.5 w-3.5" /> Storage
                </span>
                <span className="text-theme-primary font-medium">
                  {formatBytes(metrics.storage_used_bytes)}
                </span>
              </div>
              <Progress
                value={metrics.storage_used_bytes}
                max={1024 * 1024 * 1024}
                size="md"
              />
            </div>
          )}

          {/* Network */}
          {(metrics.network_bytes_in !== undefined || metrics.network_bytes_out !== undefined) && (
            <div className="flex items-center justify-between text-sm p-3 rounded-lg bg-theme-surface border border-theme-border">
              <span className="text-theme-secondary flex items-center gap-1.5">
                <Wifi className="h-3.5 w-3.5" /> Network
              </span>
              <div className="text-right text-xs">
                {metrics.network_bytes_in !== undefined && (
                  <p className="text-theme-primary">
                    In: {formatBytes(metrics.network_bytes_in)}
                  </p>
                )}
                {metrics.network_bytes_out !== undefined && (
                  <p className="text-theme-primary">
                    Out: {formatBytes(metrics.network_bytes_out)}
                  </p>
                )}
              </div>
            </div>
          )}

          {/* Uptime */}
          {metrics.uptime_seconds !== undefined && (
            <div className="flex items-center justify-between text-sm p-3 rounded-lg bg-theme-surface border border-theme-border">
              <span className="text-theme-secondary flex items-center gap-1.5">
                <Clock className="h-3.5 w-3.5" /> Uptime
              </span>
              <span className="text-theme-primary font-medium">
                {formatUptime(metrics.uptime_seconds)}
              </span>
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
};
