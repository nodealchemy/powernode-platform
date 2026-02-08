// Team Card Component - Displays a single team with expandable full-width details

import React from 'react';
import { Users, Crown, Play, Trash2, ChevronDown } from 'lucide-react';
import { AgentTeam } from '../services/agentTeamsApi';
import { TeamExpandedView } from './TeamExpandedView';
import { TeamExecutionDiagram } from './diagram';
import { cn } from '@/shared/utils/cn';

interface TeamCardProps {
  team: AgentTeam;
  isExpanded: boolean;
  isExecuting: boolean;
  onToggleExpand: (teamId: string) => void;
  onDelete: (team: AgentTeam) => void;
  onExecute: (team: AgentTeam) => void;
  onExecutionComplete: (teamId: string) => void;
  onDismissMonitor: (teamId: string) => void;
  onTeamUpdated: () => void;
}

const getTeamTypeColor = (type: string) => {
  switch (type) {
    case 'hierarchical':
      return 'bg-theme-info/10 text-theme-info';
    case 'mesh':
      return 'bg-theme-interactive-primary/10 text-theme-interactive-primary';
    case 'sequential':
      return 'bg-theme-success/10 text-theme-success';
    case 'parallel':
      return 'bg-theme-warning/10 text-theme-warning';
    default:
      return 'bg-theme-accent text-theme-secondary';
  }
};

const getStatusColor = (status: string) => {
  switch (status) {
    case 'active':
      return 'bg-theme-success/10 text-theme-success';
    case 'inactive':
      return 'bg-theme-accent text-theme-secondary';
    case 'archived':
      return 'bg-theme-error/10 text-theme-error';
    default:
      return 'bg-theme-accent text-theme-secondary';
  }
};

export const TeamCard: React.FC<TeamCardProps> = ({
  team,
  isExpanded,
  isExecuting,
  onToggleExpand,
  onDelete,
  onExecute,
  onExecutionComplete,
  onDismissMonitor,
  onTeamUpdated,
}) => {
  return (
    <div
      data-testid="team-card"
      className={cn(
        'bg-theme-surface border border-theme rounded-lg hover:shadow-md transition-all',
        isExpanded && 'col-span-full shadow-lg',
        isExecuting && 'border-theme-info/50'
      )}
    >
      {/* Clickable header area */}
      <div
        className="p-6 cursor-pointer"
        onClick={() => onToggleExpand(team.id)}
      >
        {/* Header */}
        <div className="flex items-start justify-between mb-4">
          <div className="flex-1">
            <div className="flex items-center gap-2">
              <h3 data-testid="team-name" className="text-lg font-semibold text-theme-primary">{team.name}</h3>
              <ChevronDown className={cn('h-4 w-4 text-theme-secondary transition-transform', isExpanded && 'rotate-180')} />
            </div>
            <p className="text-sm text-theme-secondary line-clamp-2 mt-1">{team.description}</p>
          </div>

          {/* Status Badge */}
          <span data-testid="team-status-badge" className={cn('px-2 py-1 text-xs font-medium rounded-full', getStatusColor(team.status))}>
            {team.status}
          </span>
        </div>

        {/* Team Info */}
        <div className="flex flex-wrap gap-2 mb-4">
          <span data-testid="team-type-badge" className={cn('px-2 py-1 text-xs font-medium rounded-full', getTeamTypeColor(team.team_type))}>
            {team.team_type}
          </span>

          <span className="flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-full bg-theme-accent text-theme-primary">
            <Users size={12} />
            {team.member_count} {team.member_count === 1 ? 'member' : 'members'}
          </span>

          {team.has_lead && (
            <span className="flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-full bg-theme-warning/10 text-theme-warning">
              <Crown size={12} />
              Has Lead
            </span>
          )}
        </div>

        {/* Coordination Strategy */}
        <div className="text-xs text-theme-secondary">
          <span className="font-medium">Strategy:</span> {team.coordination_strategy.replace('_', ' ')}
        </div>
      </div>

      {/* Inline Execution Monitor - appears inside the card when not expanded */}
      {isExecuting && !isExpanded && (
        <div className="px-6 pb-4" onClick={(e) => e.stopPropagation()}>
          <TeamExecutionDiagram
            teamId={team.id}
            team={team}
            onExecutionComplete={() => onExecutionComplete(team.id)}
            onDismiss={() => onDismissMonitor(team.id)}
          />
        </div>
      )}

      {/* Expanded Full-Width Management View */}
      {isExpanded && (
        <TeamExpandedView
          team={team}
          isExecuting={isExecuting}
          onDelete={onDelete}
          onExecute={onExecute}
          onExecutionComplete={onExecutionComplete}
          onDismissMonitor={onDismissMonitor}
          onTeamUpdated={onTeamUpdated}
        />
      )}

      {/* Compact Actions - only when collapsed */}
      {!isExpanded && (
        <div className="flex gap-2 px-6 pb-6 pt-2">
          <button
            onClick={(e) => { e.stopPropagation(); onExecute(team); }}
            disabled={team.status !== 'active' || team.member_count === 0}
            className="btn-theme btn-theme-primary btn-theme-sm flex items-center gap-1"
          >
            <Play size={16} />
            Execute
          </button>

          <button
            onClick={(e) => { e.stopPropagation(); onDelete(team); }}
            className="flex items-center gap-1 px-3 py-2 text-sm font-medium text-theme-danger bg-theme-error/10 rounded-md hover:bg-theme-error/20 transition-colors"
          >
            <Trash2 size={16} />
            Delete
          </button>
        </div>
      )}
    </div>
  );
};
