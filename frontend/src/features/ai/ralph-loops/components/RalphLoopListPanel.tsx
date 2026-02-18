import React, { useState, useCallback, useEffect, useMemo, useRef } from 'react';
import { Plus, RotateCcw, Search } from 'lucide-react';
import { ResizableListPanel } from '@/shared/components/layout/ResizableListPanel';
import { RalphLoopListItem } from './RalphLoopListItem';
import { ralphLoopsApi } from '@/shared/services/ai/RalphLoopsApiService';
import type { RalphLoopSummary, RalphLoopStatus } from '@/shared/services/ai/types/ralph-types';

type TabId = 'all' | 'running' | 'pending' | 'completed' | 'failed';

const TABS: { id: TabId; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'running', label: 'Running' },
  { id: 'pending', label: 'Pending' },
  { id: 'completed', label: 'Completed' },
  { id: 'failed', label: 'Failed' },
];

const TAB_STATUS_MAP: Record<TabId, RalphLoopStatus[] | null> = {
  all: null,
  running: ['running'],
  pending: ['pending', 'paused'],
  completed: ['completed'],
  failed: ['failed', 'cancelled'],
};

const STATUS_DOT: Record<RalphLoopStatus, string> = {
  pending: 'bg-theme-secondary',
  running: 'bg-theme-info',
  paused: 'bg-theme-warning',
  completed: 'bg-theme-success',
  failed: 'bg-theme-error',
  cancelled: 'bg-theme-tertiary',
};

interface RalphLoopListPanelProps {
  selectedLoopId: string | null;
  onSelectLoop: (loop: RalphLoopSummary) => void;
  onCreateLoop: () => void;
  refreshKey?: number;
}

export const RalphLoopListPanel: React.FC<RalphLoopListPanelProps> = ({
  selectedLoopId,
  onSelectLoop,
  onCreateLoop,
  refreshKey,
}) => {
  const [loops, setLoops] = useState<RalphLoopSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<TabId>('all');
  const [search, setSearch] = useState('');
  const [focusIndex, setFocusIndex] = useState(-1);
  const listRef = useRef<HTMLDivElement>(null);

  const loadLoops = useCallback(async () => {
    try {
      setLoading(true);
      const response = await ralphLoopsApi.getLoops({ per_page: 100 });
      setLoops(response.items || []);
    } catch {
      // Silently fail — list will show empty state
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadLoops();
  }, [loadLoops]);

  // Reload when refreshKey changes
  useEffect(() => {
    if (refreshKey && refreshKey > 0) {
      loadLoops();
    }
  }, [refreshKey, loadLoops]);

  // Auto-refresh every 5s when running loops exist
  useEffect(() => {
    const hasRunning = loops.some(l => l.status === 'running');
    if (hasRunning) {
      const interval = setInterval(loadLoops, 5000);
      return () => clearInterval(interval);
    }
  }, [loops, loadLoops]);

  // Filter by tab + search
  const filteredLoops = useMemo(() => {
    let filtered = loops;
    const statuses = TAB_STATUS_MAP[activeTab];
    if (statuses) {
      filtered = filtered.filter(l => statuses.includes(l.status));
    }
    if (search.trim()) {
      const q = search.toLowerCase();
      filtered = filtered.filter(l => l.name.toLowerCase().includes(q));
    }
    return filtered;
  }, [loops, activeTab, search]);

  // Stats
  const runningCount = loops.filter(l => l.status === 'running').length;
  const completedCount = loops.filter(l => l.status === 'completed').length;
  const failedCount = loops.filter(l => l.status === 'failed').length;

  // Keyboard navigation
  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setFocusIndex(prev => Math.min(prev + 1, filteredLoops.length - 1));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setFocusIndex(prev => Math.max(prev - 1, 0));
    } else if (e.key === 'Enter' && focusIndex >= 0 && focusIndex < filteredLoops.length) {
      e.preventDefault();
      onSelectLoop(filteredLoops[focusIndex]);
    } else if (e.key === 'Escape') {
      e.preventDefault();
      setFocusIndex(-1);
    }
  }, [filteredLoops, focusIndex, onSelectLoop]);

  // Scroll focused item into view
  useEffect(() => {
    if (focusIndex >= 0 && listRef.current) {
      const items = listRef.current.querySelectorAll('[data-list-item]');
      items[focusIndex]?.scrollIntoView({ block: 'nearest' });
    }
  }, [focusIndex]);

  return (
    <ResizableListPanel
      storageKeyPrefix="ralph-loops-panel"
      title="Ralph Loops"
      onKeyDown={handleKeyDown}
      headerAction={
        <button
          onClick={onCreateLoop}
          className="btn-theme btn-theme-primary text-xs px-2 py-1 flex items-center gap-1"
          title="New Loop"
        >
          <Plus className="h-3.5 w-3.5" />
          <span className="hidden sm:inline">New</span>
        </button>
      }
      tabPills={
        <div className="flex px-3 pt-2 pb-1 gap-1">
          {TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex-1 px-2 py-1 text-xs font-medium rounded transition-colors ${
                activeTab === tab.id
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
        <div className="px-3 py-2">
          <div className="relative">
            <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-theme-tertiary" />
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search loops..."
              className="w-full pl-7 pr-2 py-1.5 text-xs bg-theme-background border border-theme rounded text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-1 focus:ring-theme-accent"
            />
          </div>
        </div>
      }
      footer={
        loops.length > 0 ? (
          <div className="px-3 py-2 border-t border-theme text-[10px] text-theme-tertiary flex gap-3">
            <span>{runningCount} running</span>
            <span>{completedCount} completed</span>
            {failedCount > 0 && <span className="text-theme-error">{failedCount} failed</span>}
          </div>
        ) : undefined
      }
      collapsedContent={
        <>
          <button
            onClick={onCreateLoop}
            className="w-8 h-8 rounded-md flex items-center justify-center text-theme-accent hover:bg-theme-surface-hover transition-colors"
            title="New Loop"
          >
            <Plus className="h-4 w-4" />
          </button>
          {loops.filter(l => ['running', 'pending', 'paused'].includes(l.status)).slice(0, 10).map((l) => (
            <button
              key={l.id}
              onClick={() => onSelectLoop(l)}
              title={l.name}
              className={`w-8 h-8 rounded-md flex items-center justify-center transition-colors ${
                selectedLoopId === l.id
                  ? 'bg-theme-interactive-primary/10'
                  : 'hover:bg-theme-surface-hover'
              }`}
            >
              <span className={`w-2.5 h-2.5 rounded-full ${STATUS_DOT[l.status] || 'bg-theme-secondary'}`} />
            </button>
          ))}
        </>
      }
    >
      <div ref={listRef}>
        {loading && loops.length === 0 ? (
          <div className="text-center py-8 text-theme-secondary text-xs">Loading...</div>
        ) : filteredLoops.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-8 px-4">
            <RotateCcw className="w-8 h-8 text-theme-tertiary mb-2" />
            <span className="text-xs text-theme-tertiary text-center">
              {search ? 'No matching loops' : 'No loops'}
            </span>
          </div>
        ) : (
          filteredLoops.map((loop, idx) => (
            <div
              key={loop.id}
              className={focusIndex === idx ? 'ring-1 ring-inset ring-theme-accent/50' : ''}
            >
              <RalphLoopListItem
                loop={loop}
                isSelected={selectedLoopId === loop.id}
                onClick={() => onSelectLoop(loop)}
              />
            </div>
          ))
        )}
      </div>
    </ResizableListPanel>
  );
};
