import React, { useState } from 'react';
import {
  Power, AlertTriangle, PlayCircle,
} from 'lucide-react';
import { Card, CardContent, CardHeader } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePermissions } from '@/shared/hooks/usePermissions';
import {
  useKillSwitchStatus,
  useKillSwitchEvents,
  useEmergencyHalt,
  useEmergencyResume,
} from '../api/autonomyApi';

const KillSwitchButton: React.FC = () => {
  const { data: status, isLoading } = useKillSwitchStatus();
  const haltMutation = useEmergencyHalt();
  const resumeMutation = useEmergencyResume();
  const { addNotification } = useNotifications();
  const { hasPermission } = usePermissions();
  const [showConfirm, setShowConfirm] = useState(false);
  const [reason, setReason] = useState('');
  const [resumeMode, setResumeMode] = useState<'full' | 'minimal'>('full');

  const canManage = hasPermission('ai.kill_switch.manage');

  if (isLoading) return <LoadingSpinner size="sm" />;

  const halted = status?.halted ?? false;

  const handleHalt = async () => {
    try {
      await haltMutation.mutateAsync(reason || 'Manual emergency halt');
      addNotification({ type: 'warning', message: 'Emergency halt activated — all AI activity stopped' });
      setShowConfirm(false);
      setReason('');
    } catch {
      addNotification({ type: 'error', message: 'Failed to activate kill switch' });
    }
  };

  const handleResume = async () => {
    try {
      await resumeMutation.mutateAsync(resumeMode);
      addNotification({ type: 'success', message: `AI activity resumed (${resumeMode} mode)` });
      setShowConfirm(false);
    } catch {
      addNotification({ type: 'error', message: 'Failed to resume AI activity' });
    }
  };

  return (
    <div className="space-y-4">
      {/* Status indicator */}
      <div className={`flex items-center gap-3 p-4 rounded-lg border ${halted ? 'border-theme-error/50 bg-theme-error/5' : 'border-theme-success/50 bg-theme-success/5'}`}>
        <div className={`h-3 w-3 rounded-full ${halted ? 'bg-theme-error animate-pulse' : 'bg-theme-success'}`} />
        <div className="flex-1">
          <p className={`font-medium ${halted ? 'text-theme-error' : 'text-theme-success'}`}>
            {halted ? 'AI SUSPENDED' : 'AI Active'}
          </p>
          {halted && status?.halted_since && (
            <p className="text-sm text-theme-muted">Since {new Date(status.halted_since).toLocaleString()}</p>
          )}
          {halted && status?.reason && (
            <p className="text-sm text-theme-secondary mt-1">Reason: {status.reason}</p>
          )}
        </div>
        {canManage && !showConfirm && (
          <button
            onClick={() => setShowConfirm(true)}
            className={`btn-theme ${halted ? 'btn-theme-success' : 'btn-theme-danger'} btn-theme-sm flex items-center gap-2`}
          >
            {halted ? <PlayCircle className="h-4 w-4" /> : <Power className="h-4 w-4" />}
            {halted ? 'Resume' : 'Emergency Stop'}
          </button>
        )}
      </div>

      {/* Confirmation dialog */}
      {showConfirm && (
        <Card className="border-theme-warning/50">
          <CardContent className="p-4">
            {halted ? (
              /* Resume confirmation */
              <div className="space-y-3">
                <div className="flex items-center gap-2 text-theme-warning">
                  <PlayCircle className="h-5 w-5" />
                  <h4 className="font-medium">Resume AI Activity</h4>
                </div>
                {status?.snapshot_preview && (
                  <div className="bg-theme-surface rounded-lg p-3 text-sm space-y-1">
                    <p className="text-theme-secondary">Restore preview:</p>
                    <p className="text-theme-primary">{status.snapshot_preview.agents_to_restore} agents to restore trust tiers</p>
                    <p className="text-theme-primary">{status.snapshot_preview.ralph_loops_to_resume} Ralph loops to resume</p>
                    <p className="text-theme-primary">{status.snapshot_preview.workflow_schedules_to_resume} workflow schedules to re-enable</p>
                  </div>
                )}
                <div className="flex items-center gap-4">
                  <label className="flex items-center gap-2 cursor-pointer">
                    <input type="radio" checked={resumeMode === 'full'} onChange={() => setResumeMode('full')} className="text-theme-info" />
                    <span className="text-sm text-theme-primary">Full restore</span>
                  </label>
                  <label className="flex items-center gap-2 cursor-pointer">
                    <input type="radio" checked={resumeMode === 'minimal'} onChange={() => setResumeMode('minimal')} className="text-theme-info" />
                    <span className="text-sm text-theme-primary">Minimal (lift suspension only)</span>
                  </label>
                </div>
                <div className="flex gap-2">
                  <button onClick={handleResume} disabled={resumeMutation.isPending} className="btn-theme btn-theme-success btn-theme-sm">
                    {resumeMutation.isPending ? 'Resuming...' : 'Confirm Resume'}
                  </button>
                  <button onClick={() => setShowConfirm(false)} className="btn-theme btn-theme-secondary btn-theme-sm">Cancel</button>
                </div>
              </div>
            ) : (
              /* Halt confirmation */
              <div className="space-y-3">
                <div className="flex items-center gap-2 text-theme-error">
                  <AlertTriangle className="h-5 w-5" />
                  <h4 className="font-medium">Confirm Emergency Stop</h4>
                </div>
                <p className="text-sm text-theme-secondary">
                  This will immediately halt ALL AI agent activity: cancel running executions, pause schedules, block LLM calls, and demote all agents to supervised.
                </p>
                <input
                  type="text"
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="Reason for emergency halt..."
                  className="w-full px-3 py-2 text-sm rounded-md border border-theme bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-error"
                />
                <div className="flex gap-2">
                  <button onClick={handleHalt} disabled={haltMutation.isPending} className="btn-theme btn-theme-danger btn-theme-sm">
                    {haltMutation.isPending ? 'Halting...' : 'Confirm Emergency Stop'}
                  </button>
                  <button onClick={() => setShowConfirm(false)} className="btn-theme btn-theme-secondary btn-theme-sm">Cancel</button>
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      )}
    </div>
  );
};

const KillSwitchEventLog: React.FC = () => {
  const { data: events, isLoading } = useKillSwitchEvents();

  if (isLoading) return <LoadingSpinner size="sm" className="py-4" />;
  if (!events || events.length === 0) {
    return (
      <p className="text-sm text-theme-muted text-center py-4">No kill switch events recorded</p>
    );
  }

  return (
    <div className="space-y-2">
      {events.map((event) => (
        <div key={event.id} className="flex items-start gap-3 p-3 bg-theme-surface rounded-lg border border-theme">
          {event.event_type === 'halt' ? (
            <Power className="h-4 w-4 text-theme-error mt-0.5 shrink-0" />
          ) : (
            <PlayCircle className="h-4 w-4 text-theme-success mt-0.5 shrink-0" />
          )}
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <span className={`text-sm font-medium ${event.event_type === 'halt' ? 'text-theme-error' : 'text-theme-success'}`}>
                {event.event_type === 'halt' ? 'Emergency Halt' : 'Resumed'}
              </span>
              <span className="text-xs text-theme-muted">{new Date(event.created_at).toLocaleString()}</span>
            </div>
            <p className="text-sm text-theme-secondary truncate">{event.reason}</p>
            {event.triggered_by_name && (
              <p className="text-xs text-theme-muted">by {event.triggered_by_name}</p>
            )}
          </div>
        </div>
      ))}
    </div>
  );
};

export const KillSwitchPanel: React.FC = () => (
  <div className="space-y-6">
    <Card>
      <CardHeader title="Emergency Kill Switch" />
      <CardContent>
        <KillSwitchButton />
      </CardContent>
    </Card>
    <Card>
      <CardHeader title="Event History" />
      <CardContent>
        <KillSwitchEventLog />
      </CardContent>
    </Card>
  </div>
);
