import React, { useState, useMemo, useCallback } from 'react';
import { Plus, Search, GitFork } from 'lucide-react';
import { ResizableListPanel } from '@/shared/components/layout/ResizableListPanel';
import { ParallelSessionListItem } from './ParallelSessionListItem';
import type { ParallelSession, ParallelSessionStatus } from '../types';

type FilterTab = 'all' | ParallelSessionStatus;

const TABS: { key: FilterTab; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'active', label: 'Active' },
  { key: 'provisioning', label: 'Provisioning' },
  { key: 'merging', label: 'Merging' },
  { key: 'completed', label: 'Completed' },
  { key: 'failed', label: 'Failed' },
];

interface ParallelSessionListPanelProps {
  sessions: ParallelSession[];
  loading: boolean;
  selectedSessionId: string | null;
  onSelectSession: (session: ParallelSession) => void;
  onCreateSession: () => void;
  refreshKey?: number;
}

export const ParallelSessionListPanel: React.FC<ParallelSessionListPanelProps> = ({
  sessions,
  loading,
  selectedSessionId,
  onSelectSession,
  onCreateSession,
}) => {
  const [activeTab, setActiveTab] = useState<FilterTab>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [focusIndex, setFocusIndex] = useState(-1);

  const filteredSessions = useMemo(() => {
    let result = sessions;
    if (activeTab !== 'all') {
      result = result.filter((s) => s.status === activeTab);
    }
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      result = result.filter(
        (s) =>
          s.base_branch.toLowerCase().includes(q) ||
          (s.integration_branch && s.integration_branch.toLowerCase().includes(q))
      );
    }
    return result;
  }, [sessions, activeTab, searchQuery]);

  const stats = useMemo(() => {
    const active = sessions.filter((s) => s.status === 'active' || s.status === 'provisioning' || s.status === 'merging').length;
    const completed = sessions.filter((s) => s.status === 'completed').length;
    const failed = sessions.filter((s) => s.status === 'failed').length;
    return { active, completed, failed };
  }, [sessions]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (filteredSessions.length === 0) return;
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        setFocusIndex((prev) => Math.min(prev + 1, filteredSessions.length - 1));
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        setFocusIndex((prev) => Math.max(prev - 1, 0));
      } else if (e.key === 'Enter' && focusIndex >= 0 && focusIndex < filteredSessions.length) {
        e.preventDefault();
        onSelectSession(filteredSessions[focusIndex]);
      }
    },
    [filteredSessions, focusIndex, onSelectSession]
  );

  const activeSessions = useMemo(
    () => sessions.filter((s) => s.status === 'active' || s.status === 'provisioning'),
    [sessions]
  );

  return (
    <ResizableListPanel
      storageKeyPrefix="parallel-panel"
      title="Sessions"
      onKeyDown={handleKeyDown}
      headerAction={
        <button
          onClick={onCreateSession}
          className="p-1 rounded text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover transition-colors"
          title="New Session"
        >
          <Plus className="h-4 w-4" />
        </button>
      }
      tabPills={
        <div className="flex flex-wrap gap-1 px-3 py-2 border-b border-theme">
          {TABS.map((tab) => (
            <button
              key={tab.key}
              onClick={() => { setActiveTab(tab.key); setFocusIndex(-1); }}
              className={`flex-1 px-2 py-1 text-xs font-medium rounded transition-colors ${
                activeTab === tab.key
                  ? 'bg-theme-interactive-primary/10 text-theme-accent'
                  : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      }
      search={
        <div className="px-3 py-2 border-b border-theme">
          <div className="relative">
            <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-theme-tertiary" />
            <input
              type="text"
              placeholder="Search branches..."
              value={searchQuery}
              onChange={(e) => { setSearchQuery(e.target.value); setFocusIndex(-1); }}
              className="w-full pl-7 pr-2 py-1.5 text-xs bg-theme-bg-secondary rounded border border-theme text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-1 focus:ring-theme-accent"
            />
          </div>
        </div>
      }
      footer={
        <div className="px-3 py-2 border-t border-theme text-[10px] text-theme-tertiary flex items-center gap-3">
          <span>{stats.active} active</span>
          <span>{stats.completed} completed</span>
          <span>{stats.failed} failed</span>
        </div>
      }
      collapsedContent={
        <>
          {activeSessions.map((s) => (
            <span key={s.id} className="relative">
              <span className="block w-2 h-2 rounded-full bg-theme-info" />
              <span className="absolute inset-0 w-2 h-2 rounded-full bg-theme-info animate-ping opacity-40" />
            </span>
          ))}
        </>
      }
    >
      {loading && sessions.length === 0 ? (
        <div className="px-3 py-8 text-center text-sm text-theme-secondary">
          Loading...
        </div>
      ) : filteredSessions.length === 0 ? (
        <div className="px-3 py-8 text-center">
          <GitFork className="h-8 w-8 text-theme-tertiary mx-auto mb-2" />
          <p className="text-sm text-theme-secondary">No sessions</p>
        </div>
      ) : (
        filteredSessions.map((session, idx) => (
          <ParallelSessionListItem
            key={session.id}
            session={session}
            isSelected={session.id === selectedSessionId || idx === focusIndex}
            onClick={() => onSelectSession(session)}
          />
        ))
      )}
    </ResizableListPanel>
  );
};
