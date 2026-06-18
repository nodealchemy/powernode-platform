import React, { useState, useMemo, useCallback } from 'react';
import {
  Search, ChevronRight, ArrowDown, ArrowUp,
  Rocket, Eye, Play, Pause, CheckCircle, XCircle, MoreHorizontal, Loader2,
} from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { DropdownMenu } from '@/shared/components/ui/DropdownMenu';
import { EntityLink } from '@/shared/components/entity';
import { useMissionModal } from '@/shared/hooks/useMissionModal';
import { useMissions } from '../hooks/useMissions';
import { MissionExpandedRow } from './MissionExpandedRow';
import {
  STATUS_CONFIG, STATUS_TABS, TAB_STATUS_MAP,
  MISSION_TYPE_LABELS, SORT_OPTIONS, timeAgo,
} from '../constants/missionConstants';
import type { StatusTabId } from '../constants/missionConstants';
import { isApprovalGate } from '../types/mission';
import type { Mission } from '../types/mission';
import { cn } from '@/shared/utils/cn';

interface MissionsIndexTableProps {
  onNewMission: () => void;
  onStartMission: (missionId: string) => void;
  onPauseMission: (missionId: string) => void;
  onCancelMission: (missionId: string) => void;
  onApproveMission: (missionId: string) => void;
}

export const MissionsIndexTable: React.FC<MissionsIndexTableProps> = ({
  onStartMission,
  onPauseMission,
  onCancelMission,
  onApproveMission,
}) => {
  const [expandedRows, setExpandedRows] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<StatusTabId>('all');
  const [sortBy, setSortBy] = useState('updated_at');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('desc');
  const [typeFilter, setTypeFilter] = useState('');

  const { missions, loading, hasManagePermission } = useMissions();
  const { openMission } = useMissionModal();

  // --- Filtering ---

  const filteredMissions = useMemo(() => {
    let filtered = missions;
    const statuses = TAB_STATUS_MAP[statusFilter];
    if (statuses) {
      filtered = filtered.filter(m => statuses.includes(m.status));
    }
    if (typeFilter) {
      filtered = filtered.filter(m => m.mission_type === typeFilter);
    }
    if (search.trim()) {
      const q = search.toLowerCase();
      filtered = filtered.filter(m =>
        m.name.toLowerCase().includes(q) ||
        (m.description && m.description.toLowerCase().includes(q)) ||
        (m.objective && m.objective.toLowerCase().includes(q)) ||
        (m.repository?.name && m.repository.name.toLowerCase().includes(q))
      );
    }
    return filtered;
  }, [missions, statusFilter, search, typeFilter]);

  // --- Handlers ---

  const toggleExpand = useCallback((id: string) => {
    setExpandedRows(prev => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }, []);

  const handleSortClick = useCallback((key: string) => {
    if (sortBy === key) {
      setSortOrder(prev => (prev === 'desc' ? 'asc' : 'desc'));
    } else {
      setSortBy(key);
      setSortOrder('desc');
    }
  }, [sortBy]);

  // --- Render ---

  return (
    <div>
      {/* Filter toolbar */}
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        {/* Search input */}
        <div className="relative flex-1 min-w-[200px] max-w-sm">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-theme-tertiary" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search missions..."
            className="w-full pl-9 pr-3 py-2 text-sm bg-theme-background border border-theme rounded-lg text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-1 focus:ring-theme-accent"
          />
        </div>

        {/* Status filter pills */}
        <div className="flex gap-1">
          {STATUS_TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setStatusFilter(tab.id)}
              className={cn(
                'px-3 py-1.5 text-xs font-medium rounded-md transition-colors',
                statusFilter === tab.id
                  ? 'bg-theme-interactive-primary/10 text-theme-info-fg border border-theme-info-border/30'
                  : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover border border-transparent'
              )}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Type filter select */}
        <select
          value={typeFilter}
          onChange={(e) => setTypeFilter(e.target.value)}
          className="px-3 py-1.5 text-xs bg-theme-background border border-theme rounded-md text-theme-primary focus:outline-none focus:ring-1 focus:ring-theme-accent"
        >
          <option value="">All types</option>
          {Object.entries(MISSION_TYPE_LABELS).map(([value, label]) => (
            <option key={value} value={value}>{label}</option>
          ))}
        </select>

        {/* Sort pills */}
        <div className="flex gap-1">
          {SORT_OPTIONS.map((opt) => (
            <button
              key={opt.key}
              onClick={() => handleSortClick(opt.key)}
              className={cn(
                'inline-flex items-center gap-0.5 px-2 py-1.5 text-xs font-medium rounded-md transition-colors',
                sortBy === opt.key
                  ? 'bg-theme-interactive-primary/10 text-theme-info-fg border border-theme-info-border/30'
                  : 'text-theme-tertiary hover:text-theme-secondary hover:bg-theme-surface-hover border border-transparent'
              )}
            >
              {opt.label}
              {sortBy === opt.key && (
                sortOrder === 'desc'
                  ? <ArrowDown className="h-3 w-3" />
                  : <ArrowUp className="h-3 w-3" />
              )}
            </button>
          ))}
        </div>
      </div>

      {/* Table */}
      <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
        <table className="min-w-full divide-y divide-theme">
          <thead className="bg-theme-background">
            <tr>
              <th className="w-10 px-3 py-3" />
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">Name</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">Status</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">Type</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">Phase</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">Repository</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">Updated</th>
              <th className="w-36 px-3 py-3" />
            </tr>
          </thead>
          <tbody className="divide-y divide-theme">
            {filteredMissions.map((mission) => (
              <React.Fragment key={mission.id}>
                {/* Main row */}
                <tr
                  className={cn(
                    'hover:bg-theme-surface-hover transition-colors cursor-pointer',
                    expandedRows.has(mission.id) && 'bg-theme-surface-hover'
                  )}
                  onClick={() => toggleExpand(mission.id)}
                >
                  {/* Expand chevron */}
                  <td className="px-3 py-3">
                    <div className={cn(
                      'transition-transform duration-200',
                      expandedRows.has(mission.id) && 'rotate-90'
                    )}>
                      <ChevronRight className={cn(
                        'h-4 w-4',
                        expandedRows.has(mission.id) ? 'text-theme-info-fg' : 'text-theme-tertiary'
                      )} />
                    </div>
                  </td>

                  {/* Name + objective snippet */}
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <span className={cn('w-2 h-2 rounded-full flex-shrink-0', STATUS_CONFIG[mission.status]?.dot || 'bg-theme-surface')} />
                      <div className="min-w-0">
                        <div className="text-sm font-medium text-theme-primary truncate">{mission.name}</div>
                        {mission.objective && (
                          <div className="text-xs text-theme-tertiary truncate max-w-xs">{mission.objective}</div>
                        )}
                      </div>
                    </div>
                  </td>

                  {/* Status badge */}
                  <td className="px-4 py-3">
                    <Badge variant={STATUS_CONFIG[mission.status]?.variant || 'outline'} size="sm">
                      {STATUS_CONFIG[mission.status]?.label || mission.status}
                    </Badge>
                  </td>

                  {/* Type */}
                  <td className="px-4 py-3">
                    <span className="text-sm text-theme-secondary">
                      {MISSION_TYPE_LABELS[mission.mission_type] || mission.mission_type}
                    </span>
                  </td>

                  {/* Phase progress bar */}
                  <td className="px-4 py-3">
                    {mission.current_phase ? (
                      <div className="flex items-center gap-2">
                        <div className="flex-1 h-1.5 bg-theme-background-secondary rounded-full overflow-hidden max-w-[100px]">
                          <div
                            className="h-full rounded-full bg-theme-interactive-primary transition-all"
                            style={{ width: `${mission.phase_progress || 0}%` }}
                          />
                        </div>
                        <span className="text-xs text-theme-tertiary whitespace-nowrap">
                          {mission.current_phase.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase())}
                        </span>
                      </div>
                    ) : (
                      <span className="text-xs text-theme-tertiary">{'\u2014'}</span>
                    )}
                  </td>

                  {/* Repository */}
                  <td className="px-4 py-3">
                    {mission.repository?.id ? (
                      <EntityLink
                        type="repository"
                        id={mission.repository.id}
                        label={mission.repository.name}
                        className="text-sm"
                      />
                    ) : (
                      <span className="text-sm text-theme-secondary">{'\u2014'}</span>
                    )}
                  </td>

                  {/* Updated */}
                  <td className="px-4 py-3">
                    <span className="text-sm text-theme-tertiary">{timeAgo(mission.updated_at)}</span>
                  </td>

                  {/* Actions */}
                  <td className="px-3 py-3">
                    <div className="flex items-center gap-0.5" onClick={(e) => e.stopPropagation()}>
                      <Button
                        variant="ghost"
                        size="sm"
                        iconOnly
                        onClick={() => openMission(mission.id)}
                        title="View details"
                      >
                        <Eye className="h-3.5 w-3.5" />
                      </Button>

                      {hasManagePermission && canStart(mission) && (
                        <Button
                          variant="ghost"
                          size="sm"
                          iconOnly
                          onClick={() => onStartMission(mission.id)}
                          title="Start"
                        >
                          <Play className="h-3.5 w-3.5" />
                        </Button>
                      )}

                      {hasManagePermission && mission.status === 'active' && !isApprovalGate(mission.current_phase, mission.approval_gate_phases) && (
                        <Button
                          variant="ghost"
                          size="sm"
                          iconOnly
                          onClick={() => onPauseMission(mission.id)}
                          title="Pause"
                        >
                          <Pause className="h-3.5 w-3.5" />
                        </Button>
                      )}

                      {hasManagePermission && isApprovalGate(mission.current_phase, mission.approval_gate_phases) && (
                        <Button
                          variant="ghost"
                          size="sm"
                          iconOnly
                          onClick={() => onApproveMission(mission.id)}
                          title="Approve"
                        >
                          <CheckCircle className="h-3.5 w-3.5" />
                        </Button>
                      )}

                      {hasManagePermission && canCancel(mission) && (
                        <DropdownMenu
                          trigger={
                            <Button variant="ghost" size="sm" iconOnly title="More actions">
                              <MoreHorizontal className="h-3.5 w-3.5" />
                            </Button>
                          }
                          items={[
                            { icon: XCircle, label: 'Cancel', onClick: () => onCancelMission(mission.id), danger: true },
                          ]}
                          align="right"
                          width="w-36"
                        />
                      )}
                    </div>
                  </td>
                </tr>

                {/* Expanded row */}
                {expandedRows.has(mission.id) && (
                  <MissionExpandedRow mission={mission} />
                )}
              </React.Fragment>
            ))}
          </tbody>
        </table>

        {/* Empty state */}
        {!loading && filteredMissions.length === 0 && (
          <div className="flex flex-col items-center justify-center py-12 px-4">
            <Rocket className="w-10 h-10 text-theme-tertiary mb-3" />
            <p className="text-sm text-theme-tertiary">{search ? 'No matching missions' : 'No missions found'}</p>
          </div>
        )}

        {/* Loading state */}
        {loading && missions.length === 0 && (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="w-6 h-6 text-theme-secondary animate-spin" />
          </div>
        )}
      </div>

      {/* Footer */}
      {missions.length > 0 && (
        <div className="flex items-center justify-between mt-3 text-xs text-theme-tertiary">
          <span>Showing {filteredMissions.length} of {missions.length} missions</span>
          <span>{missions.filter(m => m.status === 'active').length} active</span>
        </div>
      )}
    </div>
  );
};

// --- Helpers ---

function canStart(mission: Mission): boolean {
  return mission.status === 'draft' || mission.status === 'paused';
}

function canCancel(mission: Mission): boolean {
  return ['active', 'paused', 'draft'].includes(mission.status);
}
