import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Rocket, Plus, ArrowRight, Clock, AlertCircle,
  CheckCircle, Loader2, Pause, XCircle, GitBranch
} from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Progress } from '@/shared/components/ui/Progress';
import { missionsApi } from '@/features/missions/api/missionsApi';
import { phaseLabel, isApprovalGate } from '@/features/missions/types/mission';
import type { Mission, MissionStatus } from '@/features/missions/types/mission';

const STATUS_CONFIG: Record<MissionStatus, { icon: React.ElementType; color: string; variant: 'success' | 'warning' | 'danger' | 'info' | 'secondary' }> = {
  active: { icon: Loader2, color: 'text-theme-info', variant: 'info' },
  paused: { icon: Pause, color: 'text-theme-warning', variant: 'warning' },
  draft: { icon: Clock, color: 'text-theme-secondary', variant: 'secondary' },
  completed: { icon: CheckCircle, color: 'text-theme-success', variant: 'success' },
  failed: { icon: XCircle, color: 'text-theme-danger', variant: 'danger' },
  cancelled: { icon: XCircle, color: 'text-theme-secondary', variant: 'secondary' },
};

const TYPE_EMOJI: Record<string, string> = {
  development: '\u{1F6E0}',
  research: '\u{1F52C}',
  operations: '\u{2699}',
};

function formatDuration(ms: number | null): string {
  if (!ms) return '-';
  const seconds = Math.floor(ms / 1000);
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  return `${hours}h ${remainingMinutes}m`;
}

function timeAgo(dateStr: string): string {
  const diff = Date.now() - new Date(dateStr).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

export const MissionsDashboardPanel: React.FC = () => {
  const navigate = useNavigate();
  const [missions, setMissions] = useState<Mission[]>([]);
  const [loading, setLoading] = useState(true);

  const loadMissions = useCallback(async () => {
    try {
      const res = await missionsApi.getMissions();
      setMissions(res.data.missions || []);
    } catch {
      // Silently handle — panel is supplementary
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadMissions();
    const interval = setInterval(loadMissions, 15000);
    return () => clearInterval(interval);
  }, [loadMissions]);

  const activeMissions = missions.filter(m => m.status === 'active' || m.status === 'paused');
  const awaitingApproval = activeMissions.filter(m => isApprovalGate(m.current_phase));
  const recentCompleted = missions
    .filter(m => m.status === 'completed')
    .slice(0, 3);
  const drafts = missions.filter(m => m.status === 'draft');

  if (loading) {
    return (
      <div className="card-theme p-6">
        <div className="flex items-center gap-3 mb-6">
          <div className="p-2 bg-gradient-to-br from-theme-primary/20 to-theme-accent/20 rounded-xl">
            <Rocket className="h-5 w-5 text-theme-primary" />
          </div>
          <h3 className="text-lg font-semibold text-theme-primary">Missions</h3>
        </div>
        <div className="flex items-center justify-center h-32">
          <Loader2 className="h-5 w-5 animate-spin text-theme-secondary" />
        </div>
      </div>
    );
  }

  return (
    <div className="card-theme overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between p-6 pb-4">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-gradient-to-br from-theme-primary/20 to-theme-accent/20 rounded-xl">
            <Rocket className="h-5 w-5 text-theme-primary" />
          </div>
          <div>
            <h3 className="text-lg font-semibold text-theme-primary">Missions</h3>
            <p className="text-xs text-theme-tertiary">
              {activeMissions.length} active{awaitingApproval.length > 0 && ` \u00B7 ${awaitingApproval.length} awaiting approval`}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => navigate('/app/ai/missions')}
            className="btn-theme btn-theme-sm btn-theme-outline flex items-center gap-1"
          >
            <Plus className="h-3.5 w-3.5" />
            New
          </button>
          <button
            onClick={() => navigate('/app/ai/missions')}
            className="btn-theme btn-theme-sm btn-theme-ghost flex items-center gap-1 text-theme-secondary"
          >
            View all
            <ArrowRight className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>

      {/* Awaiting Approval Banner */}
      {awaitingApproval.length > 0 && (
        <div className="mx-6 mb-4 p-3 bg-theme-warning/10 border border-theme-warning/30 rounded-lg">
          <div className="flex items-center gap-2 text-sm">
            <AlertCircle className="h-4 w-4 text-theme-warning flex-shrink-0" />
            <span className="text-theme-primary font-medium">
              {awaitingApproval.length} mission{awaitingApproval.length > 1 ? 's' : ''} awaiting your approval
            </span>
          </div>
          <div className="mt-2 space-y-1">
            {awaitingApproval.map(m => (
              <button
                key={m.id}
                onClick={() => navigate(`/app/ai/missions/${m.id}`)}
                className="flex items-center justify-between w-full text-left px-2 py-1 rounded hover:bg-theme-warning/10 transition-colors text-sm"
              >
                <span className="text-theme-primary truncate">{m.name}</span>
                <Badge variant="warning" size="sm">{phaseLabel(m.current_phase || '')}</Badge>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Active Missions */}
      {activeMissions.length > 0 ? (
        <div className="px-6 pb-2 space-y-3">
          {activeMissions.slice(0, 5).map(mission => {
            const statusConf = STATUS_CONFIG[mission.status];
            const StatusIcon = statusConf.icon;
            return (
              <div
                key={mission.id}
                onClick={() => navigate(`/app/ai/missions/${mission.id}`)}
                className="group flex items-center gap-3 p-3 rounded-lg border border-theme hover:border-theme-primary/40 hover:bg-theme-surface cursor-pointer transition-all"
              >
                <div className="flex-shrink-0 text-lg" title={mission.mission_type}>
                  {TYPE_EMOJI[mission.mission_type] || '\u{1F680}'}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="text-sm font-medium text-theme-primary truncate">{mission.name}</span>
                    <Badge variant={statusConf.variant} size="sm">
                      <StatusIcon className={`h-3 w-3 mr-1 ${mission.status === 'active' ? 'animate-spin' : ''}`} />
                      {mission.status}
                    </Badge>
                  </div>
                  <div className="flex items-center gap-3">
                    <Progress value={mission.phase_progress} className="h-1 flex-1" />
                    <span className="text-xs text-theme-tertiary flex-shrink-0 w-8 text-right">{mission.phase_progress}%</span>
                  </div>
                  <div className="flex items-center gap-3 mt-1 text-xs text-theme-tertiary">
                    <span>{phaseLabel(mission.current_phase || 'draft')}</span>
                    {mission.repository && (
                      <>
                        <span className="text-theme-border">&middot;</span>
                        <span className="flex items-center gap-1">
                          <GitBranch className="h-3 w-3" />
                          {typeof mission.repository === 'string' ? mission.repository : mission.repository.full_name}
                        </span>
                      </>
                    )}
                  </div>
                </div>
                <ArrowRight className="h-4 w-4 text-theme-muted opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0" />
              </div>
            );
          })}
          {activeMissions.length > 5 && (
            <button
              onClick={() => navigate('/app/ai/missions')}
              className="w-full text-center text-sm text-theme-secondary hover:text-theme-primary py-2"
            >
              +{activeMissions.length - 5} more active missions
            </button>
          )}
        </div>
      ) : (
        <div className="px-6 pb-2">
          <div className="text-center py-6 border border-dashed border-theme rounded-lg">
            <Rocket className="h-8 w-8 mx-auto mb-2 text-theme-muted" />
            <p className="text-sm text-theme-secondary mb-3">No active missions</p>
            <button
              onClick={() => navigate('/app/ai/missions')}
              className="btn-theme btn-theme-sm btn-theme-primary"
            >
              <Plus className="h-3.5 w-3.5 mr-1" />
              Create Mission
            </button>
          </div>
        </div>
      )}

      {/* Drafts */}
      {drafts.length > 0 && (
        <div className="px-6 py-3 border-t border-theme">
          <p className="text-xs font-medium text-theme-tertiary uppercase tracking-wider mb-2">Drafts</p>
          <div className="space-y-1">
            {drafts.slice(0, 3).map(m => (
              <button
                key={m.id}
                onClick={() => navigate(`/app/ai/missions/${m.id}`)}
                className="flex items-center justify-between w-full text-left px-2 py-1.5 rounded hover:bg-theme-surface transition-colors text-sm"
              >
                <span className="text-theme-secondary truncate flex items-center gap-2">
                  <span>{TYPE_EMOJI[m.mission_type]}</span>
                  {m.name}
                </span>
                <span className="text-xs text-theme-tertiary">{timeAgo(m.created_at)}</span>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Recent Completions */}
      {recentCompleted.length > 0 && (
        <div className="px-6 py-3 border-t border-theme">
          <p className="text-xs font-medium text-theme-tertiary uppercase tracking-wider mb-2">Recently Completed</p>
          <div className="space-y-1">
            {recentCompleted.map(m => (
              <button
                key={m.id}
                onClick={() => navigate(`/app/ai/missions/${m.id}`)}
                className="flex items-center justify-between w-full text-left px-2 py-1.5 rounded hover:bg-theme-surface transition-colors text-sm"
              >
                <span className="text-theme-secondary truncate flex items-center gap-2">
                  <CheckCircle className="h-3.5 w-3.5 text-theme-success flex-shrink-0" />
                  {m.name}
                </span>
                <span className="text-xs text-theme-tertiary">{formatDuration(m.duration_ms)}</span>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Footer stats */}
      <div className="px-6 py-3 bg-theme-surface/50 border-t border-theme">
        <div className="flex items-center justify-between text-xs text-theme-tertiary">
          <span>{missions.length} total missions</span>
          <span>
            {missions.filter(m => m.status === 'completed').length} completed
            {missions.filter(m => m.status === 'failed').length > 0 &&
              ` \u00B7 ${missions.filter(m => m.status === 'failed').length} failed`
            }
          </span>
        </div>
      </div>
    </div>
  );
};
