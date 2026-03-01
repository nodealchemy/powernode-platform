import React from 'react';
import { HostSelector } from './HostSelector';
import { useHostContext } from '../hooks/useHostContext';

interface DockerLayoutProps {
  children: React.ReactNode;
}

export const DockerLayout: React.FC<DockerLayoutProps> = ({ children }) => {
  const { selectedHostId, isLoading } = useHostContext();

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between border-b border-theme pb-4">
        <HostSelector />
      </div>

      {isLoading ? (
        <div className="flex items-center justify-center py-16">
          <div className="text-sm text-theme-tertiary">Loading hosts...</div>
        </div>
      ) : !selectedHostId ? (
        <div className="flex flex-col items-center justify-center py-16 space-y-3">
          <div className="w-16 h-16 rounded-full bg-theme-surface flex items-center justify-center">
            <svg className="w-8 h-8 text-theme-tertiary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2" />
            </svg>
          </div>
          <p className="text-sm font-medium text-theme-secondary">No host selected</p>
          <p className="text-xs text-theme-tertiary">Select a Docker host from the dropdown above to get started.</p>
        </div>
      ) : (
        children
      )}
    </div>
  );
};
