import React from 'react';
import { AlertTriangle } from 'lucide-react';
import type { Mission, MissionStatus } from '../types/mission';
import { phaseLabel, isApprovalGate } from '../types/mission';

const STATUS_STYLES: Record<MissionStatus, { dot: string; pulse?: boolean }> = {
  draft: { dot: 'bg-theme-secondary' },
  active: { dot: 'bg-theme-info', pulse: true },
  paused: { dot: 'bg-theme-warning' },
  completed: { dot: 'bg-theme-success' },
  failed: { dot: 'bg-theme-error' },
  cancelled: { dot: 'bg-theme-tertiary' },
};

const TYPE_ICONS: Record<string, string> = {
  development: '\u{1F6E0}',
  research: '\u{1F52C}',
  operations: '\u2699',
};

function timeAgo(dateStr: string): string {
  const diff = Date.now() - new Date(dateStr).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}

interface MissionListItemProps {
  mission: Mission;
  isSelected: boolean;
  onClick: () => void;
}

export const MissionListItem: React.FC<MissionListItemProps> = ({ mission, isSelected, onClick }) => {
  const statusStyle = STATUS_STYLES[mission.status] || STATUS_STYLES.draft;
  const typeIcon = TYPE_ICONS[mission.mission_type] || '\u{1F4CB}';
  const showProgress = mission.status === 'active' && mission.current_phase;
  const atApprovalGate = isApprovalGate(mission.current_phase, mission.approval_gate_phases);
  const timestamp = mission.started_at || mission.created_at;

  return (
    <button
      onClick={onClick}
      className={`w-full text-left px-3 py-2.5 border-l-2 transition-colors hover:bg-theme-surface-hover ${
        isSelected
          ? 'border-l-theme-accent bg-theme-surface-hover'
          : 'border-l-transparent'
      }`}
    >
      <div className="flex items-center justify-between gap-2 min-w-0">
        <div className="flex items-center gap-2 min-w-0 flex-1">
          {/* Status dot */}
          <span className="relative flex-shrink-0">
            <span className={`block w-2 h-2 rounded-full ${statusStyle.dot}`} />
            {statusStyle.pulse && (
              <span className={`absolute inset-0 w-2 h-2 rounded-full ${statusStyle.dot} animate-ping opacity-40`} />
            )}
          </span>
          {/* Name */}
          <span className="text-sm font-medium text-theme-primary truncate">{mission.name}</span>
        </div>
        <div className="flex items-center gap-1.5 flex-shrink-0">
          {atApprovalGate && (
            <AlertTriangle className="w-3.5 h-3.5 text-theme-warning" />
          )}
          <span className="text-[10px] text-theme-tertiary whitespace-nowrap">{timeAgo(timestamp)}</span>
        </div>
      </div>

      {/* Second row: type + phase + progress */}
      {showProgress && (
        <div className="flex items-center gap-2 mt-1 pl-4">
          <span className="text-[10px] text-theme-secondary whitespace-nowrap">
            {typeIcon} {phaseLabel(mission.current_phase!)}
          </span>
          <div className="flex-1 h-1 bg-theme-surface rounded-full overflow-hidden max-w-[80px]">
            <div
              className="h-full bg-theme-accent rounded-full transition-all"
              style={{ width: `${mission.phase_progress}%` }}
            />
          </div>
          <span className="text-[10px] text-theme-tertiary">{mission.phase_progress}%</span>
        </div>
      )}
    </button>
  );
};
