import React from 'react';
import { Link } from 'react-router-dom';
import {
  GitBranch, Users, Clock, MessageSquare,
  ExternalLink, Calendar, Timer,
} from 'lucide-react';
import type { Mission } from '../../types/mission';
import { phaseLabel } from '../../types/mission';

interface MissionSidebarProps {
  mission: Mission;
}

function formatDate(dateStr: string | null): string {
  if (!dateStr) return '-';
  return new Date(dateStr).toLocaleString();
}

function formatDuration(ms: number | null): string {
  if (!ms) return '-';
  const seconds = Math.floor(ms / 1000);
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ${seconds % 60}s`;
  const hours = Math.floor(minutes / 60);
  return `${hours}h ${minutes % 60}m`;
}

export const MissionSidebar: React.FC<MissionSidebarProps> = ({ mission }) => {
  return (
    <div className="space-y-4">
      {/* Status & Type */}
      <div className="card-theme p-4 space-y-3">
        <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide">Details</h4>

        <div className="flex justify-between text-sm">
          <span className="text-theme-tertiary">Status</span>
          <span className="text-theme-primary font-medium capitalize">{mission.status}</span>
        </div>

        <div className="flex justify-between text-sm">
          <span className="text-theme-tertiary">Type</span>
          <span className="text-theme-primary capitalize">{mission.mission_type}</span>
        </div>

        {mission.current_phase && (
          <div className="flex justify-between text-sm">
            <span className="text-theme-tertiary">Phase</span>
            <span className="text-theme-primary">{phaseLabel(mission.current_phase)}</span>
          </div>
        )}
      </div>

      {/* Repository */}
      {mission.repository && (
        <div className="card-theme p-4 space-y-2">
          <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide flex items-center gap-1">
            <GitBranch className="w-3 h-3" /> Repository
          </h4>
          <p className="text-sm text-theme-primary">{mission.repository.full_name || mission.repository.name}</p>
          {mission.branch_name && (
            <div className="flex items-center gap-1 text-xs text-theme-tertiary">
              <GitBranch className="w-3 h-3" />
              <code>{mission.branch_name}</code>
              <span className="mx-1">from</span>
              <code>{mission.base_branch}</code>
            </div>
          )}
          {mission.pr_url && (
            <a
              href={mission.pr_url}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1 text-xs text-theme-accent hover:underline"
            >
              PR #{mission.pr_number} <ExternalLink className="w-3 h-3" />
            </a>
          )}
        </div>
      )}

      {/* Team */}
      {mission.team && (
        <div className="card-theme p-4 space-y-2">
          <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide flex items-center gap-1">
            <Users className="w-3 h-3" /> Team
          </h4>
          <p className="text-sm text-theme-primary">{mission.team.name}</p>
        </div>
      )}

      {/* Timing */}
      <div className="card-theme p-4 space-y-2">
        <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide flex items-center gap-1">
          <Clock className="w-3 h-3" /> Timing
        </h4>
        <div className="space-y-1.5 text-xs">
          <div className="flex justify-between">
            <span className="text-theme-tertiary flex items-center gap-1"><Calendar className="w-3 h-3" /> Created</span>
            <span className="text-theme-primary">{formatDate(mission.created_at)}</span>
          </div>
          {mission.started_at && (
            <div className="flex justify-between">
              <span className="text-theme-tertiary">Started</span>
              <span className="text-theme-primary">{formatDate(mission.started_at)}</span>
            </div>
          )}
          {mission.completed_at && (
            <div className="flex justify-between">
              <span className="text-theme-tertiary">Completed</span>
              <span className="text-theme-primary">{formatDate(mission.completed_at)}</span>
            </div>
          )}
          {mission.duration_ms && (
            <div className="flex justify-between">
              <span className="text-theme-tertiary flex items-center gap-1"><Timer className="w-3 h-3" /> Duration</span>
              <span className="text-theme-primary font-medium">{formatDuration(mission.duration_ms)}</span>
            </div>
          )}
        </div>
      </div>

      {/* Mission Chat */}
      {mission.conversation_id && (
        <div className="card-theme p-4 space-y-2">
          <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide flex items-center gap-1">
            <MessageSquare className="w-3 h-3" /> Mission Chat
          </h4>
          <Link
            to={`/app/ai/communication/conversations?id=${mission.conversation_id}`}
            className="inline-flex items-center gap-1 text-xs text-theme-accent hover:underline"
          >
            Open Conversation <ExternalLink className="w-3 h-3" />
          </Link>
        </div>
      )}

      {/* Approvals */}
      {mission.approvals && mission.approvals.length > 0 && (
        <div className="card-theme p-4 space-y-2">
          <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide">Approvals</h4>
          <div className="space-y-2">
            {mission.approvals.map((a) => (
              <div key={a.id} className="text-xs">
                <div className="flex items-center justify-between">
                  <span className="text-theme-primary capitalize">{a.gate.replace(/_/g, ' ')}</span>
                  <span className={`px-1.5 py-0.5 rounded text-[10px] font-medium ${
                    a.decision === 'approved'
                      ? 'bg-theme-success/10 text-theme-success'
                      : 'bg-theme-error/10 text-theme-error'
                  }`}>
                    {a.decision}
                  </span>
                </div>
                {a.comment && (
                  <p className="text-theme-tertiary mt-0.5">{a.comment}</p>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Created By */}
      {mission.created_by && (
        <div className="card-theme p-4">
          <div className="flex items-center justify-between text-xs">
            <span className="text-theme-tertiary">Created by</span>
            <span className="text-theme-primary">{mission.created_by.name}</span>
          </div>
        </div>
      )}
    </div>
  );
};
