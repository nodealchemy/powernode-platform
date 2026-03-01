import React from 'react';
import { Play, CheckCircle, XCircle, Clock, Ban } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import type { AguiSession, AguiSessionStatus } from '../types/agui';

interface AguiRunStatusProps {
  session: AguiSession;
}

const STATUS_CONFIG: Record<AguiSessionStatus, {
  icon: React.FC<{ className?: string }>;
  variant: 'default' | 'primary' | 'success' | 'danger' | 'warning';
  label: string;
  description: string;
}> = {
  idle: {
    icon: Clock,
    variant: 'default',
    label: 'Idle',
    description: 'Session is idle, waiting for input',
  },
  running: {
    icon: Play,
    variant: 'primary',
    label: 'Running',
    description: 'Agent is actively processing',
  },
  completed: {
    icon: CheckCircle,
    variant: 'success',
    label: 'Completed',
    description: 'Run finished successfully',
  },
  error: {
    icon: XCircle,
    variant: 'danger',
    label: 'Error',
    description: 'Run encountered an error',
  },
  cancelled: {
    icon: Ban,
    variant: 'warning',
    label: 'Cancelled',
    description: 'Run was cancelled',
  },
};

export const AguiRunStatus: React.FC<AguiRunStatusProps> = ({ session }) => {
  const config = STATUS_CONFIG[session.status];
  const Icon = config.icon;

  return (
    <div className="bg-theme-card border border-theme rounded-lg p-4">
      <div className="flex items-center gap-3 mb-3">
        <div className={`h-10 w-10 rounded-lg flex items-center justify-center bg-theme-surface`}>
          <Icon className="h-5 w-5 text-theme-interactive-primary" />
        </div>
        <div>
          <div className="flex items-center gap-2">
            <span className="text-sm font-semibold text-theme-primary">{config.label}</span>
            <Badge variant={config.variant} size="xs">
              {session.status}
            </Badge>
          </div>
          <p className="text-xs text-theme-tertiary">{config.description}</p>
        </div>
      </div>
      <div className="grid grid-cols-2 gap-3 text-xs">
        <div>
          <span className="text-theme-tertiary">Thread</span>
          <p className="text-theme-primary font-mono truncate">{session.thread_id}</p>
        </div>
        {session.run_id && (
          <div>
            <span className="text-theme-tertiary">Run ID</span>
            <p className="text-theme-primary font-mono truncate">{session.run_id}</p>
          </div>
        )}
        <div>
          <span className="text-theme-tertiary">Sequence</span>
          <p className="text-theme-primary">{session.sequence_number}</p>
        </div>
        {session.started_at && (
          <div>
            <span className="text-theme-tertiary">Started</span>
            <p className="text-theme-primary">{new Date(session.started_at).toLocaleString()}</p>
          </div>
        )}
        {session.completed_at && (
          <div>
            <span className="text-theme-tertiary">Completed</span>
            <p className="text-theme-primary">{new Date(session.completed_at).toLocaleString()}</p>
          </div>
        )}
        {session.expires_at && (
          <div>
            <span className="text-theme-tertiary">Expires</span>
            <p className="text-theme-primary">{new Date(session.expires_at).toLocaleString()}</p>
          </div>
        )}
      </div>
      {session.tools.length > 0 && (
        <div className="mt-3 pt-3 border-t border-theme">
          <span className="text-xs text-theme-tertiary block mb-1">
            Tools ({session.tools.length})
          </span>
          <div className="flex flex-wrap gap-1">
            {session.tools.map((tool) => (
              <Badge key={tool} variant="outline" size="xs">
                {tool}
              </Badge>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};
