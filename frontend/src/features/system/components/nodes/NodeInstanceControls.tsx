import React, { useState, useCallback } from 'react';
import { Play, Square, RotateCw, MoreVertical, Power } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemNodeInstance } from '@/features/system/types/system.types';

interface NodeInstanceControlsProps {
  /** The instance to control */
  instance: SystemNodeInstance;
  /** Callback when an action completes */
  onActionComplete?: () => void;
  /** Show as compact dropdown menu */
  compact?: boolean;
  /** Additional CSS classes */
  className?: string;
}

/**
 * NodeInstanceControls - Control buttons for node instances
 *
 * Provides Start, Stop, and Reboot actions for node instances
 * with permission checks and loading states.
 */
export const NodeInstanceControls: React.FC<NodeInstanceControlsProps> = ({
  instance,
  onActionComplete,
  compact = false,
  className = ''
}) => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();
  const [loading, setLoading] = useState<string | null>(null);
  const [showMenu, setShowMenu] = useState(false);

  const canControl = hasPermission('system.instances.control');

  // Determine available actions based on instance status
  const isRunning = instance.status === 'running';
  const isStopped = instance.status === 'stopped';
  const isPending = instance.status === 'pending' || instance.status === 'starting' || instance.status === 'stopping';

  // Action handlers
  const handleAction = useCallback(async (action: 'start' | 'stop' | 'reboot') => {
    if (!canControl) return;

    setLoading(action);
    setShowMenu(false);

    try {
      switch (action) {
        case 'start':
          await systemApi.startInstance(instance.node_id, instance.id);
          addNotification({
            type: 'success',
            message: `Starting instance ${instance.name}...`
          });
          break;
        case 'stop':
          await systemApi.stopInstance(instance.node_id, instance.id);
          addNotification({
            type: 'success',
            message: `Stopping instance ${instance.name}...`
          });
          break;
        case 'reboot':
          await systemApi.rebootInstance(instance.node_id, instance.id);
          addNotification({
            type: 'success',
            message: `Rebooting instance ${instance.name}...`
          });
          break;
      }
      onActionComplete?.();
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'An error occurred';
      addNotification({
        type: 'error',
        message: `Failed to ${action} instance: ${errorMessage}`
      });
    } finally {
      setLoading(null);
    }
  }, [canControl, instance.id, instance.name, addNotification, onActionComplete]);

  if (!canControl) {
    return null;
  }

  // Compact dropdown mode
  if (compact) {
    return (
      <div className={`relative ${className}`}>
        <Button
          variant="ghost"
          size="sm"
          onClick={() => setShowMenu(!showMenu)}
          disabled={isPending}
          className="p-1"
        >
          <MoreVertical className="w-4 h-4" />
        </Button>

        {showMenu && (
          <>
            {/* Backdrop to close menu */}
            <div
              className="fixed inset-0 z-10"
              onClick={() => setShowMenu(false)}
            />
            {/* Menu */}
            <div className="absolute right-0 top-full mt-1 z-20 bg-theme-surface border border-theme rounded-lg shadow-lg py-1 min-w-[120px]">
              {isStopped && (
                <button
                  onClick={() => handleAction('start')}
                  disabled={loading === 'start'}
                  className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover disabled:opacity-50"
                >
                  <Play className="w-4 h-4 text-theme-success" />
                  {loading === 'start' ? 'Starting...' : 'Start'}
                </button>
              )}
              {isRunning && (
                <>
                  <button
                    onClick={() => handleAction('stop')}
                    disabled={loading === 'stop'}
                    className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover disabled:opacity-50"
                  >
                    <Square className="w-4 h-4 text-theme-danger" />
                    {loading === 'stop' ? 'Stopping...' : 'Stop'}
                  </button>
                  <button
                    onClick={() => handleAction('reboot')}
                    disabled={loading === 'reboot'}
                    className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover disabled:opacity-50"
                  >
                    <RotateCw className="w-4 h-4 text-theme-warning" />
                    {loading === 'reboot' ? 'Rebooting...' : 'Reboot'}
                  </button>
                </>
              )}
              {!isRunning && !isStopped && (
                <div className="px-3 py-2 text-sm text-theme-secondary">
                  Instance is {instance.status}
                </div>
              )}
            </div>
          </>
        )}
      </div>
    );
  }

  // Standard button mode
  return (
    <div className={`flex items-center gap-2 ${className}`}>
      {isStopped && (
        <Button
          variant="success"
          size="sm"
          onClick={() => handleAction('start')}
          disabled={loading !== null}
          className="flex items-center gap-1"
        >
          {loading === 'start' ? (
            <>
              <RotateCw className="w-4 h-4 animate-spin" />
              Starting...
            </>
          ) : (
            <>
              <Play className="w-4 h-4" />
              Start
            </>
          )}
        </Button>
      )}

      {isRunning && (
        <>
          <Button
            variant="danger"
            size="sm"
            onClick={() => handleAction('stop')}
            disabled={loading !== null}
            className="flex items-center gap-1"
          >
            {loading === 'stop' ? (
              <>
                <RotateCw className="w-4 h-4 animate-spin" />
                Stopping...
              </>
            ) : (
              <>
                <Square className="w-4 h-4" />
                Stop
              </>
            )}
          </Button>
          <Button
            variant="warning"
            size="sm"
            onClick={() => handleAction('reboot')}
            disabled={loading !== null}
            className="flex items-center gap-1"
          >
            {loading === 'reboot' ? (
              <>
                <RotateCw className="w-4 h-4 animate-spin" />
                Rebooting...
              </>
            ) : (
              <>
                <RotateCw className="w-4 h-4" />
                Reboot
              </>
            )}
          </Button>
        </>
      )}

      {isPending && (
        <div className="flex items-center gap-2 text-sm text-theme-secondary">
          <Power className="w-4 h-4 animate-pulse" />
          <span className="capitalize">{instance.status}...</span>
        </div>
      )}
    </div>
  );
};

export default NodeInstanceControls;
