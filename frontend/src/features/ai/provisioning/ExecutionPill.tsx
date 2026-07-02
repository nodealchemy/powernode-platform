import React from 'react';
import { Loader2, X } from 'lucide-react';

export interface ExecutionPillProps {
  missionId: string;
  totalSteps: number;
  completedSteps: number;
  onClick: () => void;
  onClose?: () => void;
}

/**
 * Floating bottom-right pill shown while the Plan Review modal is backgrounded.
 *
 * Click → re-opens the Plan Review modal in execution view.
 * Z-index sits above page content (`z-40`) but below the modal layer (`z-50`).
 */
export const ExecutionPill: React.FC<ExecutionPillProps> = ({
  missionId,
  totalSteps,
  completedSteps,
  onClick,
  onClose,
}) => {
  const safeTotal = Math.max(0, totalSteps);
  const safeCompleted = Math.max(0, Math.min(completedSteps, safeTotal));

  return (
    <div
      className="fixed bottom-4 right-4 z-40"
      data-testid="execution-pill"
      data-mission-id={missionId}
    >
      <div className="flex items-center gap-2 rounded-full bg-theme-interactive-primary text-white shadow-lg pl-3 pr-1 py-1">
        <button
          type="button"
          onClick={onClick}
          aria-label="Open provisioning plan"
          className="flex items-center gap-2 pr-2 hover:opacity-90 transition-opacity"
        >
          <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
          <span className="text-xs font-medium tabular-nums">
            Provisioning… {safeCompleted} of {safeTotal} steps
          </span>
        </button>
        {onClose && (
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              onClose();
            }}
            aria-label="Dismiss"
            className="flex items-center justify-center h-6 w-6 rounded-full hover:bg-theme-on-primary/20 transition-colors"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        )}
      </div>
    </div>
  );
};

export default ExecutionPill;
