import React from 'react';
import { Box, Pause, Play, Trash2, Activity } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Progress } from '@/shared/components/ui/Progress';
import type { SandboxInstance, SandboxStatus, TrustLevel } from '../types/sandbox';

interface SandboxCardProps {
  sandbox: SandboxInstance;
  onPause: (id: string) => void;
  onResume: (id: string) => void;
  onDestroy: (id: string) => void;
  actionLoading?: string | null;
}

const STATUS_BADGE_VARIANT: Record<SandboxStatus, 'success' | 'warning' | 'danger' | 'info' | 'secondary' | 'default'> = {
  pending: 'secondary',
  running: 'success',
  paused: 'warning',
  completed: 'info',
  failed: 'danger',
  cancelled: 'default',
};

const TRUST_BADGE_VARIANT: Record<TrustLevel, 'warning' | 'info' | 'success' | 'primary'> = {
  supervised: 'warning',
  monitored: 'info',
  trusted: 'success',
  autonomous: 'primary',
};

const formatBytes = (bytes: number): string => {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
};

export const SandboxCard: React.FC<SandboxCardProps> = ({
  sandbox,
  onPause,
  onResume,
  onDestroy,
  actionLoading,
}) => {
  const isRunning = sandbox.status === 'running';
  const isPaused = sandbox.status === 'paused';
  const isActive = isRunning || isPaused;
  const isActionLoading = actionLoading === sandbox.id;

  return (
    <Card className="p-5">
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-start gap-3">
          <div className="h-10 w-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
            <Box className="h-5 w-5 text-theme-info" />
          </div>
          <div>
            <h3 className="font-semibold text-theme-primary">{sandbox.agent_name}</h3>
            <p className="text-xs text-theme-tertiary mt-0.5">{sandbox.template_name}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <Badge variant={TRUST_BADGE_VARIANT[sandbox.trust_level]} size="xs">
            {sandbox.trust_level}
          </Badge>
          <Badge
            variant={STATUS_BADGE_VARIANT[sandbox.status]}
            size="sm"
            dot={isRunning}
            pulse={isRunning}
          >
            {sandbox.status}
          </Badge>
        </div>
      </div>

      <div className="space-y-3">
        <div className="flex items-center justify-between text-sm">
          <span className="text-theme-tertiary">Image</span>
          <span className="text-theme-primary text-xs font-mono">
            {sandbox.image_name}:{sandbox.image_tag}
          </span>
        </div>

        {sandbox.cpu_used_millicores !== undefined && (
          <div className="space-y-1">
            <div className="flex items-center justify-between text-sm">
              <span className="text-theme-tertiary flex items-center gap-1">
                <Activity className="h-3 w-3" /> CPU
              </span>
              <span className="text-theme-primary text-xs">
                {sandbox.cpu_used_millicores}m
              </span>
            </div>
            <Progress
              value={sandbox.cpu_used_millicores}
              max={1000}
              size="sm"
              variant={sandbox.cpu_used_millicores > 800 ? 'error' : sandbox.cpu_used_millicores > 500 ? 'warning' : 'default'}
            />
          </div>
        )}

        {sandbox.memory_used_mb !== undefined && (
          <div className="space-y-1">
            <div className="flex items-center justify-between text-sm">
              <span className="text-theme-tertiary">Memory</span>
              <span className="text-theme-primary text-xs">
                {sandbox.memory_used_mb} MB
              </span>
            </div>
            <Progress
              value={sandbox.memory_used_mb}
              max={512}
              size="sm"
              variant={sandbox.memory_used_mb > 400 ? 'error' : sandbox.memory_used_mb > 256 ? 'warning' : 'default'}
            />
          </div>
        )}

        {sandbox.storage_used_bytes !== undefined && (
          <div className="flex items-center justify-between text-sm">
            <span className="text-theme-tertiary">Storage</span>
            <span className="text-theme-primary text-xs">
              {formatBytes(sandbox.storage_used_bytes)}
            </span>
          </div>
        )}
      </div>

      {isActive && (
        <div className="flex items-center gap-2 mt-4 pt-4 border-t border-theme">
          {isRunning && (
            <Button
              variant="warning"
              size="sm"
              disabled={isActionLoading}
              className="flex items-center gap-1.5"
              onClick={() => onPause(sandbox.id)}
            >
              <Pause className="h-3 w-3" />
              Pause
            </Button>
          )}
          {isPaused && (
            <Button
              variant="success"
              size="sm"
              disabled={isActionLoading}
              className="flex items-center gap-1.5"
              onClick={() => onResume(sandbox.id)}
            >
              <Play className="h-3 w-3" />
              Resume
            </Button>
          )}
          <Button
            variant="danger"
            size="sm"
            disabled={isActionLoading}
            className="flex items-center gap-1.5 ml-auto"
            onClick={() => onDestroy(sandbox.id)}
          >
            <Trash2 className="h-3 w-3" />
            Destroy
          </Button>
        </div>
      )}
    </Card>
  );
};
