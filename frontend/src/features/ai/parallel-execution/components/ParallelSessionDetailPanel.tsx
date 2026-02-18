import React from 'react';
import { GitFork, Loader2 } from 'lucide-react';
import { SessionDetailView } from './SessionDetailView';
import type { ParallelSessionDetail } from '../types';

interface ParallelSessionDetailPanelProps {
  session: ParallelSessionDetail | null;
  loading: boolean;
  error: string | null;
  isConnected: boolean;
  onRetryMerge: () => void;
}

export const ParallelSessionDetailPanel: React.FC<ParallelSessionDetailPanelProps> = ({
  session,
  loading,
  error,
  isConnected,
  onRetryMerge,
}) => {
  if (!session && loading) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <Loader2 className="h-6 w-6 text-theme-secondary animate-spin" />
      </div>
    );
  }

  if (error && !session) {
    return (
      <div className="flex-1 flex items-center justify-center px-6">
        <p className="text-sm text-theme-error">{error}</p>
      </div>
    );
  }

  if (!session) {
    return (
      <div className="flex-1 flex flex-col items-center justify-center text-theme-secondary">
        <GitFork className="h-10 w-10 mb-3 text-theme-tertiary" />
        <p className="text-sm">Select a session to view details</p>
      </div>
    );
  }

  return (
    <div className="flex-1 overflow-y-auto p-6">
      <SessionDetailView
        session={session}
        isConnected={isConnected}
        onRetryMerge={onRetryMerge}
      />
    </div>
  );
};
