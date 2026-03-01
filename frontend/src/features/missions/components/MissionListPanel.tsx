import React, { useState, useCallback, useRef, useEffect, useMemo } from 'react';
import { Plus, PanelLeftClose, PanelLeft, Rocket, Search } from 'lucide-react';
import type { Mission, MissionStatus } from '../types/mission';
import { MissionListItem } from './MissionListItem';

const STORAGE_KEY = 'missions-panel-width';
const COLLAPSED_KEY = 'missions-panel-collapsed';
const MIN_WIDTH = 240;
const MAX_WIDTH = 400;
const DEFAULT_WIDTH = 300;
const COLLAPSED_WIDTH = 48;

const STATUS_DOT: Record<MissionStatus, string> = {
  draft: 'bg-theme-secondary',
  active: 'bg-theme-info',
  paused: 'bg-theme-warning',
  completed: 'bg-theme-success',
  failed: 'bg-theme-error',
  cancelled: 'bg-theme-tertiary',
};

const TABS = [
  { id: 'active' as const, label: 'Active' },
  { id: 'completed' as const, label: 'Completed' },
  { id: 'all' as const, label: 'All' },
];

export type MissionTabId = 'active' | 'completed' | 'all';

interface MissionListPanelProps {
  missions: Mission[];
  loading: boolean;
  selectedMissionId: string | null;
  activeTab: MissionTabId;
  onTabChange: (tab: MissionTabId) => void;
  onSelectMission: (id: string) => void;
  onNewMission: () => void;
  hasManagePermission: boolean;
}

export const MissionListPanel: React.FC<MissionListPanelProps> = ({
  missions,
  loading,
  selectedMissionId,
  activeTab,
  onTabChange,
  onSelectMission,
  onNewMission,
  hasManagePermission,
}) => {
  const [width, setWidth] = useState(() => {
    const saved = localStorage.getItem(STORAGE_KEY);
    return saved ? Math.max(MIN_WIDTH, Math.min(MAX_WIDTH, parseInt(saved, 10))) : DEFAULT_WIDTH;
  });

  const [collapsed, setCollapsed] = useState(() => {
    return localStorage.getItem(COLLAPSED_KEY) === 'true';
  });

  const [search, setSearch] = useState('');
  const [focusIndex, setFocusIndex] = useState(-1);
  const listRef = useRef<HTMLDivElement>(null);
  const isDragging = useRef(false);
  const startX = useRef(0);
  const startWidth = useRef(0);

  // Resize handlers
  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    isDragging.current = true;
    startX.current = e.clientX;
    startWidth.current = width;
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  }, [width]);

  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      if (!isDragging.current) return;
      const delta = e.clientX - startX.current;
      const newWidth = Math.max(MIN_WIDTH, Math.min(MAX_WIDTH, startWidth.current + delta));
      setWidth(newWidth);
      localStorage.setItem(STORAGE_KEY, String(newWidth));
    };

    const handleMouseUp = () => {
      isDragging.current = false;
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, []);

  const toggleCollapsed = useCallback(() => {
    setCollapsed((prev) => {
      const next = !prev;
      localStorage.setItem(COLLAPSED_KEY, String(next));
      return next;
    });
  }, []);

  // Filter missions by tab + search
  const filteredMissions = useMemo(() => {
    let filtered = missions;
    switch (activeTab) {
      case 'active':
        filtered = missions.filter(m => ['draft', 'active', 'paused'].includes(m.status));
        break;
      case 'completed':
        filtered = missions.filter(m => ['completed', 'failed', 'cancelled'].includes(m.status));
        break;
    }
    if (search.trim()) {
      const q = search.toLowerCase();
      filtered = filtered.filter(m =>
        m.name.toLowerCase().includes(q) ||
        m.description?.toLowerCase().includes(q) ||
        m.repository?.full_name?.toLowerCase().includes(q) ||
        m.repository?.name?.toLowerCase().includes(q)
      );
    }
    return filtered;
  }, [missions, activeTab, search]);

  // Keyboard navigation
  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setFocusIndex(prev => Math.min(prev + 1, filteredMissions.length - 1));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setFocusIndex(prev => Math.max(prev - 1, 0));
    } else if (e.key === 'Enter' && focusIndex >= 0 && focusIndex < filteredMissions.length) {
      e.preventDefault();
      onSelectMission(filteredMissions[focusIndex].id);
    } else if (e.key === 'Escape') {
      e.preventDefault();
      setFocusIndex(-1);
    }
  }, [filteredMissions, focusIndex, onSelectMission]);

  // Scroll focused item into view
  useEffect(() => {
    if (focusIndex >= 0 && listRef.current) {
      const items = listRef.current.querySelectorAll('[data-mission-item]');
      items[focusIndex]?.scrollIntoView({ block: 'nearest' });
    }
  }, [focusIndex]);

  // Stats
  const activeMissionCount = missions.filter(m => ['draft', 'active', 'paused'].includes(m.status)).length;
  const completedMissionCount = missions.filter(m => m.status === 'completed').length;
  const failedMissionCount = missions.filter(m => m.status === 'failed').length;

  const sidebarWidth = collapsed ? COLLAPSED_WIDTH : width;

  return (
    <div
      className="relative flex flex-col h-full bg-theme-surface border-r border-theme flex-shrink-0"
      style={{ width: sidebarWidth, minWidth: sidebarWidth }}
      onKeyDown={!collapsed ? handleKeyDown : undefined}
      tabIndex={collapsed ? undefined : 0}
    >
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-3 border-b border-theme">
        {!collapsed && (
          <h3 className="text-sm font-semibold text-theme-primary truncate">Missions</h3>
        )}
        <div className="flex items-center gap-1">
          {!collapsed && hasManagePermission && (
            <button
              onClick={onNewMission}
              className="btn-theme btn-theme-primary text-xs px-2 py-1 flex items-center gap-1"
              title="New Mission"
            >
              <Plus className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">New</span>
            </button>
          )}
          <button
            onClick={toggleCollapsed}
            className="p-1 rounded text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover transition-colors"
            title={collapsed ? 'Expand panel' : 'Collapse panel'}
          >
            {collapsed ? <PanelLeft className="h-4 w-4" /> : <PanelLeftClose className="h-4 w-4" />}
          </button>
        </div>
      </div>

      {/* Collapsed mode: status dots only */}
      {collapsed ? (
        <div className="flex flex-col items-center gap-1.5 py-3">
          {hasManagePermission && (
            <button
              onClick={onNewMission}
              className="w-8 h-8 rounded-md flex items-center justify-center text-theme-accent hover:bg-theme-surface-hover transition-colors"
              title="New Mission"
            >
              <Plus className="h-4 w-4" />
            </button>
          )}
          {missions.filter(m => ['draft', 'active', 'paused'].includes(m.status)).slice(0, 10).map((m) => (
            <button
              key={m.id}
              onClick={() => onSelectMission(m.id)}
              title={m.name}
              className={`w-8 h-8 rounded-md flex items-center justify-center transition-colors ${
                selectedMissionId === m.id
                  ? 'bg-theme-interactive-primary/10'
                  : 'hover:bg-theme-surface-hover'
              }`}
            >
              <span className={`w-2.5 h-2.5 rounded-full ${STATUS_DOT[m.status] || 'bg-theme-secondary'}`} />
            </button>
          ))}
        </div>
      ) : (
        <>
          {/* Tab pills */}
          <div className="flex px-3 pt-2 pb-1 gap-1">
            {TABS.map((tab) => (
              <button
                key={tab.id}
                onClick={() => onTabChange(tab.id)}
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

          {/* Search */}
          <div className="px-3 py-2">
            <div className="relative">
              <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-theme-tertiary" />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search missions..."
                className="w-full pl-7 pr-2 py-1.5 text-xs bg-theme-background border border-theme rounded text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-1 focus:ring-theme-accent"
              />
            </div>
          </div>

          {/* List */}
          <div ref={listRef} className="flex-1 overflow-y-auto">
            {loading && missions.length === 0 ? (
              <div className="text-center py-8 text-theme-secondary text-xs">Loading...</div>
            ) : filteredMissions.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-8 px-4">
                <Rocket className="w-8 h-8 text-theme-tertiary mb-2" />
                <span className="text-xs text-theme-tertiary text-center">
                  {search ? 'No matching missions' : 'No missions'}
                </span>
              </div>
            ) : (
              filteredMissions.map((mission, idx) => (
                <div
                  key={mission.id}
                  data-mission-item
                  className={focusIndex === idx ? 'ring-1 ring-inset ring-theme-accent/50' : ''}
                >
                  <MissionListItem
                    mission={mission}
                    isSelected={selectedMissionId === mission.id}
                    onClick={() => onSelectMission(mission.id)}
                  />
                </div>
              ))
            )}
          </div>

          {/* Footer stats */}
          {missions.length > 0 && (
            <div className="px-3 py-2 border-t border-theme text-[10px] text-theme-tertiary flex gap-3">
              <span>{activeMissionCount} active</span>
              <span>{completedMissionCount} completed</span>
              {failedMissionCount > 0 && <span className="text-theme-error">{failedMissionCount} failed</span>}
            </div>
          )}
        </>
      )}

      {/* Drag handle */}
      {!collapsed && (
        <div
          onMouseDown={handleMouseDown}
          onDoubleClick={toggleCollapsed}
          className="absolute top-0 right-0 w-1 h-full cursor-col-resize hover:bg-theme-interactive-primary/30 transition-colors"
        />
      )}
    </div>
  );
};
