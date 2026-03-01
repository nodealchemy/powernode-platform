import React from 'react';
import type { ContainerState } from '../types';

interface ContainerStateActionsProps {
  state: ContainerState;
  onStart?: () => void;
  onStop?: () => void;
  onRestart?: () => void;
  isLoading?: boolean;
}

export const ContainerStateActions: React.FC<ContainerStateActionsProps> = ({
  state,
  onStart,
  onStop,
  onRestart,
  isLoading = false,
}) => {
  const canStart = state === 'exited' || state === 'created' || state === 'dead';
  const canStop = state === 'running' || state === 'paused' || state === 'restarting';
  const canRestart = state === 'running';

  return (
    <div className="flex items-center gap-2">
      {canStart && (
        <button
          onClick={onStart}
          disabled={isLoading}
          className="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-medium rounded-md bg-theme-success bg-opacity-10 text-theme-success hover:bg-opacity-20 transition-colors disabled:opacity-50"
        >
          <svg className="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 20 20">
            <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z" clipRule="evenodd" />
          </svg>
          Start
        </button>
      )}
      {canStop && (
        <button
          onClick={onStop}
          disabled={isLoading}
          className="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-medium rounded-md bg-theme-error bg-opacity-10 text-theme-error hover:bg-opacity-20 transition-colors disabled:opacity-50"
        >
          <svg className="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 20 20">
            <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8 7a1 1 0 00-1 1v4a1 1 0 001 1h4a1 1 0 001-1V8a1 1 0 00-1-1H8z" clipRule="evenodd" />
          </svg>
          Stop
        </button>
      )}
      {canRestart && (
        <button
          onClick={onRestart}
          disabled={isLoading}
          className="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-medium rounded-md bg-theme-warning bg-opacity-10 text-theme-warning hover:bg-opacity-20 transition-colors disabled:opacity-50"
        >
          <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
          </svg>
          Restart
        </button>
      )}
      {isLoading && (
        <span className="text-xs text-theme-tertiary animate-pulse">Processing...</span>
      )}
    </div>
  );
};
