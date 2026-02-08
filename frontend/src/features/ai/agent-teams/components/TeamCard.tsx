// Team Card Component - Displays a single team with expandable details

import React, { useState } from 'react';
import { Users, Crown, Play, Edit2, Trash2, ChevronDown, Bot, Settings, Clock } from 'lucide-react';
import { AgentTeam, agentTeamsApi, TeamMember } from '../services/agentTeamsApi';

interface TeamCardProps {
  team: AgentTeam;
  onEdit: (team: AgentTeam) => void;
  onDelete: (team: AgentTeam) => void;
  onExecute: (team: AgentTeam) => void;
}

export const TeamCard: React.FC<TeamCardProps> = ({ team, onEdit, onDelete, onExecute }) => {
  const [expanded, setExpanded] = useState(false);
  const [members, setMembers] = useState<TeamMember[]>([]);
  const [loadingMembers, setLoadingMembers] = useState(false);

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

  const handleToggleExpand = async () => {
    if (!expanded && members.length === 0) {
      setLoadingMembers(true);
      try {
        const detail = await agentTeamsApi.getTeam(team.id);
        setMembers(detail.members || []);
      } catch {
        // Silently handle
      } finally {
        setLoadingMembers(false);
      }
    }
    setExpanded(!expanded);
  };

  return (
    <div data-testid="team-card" className="bg-theme-surface border border-theme rounded-lg hover:shadow-md transition-shadow">
      {/* Clickable header area */}
      <div
        className="p-6 cursor-pointer"
        onClick={handleToggleExpand}
      >
        {/* Header */}
        <div className="flex items-start justify-between mb-4">
          <div className="flex-1">
            <div className="flex items-center gap-2">
              <h3 data-testid="team-name" className="text-lg font-semibold text-theme-primary">{team.name}</h3>
              <ChevronDown className={`h-4 w-4 text-theme-secondary transition-transform ${expanded ? 'rotate-180' : ''}`} />
            </div>
            <p className="text-sm text-theme-secondary line-clamp-2 mt-1">{team.description}</p>
          </div>

          {/* Status Badge */}
          <span data-testid="team-status-badge" className={`px-2 py-1 text-xs font-medium rounded-full ${getStatusColor(team.status)}`}>
            {team.status}
          </span>
        </div>

        {/* Team Info */}
        <div className="flex flex-wrap gap-2 mb-4">
          <span data-testid="team-type-badge" className={`px-2 py-1 text-xs font-medium rounded-full ${getTeamTypeColor(team.team_type)}`}>
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

      {/* Expanded Details */}
      {expanded && (
        <div className="px-6 pb-4 border-t border-theme pt-4 space-y-4">
          {/* Members */}
          <div>
            <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide mb-2">Members</h4>
            {loadingMembers ? (
              <div className="text-xs text-theme-secondary py-2">Loading members...</div>
            ) : members.length === 0 ? (
              <div className="text-xs text-theme-secondary py-2">No members assigned</div>
            ) : (
              <div className="space-y-2">
                {members.map((member) => (
                  <div key={member.id} className="flex items-center gap-3 p-2 rounded-md bg-theme-background">
                    <Bot className="h-4 w-4 text-theme-info flex-shrink-0" />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-medium text-theme-primary truncate">{member.agent_name}</span>
                        {member.is_lead && (
                          <Crown className="h-3 w-3 text-theme-warning flex-shrink-0" />
                        )}
                      </div>
                      <span className="text-xs text-theme-secondary">{member.role}</span>
                    </div>
                    <span className="text-xs text-theme-secondary flex-shrink-0">#{member.priority_order}</span>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Config */}
          {team.team_config && (
            <div>
              <h4 className="text-xs font-semibold text-theme-secondary uppercase tracking-wide mb-2">Configuration</h4>
              <div className="grid grid-cols-2 gap-2">
                {team.team_config.max_iterations != null && (
                  <div className="flex items-center gap-2 text-xs text-theme-primary">
                    <Settings className="h-3 w-3 text-theme-secondary" />
                    <span>Max iterations: {team.team_config.max_iterations}</span>
                  </div>
                )}
                {team.team_config.timeout_seconds != null && (
                  <div className="flex items-center gap-2 text-xs text-theme-primary">
                    <Clock className="h-3 w-3 text-theme-secondary" />
                    <span>Timeout: {team.team_config.timeout_seconds}s</span>
                  </div>
                )}
              </div>
            </div>
          )}

          {/* Timestamps */}
          <div className="flex gap-4 text-xs text-theme-secondary">
            <span>Created: {new Date(team.created_at).toLocaleDateString()}</span>
            <span>Updated: {new Date(team.updated_at).toLocaleDateString()}</span>
          </div>
        </div>
      )}

      {/* Actions - always visible */}
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
          onClick={(e) => { e.stopPropagation(); onEdit(team); }}
          className="btn-theme btn-theme-secondary btn-theme-sm flex items-center gap-1"
        >
          <Edit2 size={16} />
          Edit
        </button>

        <button
          onClick={(e) => { e.stopPropagation(); onDelete(team); }}
          className="flex items-center gap-1 px-3 py-2 text-sm font-medium text-theme-danger bg-theme-error/10 rounded-md hover:bg-theme-error/20 transition-colors"
        >
          <Trash2 size={16} />
          Delete
        </button>
      </div>
    </div>
  );
};
