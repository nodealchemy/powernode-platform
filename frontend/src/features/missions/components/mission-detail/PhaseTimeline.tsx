import React from 'react';
import { CheckCircle2, Circle, Loader2, AlertCircle } from 'lucide-react';
import type { MissionPhase, MissionStatus, PhaseEntry } from '../../types/mission';
import { phaseLabel } from '../../types/mission';

interface PhaseTimelineProps {
  phases: MissionPhase[];
  currentPhase: MissionPhase | null;
  phaseHistory: PhaseEntry[];
  status: MissionStatus;
  onPhaseClick?: (phase: MissionPhase | null) => void;
  selectedPhase?: MissionPhase | null;
}

function getPhaseState(
  phase: MissionPhase,
  currentPhase: MissionPhase | null,
  phaseHistory: PhaseEntry[],
  status: MissionStatus,
  phaseIndex: number,
  currentIndex: number
): 'completed' | 'active' | 'failed' | 'pending' {
  if (status === 'failed' && phase === currentPhase) return 'failed';
  if (status === 'completed') return 'completed';

  const historyEntry = phaseHistory.find(e => e.phase === phase);
  if (historyEntry?.exited_at) return 'completed';
  if (phase === currentPhase && ['active', 'paused'].includes(status)) return 'active';
  if (phaseIndex < currentIndex) return 'completed';
  return 'pending';
}

export const PhaseTimeline: React.FC<PhaseTimelineProps> = ({
  phases,
  currentPhase,
  phaseHistory,
  status,
  onPhaseClick,
  selectedPhase,
}) => {
  const currentIndex = currentPhase ? phases.indexOf(currentPhase) : -1;

  return (
    <div className="card-theme p-4">
      <div className="flex items-center flex-wrap gap-y-2 gap-x-1">
        {phases.map((phase, i) => {
          const state = getPhaseState(phase, currentPhase, phaseHistory, status, i, currentIndex);

          return (
            <React.Fragment key={phase}>
              {i > 0 && (
                <div
                  className={`h-0.5 flex-shrink-0 w-6 ${
                    state === 'completed' ? 'bg-theme-success' :
                    state === 'active' ? 'bg-theme-accent' :
                    'bg-theme-border'
                  }`}
                />
              )}
              <div
                className={`flex flex-col items-center flex-shrink-0 min-w-[64px] ${onPhaseClick ? 'cursor-pointer' : ''}`}
                onClick={onPhaseClick ? () => onPhaseClick(selectedPhase === phase ? null : phase) : undefined}
                role={onPhaseClick ? 'button' : undefined}
                tabIndex={onPhaseClick ? 0 : undefined}
                onKeyDown={onPhaseClick ? (e) => { if (e.key === 'Enter' || e.key === ' ') onPhaseClick(selectedPhase === phase ? null : phase); } : undefined}
              >
                <div className={`mb-1 ${selectedPhase === phase ? 'ring-2 ring-theme-accent ring-offset-1 ring-offset-theme-bg-surface rounded-full' : ''}`}>
                  {state === 'completed' && (
                    <CheckCircle2 className="w-5 h-5 text-theme-success" />
                  )}
                  {state === 'active' && (
                    <Loader2 className="w-5 h-5 text-theme-accent animate-spin" />
                  )}
                  {state === 'failed' && (
                    <AlertCircle className="w-5 h-5 text-theme-error" />
                  )}
                  {state === 'pending' && (
                    <Circle className="w-5 h-5 text-theme-tertiary" />
                  )}
                </div>
                <span
                  className={`text-[10px] text-center leading-tight ${
                    state === 'active' ? 'text-theme-accent font-medium' :
                    state === 'completed' ? 'text-theme-success' :
                    state === 'failed' ? 'text-theme-error' :
                    'text-theme-tertiary'
                  }`}
                >
                  {phaseLabel(phase)}
                </span>
              </div>
            </React.Fragment>
          );
        })}
      </div>
    </div>
  );
};
