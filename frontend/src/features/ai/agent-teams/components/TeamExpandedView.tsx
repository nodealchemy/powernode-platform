// Team Expanded View - Full-width management interface for an expanded team card

import React, { useState, useEffect } from 'react';
import {
  Play, Save, Trash2, Zap, Crown, Bot, Settings, X, Loader2, Shield,
  Edit2, History, Activity,
} from 'lucide-react';
import { AgentTeam, TeamMember, AutonomyConfigResponse, agentTeamsApi, UpdateTeamParams } from '../services/agentTeamsApi';
import { TeamExecutionHistory } from './TeamExecutionHistory';
import { TeamExecutionDiagram } from './diagram';
import { CompositionOptimizer } from './CompositionOptimizer';
import { formatDateTime } from '@/shared/utils/formatters';
import { cn } from '@/shared/utils/cn';
import { useDispatch } from 'react-redux';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { AppDispatch } from '@/shared/services';

interface TeamExpandedViewProps {
  team: AgentTeam;
  isExecuting?: boolean;
  onDelete: (team: AgentTeam) => void;
  onExecute: (team: AgentTeam) => void;
  onExecutionComplete?: (teamId: string) => void;
  onDismissMonitor?: (teamId: string) => void;
  onTeamUpdated: () => void;
}

const TEAM_TYPES = [
  { value: 'hierarchical', label: 'Hierarchical' },
  { value: 'mesh', label: 'Mesh' },
  { value: 'sequential', label: 'Sequential' },
  { value: 'parallel', label: 'Parallel' },
];

const STRATEGIES = [
  { value: 'manager_worker', label: 'Manager-Worker' },
  { value: 'peer_to_peer', label: 'Peer-to-Peer' },
  { value: 'hybrid', label: 'Hybrid' },
];

const STATUSES = [
  { value: 'active', label: 'Active' },
  { value: 'inactive', label: 'Inactive' },
  { value: 'archived', label: 'Archived' },
];

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

export const TeamExpandedView: React.FC<TeamExpandedViewProps> = ({
  team,
  isExecuting = false,
  onDelete,
  onExecute,
  onExecutionComplete,
  onDismissMonitor,
  onTeamUpdated,
}) => {
  const dispatch = useDispatch<AppDispatch>();
  const [members, setMembers] = useState<TeamMember[]>([]);
  const [autonomyConfig, setAutonomyConfig] = useState<AutonomyConfigResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [optimizing, setOptimizing] = useState(false);
  const [assigningLead, setAssigningLead] = useState(false);
  const [removingMemberId, setRemovingMemberId] = useState<string | null>(null);

  // Inline editing state
  const [isEditing, setIsEditing] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [editData, setEditData] = useState<UpdateTeamParams>({
    name: team.name,
    description: team.description,
    team_type: team.team_type,
    coordination_strategy: team.coordination_strategy,
    status: team.status,
  });

  // History visibility
  const [showHistory, setShowHistory] = useState(false);

  useEffect(() => {
    const loadData = async () => {
      setLoading(true);
      try {
        const [teamDetail, config] = await Promise.all([
          agentTeamsApi.getTeam(team.id),
          agentTeamsApi.getAutonomyConfig(team.id).catch(() => null),
        ]);
        setMembers(teamDetail.members || []);
        setAutonomyConfig(config);
      } catch {
        dispatch(addNotification({ type: 'error', message: 'Failed to load team details' }));
      } finally {
        setLoading(false);
      }
    };
    loadData();
  }, [team.id]);

  // Reset edit data when team changes
  useEffect(() => {
    setEditData({
      name: team.name,
      description: team.description,
      team_type: team.team_type,
      coordination_strategy: team.coordination_strategy,
      status: team.status,
    });
    setIsEditing(false);
  }, [team.id]);

  const handleSave = async () => {
    setIsSaving(true);
    try {
      await agentTeamsApi.updateTeam(team.id, editData);
      dispatch(addNotification({ type: 'success', message: 'Team updated successfully' }));
      setIsEditing(false);
      onTeamUpdated();
    } catch {
      dispatch(addNotification({ type: 'error', message: 'Failed to update team' }));
    } finally {
      setIsSaving(false);
    }
  };

  const handleCancelEdit = () => {
    setEditData({
      name: team.name,
      description: team.description,
      team_type: team.team_type,
      coordination_strategy: team.coordination_strategy,
      status: team.status,
    });
    setIsEditing(false);
  };

  const handleRemoveMember = async (memberId: string) => {
    setRemovingMemberId(memberId);
    try {
      await agentTeamsApi.removeMember(team.id, memberId);
      setMembers(prev => prev.filter(m => m.id !== memberId));
      onTeamUpdated();
      dispatch(addNotification({ type: 'success', message: 'Member removed' }));
    } catch {
      dispatch(addNotification({ type: 'error', message: 'Failed to remove member' }));
    } finally {
      setRemovingMemberId(null);
    }
  };

  const handleOptimize = async () => {
    setOptimizing(true);
    try {
      await agentTeamsApi.optimizeTeam(team.id);
      dispatch(addNotification({ type: 'success', message: 'Team optimization started' }));
      onTeamUpdated();
    } catch {
      dispatch(addNotification({ type: 'error', message: 'Failed to optimize team' }));
    } finally {
      setOptimizing(false);
    }
  };

  const handleAutoAssignLead = async () => {
    setAssigningLead(true);
    try {
      const updated = await agentTeamsApi.autoAssignLead(team.id);
      setMembers(updated.members || []);
      onTeamUpdated();
      dispatch(addNotification({ type: 'success', message: 'Lead auto-assigned' }));
    } catch {
      dispatch(addNotification({ type: 'error', message: 'Failed to auto-assign lead' }));
    } finally {
      setAssigningLead(false);
    }
  };

  if (loading) {
    return (
      <div className="px-6 pb-6 border-t border-theme pt-6">
        <div className="flex items-center justify-center py-12">
          <Loader2 className="h-6 w-6 animate-spin text-theme-primary" />
        </div>
      </div>
    );
  }

  return (
    <div className="px-6 pb-6 border-t border-theme pt-4 space-y-6" onClick={(e) => e.stopPropagation()}>
      {/* Actions Bar */}
      <div className="flex flex-wrap items-center gap-2">
        <button
          onClick={() => onExecute(team)}
          disabled={team.status !== 'active' || team.member_count === 0}
          className="btn-theme btn-theme-primary btn-theme-sm flex items-center gap-1"
        >
          <Play size={14} />
          Execute
        </button>
        {!isEditing ? (
          <button
            onClick={() => setIsEditing(true)}
            className="btn-theme btn-theme-secondary btn-theme-sm flex items-center gap-1"
          >
            <Edit2 size={14} />
            Edit
          </button>
        ) : (
          <>
            <button
              onClick={handleSave}
              disabled={isSaving || !editData.name}
              className="btn-theme btn-theme-primary btn-theme-sm flex items-center gap-1"
            >
              {isSaving ? <Loader2 size={14} className="animate-spin" /> : <Save size={14} />}
              Save
            </button>
            <button
              onClick={handleCancelEdit}
              disabled={isSaving}
              className="btn-theme btn-theme-secondary btn-theme-sm flex items-center gap-1"
            >
              <X size={14} />
              Cancel
            </button>
          </>
        )}
        <button
          onClick={handleOptimize}
          disabled={optimizing}
          className="flex items-center gap-1 px-3 py-2 text-sm font-medium text-theme-primary bg-theme-primary/10 rounded-md hover:bg-theme-primary/20 transition-colors disabled:opacity-50"
        >
          {optimizing ? <Loader2 size={14} className="animate-spin" /> : <Zap size={14} />}
          Optimize
        </button>
        <button
          onClick={handleAutoAssignLead}
          disabled={assigningLead}
          className="flex items-center gap-1 px-3 py-2 text-sm font-medium text-theme-warning bg-theme-warning/10 rounded-md hover:bg-theme-warning/20 transition-colors disabled:opacity-50"
        >
          {assigningLead ? <Loader2 size={14} className="animate-spin" /> : <Crown size={14} />}
          Auto-Assign Lead
        </button>
        <button
          onClick={() => setShowHistory(prev => !prev)}
          className={cn(
            'flex items-center gap-1 px-3 py-2 text-sm font-medium rounded-md transition-colors',
            showHistory
              ? 'text-theme-info bg-theme-info/20'
              : 'text-theme-secondary bg-theme-accent hover:bg-theme-accent/80'
          )}
        >
          <History size={14} />
          History
        </button>
        <button
          onClick={() => onDelete(team)}
          className="flex items-center gap-1 px-3 py-2 text-sm font-medium text-theme-danger bg-theme-error/10 rounded-md hover:bg-theme-error/20 transition-colors ml-auto"
        >
          <Trash2 size={14} />
          Delete
        </button>
      </div>

      {/* Live Execution Diagram */}
      {isExecuting && (
        <div className="bg-theme-background border border-theme-info/30 rounded-lg p-4">
          <div className="flex items-center gap-2 mb-3">
            <Activity size={16} className="text-theme-info animate-pulse" />
            <h4 className="text-sm font-semibold text-theme-primary">Live Execution</h4>
          </div>
          <TeamExecutionDiagram
            teamId={team.id}
            team={team}
            onExecutionComplete={() => onExecutionComplete?.(team.id)}
            onDismiss={() => onDismissMonitor?.(team.id)}
          />
        </div>
      )}

      {/* Execution History */}
      {showHistory && (
        <div className="bg-theme-background border border-theme rounded-lg p-4">
          <TeamExecutionHistory teamId={team.id} />
        </div>
      )}

      {/* Team Details — full-width view/edit toggle */}
      <div className={cn(
        'bg-theme-background border rounded-lg p-4 space-y-3',
        isEditing ? 'border-theme-info/30' : 'border-theme'
      )}>
        <h4 className="text-sm font-semibold text-theme-primary flex items-center gap-2">
          <Settings size={16} />
          Team Details
        </h4>

        {isEditing ? (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label htmlFor="edit-name" className="block text-xs font-medium text-theme-secondary mb-1">Name</label>
              <input
                id="edit-name"
                type="text"
                value={editData.name || ''}
                onChange={(e) => setEditData(prev => ({ ...prev, name: e.target.value }))}
                className="w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-info"
              />
            </div>
            <div>
              <label htmlFor="edit-status" className="block text-xs font-medium text-theme-secondary mb-1">Status</label>
              <select
                id="edit-status"
                value={editData.status || 'active'}
                onChange={(e) => setEditData(prev => ({ ...prev, status: e.target.value as 'active' | 'inactive' | 'archived' }))}
                className="w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-info"
              >
                {STATUSES.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
              </select>
            </div>
            <div>
              <label htmlFor="edit-type" className="block text-xs font-medium text-theme-secondary mb-1">Team Type</label>
              <select
                id="edit-type"
                value={editData.team_type || 'hierarchical'}
                onChange={(e) => setEditData(prev => ({ ...prev, team_type: e.target.value as 'hierarchical' | 'mesh' | 'sequential' | 'parallel' }))}
                className="w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-info"
              >
                {TEAM_TYPES.map(t => <option key={t.value} value={t.value}>{t.label}</option>)}
              </select>
            </div>
            <div>
              <label htmlFor="edit-strategy" className="block text-xs font-medium text-theme-secondary mb-1">Coordination Strategy</label>
              <select
                id="edit-strategy"
                value={editData.coordination_strategy || 'manager_worker'}
                onChange={(e) => setEditData(prev => ({ ...prev, coordination_strategy: e.target.value as 'manager_worker' | 'peer_to_peer' | 'hybrid' }))}
                className="w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-info"
              >
                {STRATEGIES.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
              </select>
            </div>
            <div className="md:col-span-2">
              <label htmlFor="edit-description" className="block text-xs font-medium text-theme-secondary mb-1">Description</label>
              <textarea
                id="edit-description"
                value={editData.description || ''}
                onChange={(e) => setEditData(prev => ({ ...prev, description: e.target.value }))}
                rows={2}
                className="w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-info"
              />
            </div>
          </div>
        ) : (
          <div className="grid grid-cols-2 md:grid-cols-4 gap-x-6 gap-y-3">
            <div>
              <span className="text-xs text-theme-secondary block mb-0.5">Name</span>
              <span className="text-sm text-theme-primary font-medium">{team.name}</span>
            </div>
            <div>
              <span className="text-xs text-theme-secondary block mb-0.5">Status</span>
              <span className={cn('px-2 py-0.5 text-xs font-medium rounded-full', getStatusColor(team.status))}>
                {team.status}
              </span>
            </div>
            <div>
              <span className="text-xs text-theme-secondary block mb-0.5">Type</span>
              <span className={cn('px-2 py-0.5 text-xs font-medium rounded-full', getTeamTypeColor(team.team_type))}>
                {team.team_type}
              </span>
            </div>
            <div>
              <span className="text-xs text-theme-secondary block mb-0.5">Strategy</span>
              <span className="text-sm text-theme-primary font-medium capitalize">
                {team.coordination_strategy.replace('_', ' ')}
              </span>
            </div>
            {team.description && (
              <div className="col-span-2 md:col-span-4">
                <span className="text-xs text-theme-secondary block mb-0.5">Description</span>
                <p className="text-sm text-theme-primary">{team.description}</p>
              </div>
            )}
            {(team.team_config?.max_iterations != null || team.team_config?.timeout_seconds != null) && (
              <>
                {team.team_config?.max_iterations != null && (
                  <div>
                    <span className="text-xs text-theme-secondary block mb-0.5">Max Iterations</span>
                    <span className="text-sm text-theme-primary font-medium">{team.team_config.max_iterations}</span>
                  </div>
                )}
                {team.team_config?.timeout_seconds != null && (
                  <div>
                    <span className="text-xs text-theme-secondary block mb-0.5">Timeout</span>
                    <span className="text-sm text-theme-primary font-medium">{team.team_config.timeout_seconds}s</span>
                  </div>
                )}
              </>
            )}
            <div>
              <span className="text-xs text-theme-secondary block mb-0.5">Created</span>
              <span className="text-xs text-theme-primary">{formatDateTime(team.created_at)}</span>
            </div>
            <div>
              <span className="text-xs text-theme-secondary block mb-0.5">Updated</span>
              <span className="text-xs text-theme-primary">{formatDateTime(team.updated_at)}</span>
            </div>
          </div>
        )}
      </div>

      {/* Members + Health/Autonomy layout */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Members */}
        <div className="lg:col-span-2">
          <div className="bg-theme-background border border-theme rounded-lg p-4">
            <h4 className="text-sm font-semibold text-theme-primary mb-3 flex items-center gap-2">
              <Bot size={16} />
              Members ({members.length})
            </h4>
            {members.length === 0 ? (
              <div className="text-sm text-theme-secondary py-6 text-center">No members assigned</div>
            ) : (
              <div className="space-y-2">
                {members.map((member) => (
                  <div
                    key={member.id}
                    className="flex items-center gap-3 p-3 rounded-md bg-theme-surface border border-theme"
                  >
                    <Bot className="h-5 w-5 text-theme-info flex-shrink-0" />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-medium text-theme-primary truncate">
                          {member.agent_name}
                        </span>
                        {member.is_lead && (
                          <Crown className="h-3.5 w-3.5 text-theme-warning flex-shrink-0" />
                        )}
                      </div>
                      <div className="flex items-center gap-2 mt-0.5">
                        <span className="text-xs font-medium text-theme-interactive-primary bg-theme-interactive-primary/10 px-1.5 py-0.5 rounded">
                          {member.role}
                        </span>
                        {member.capabilities.length > 0 && (
                          <span className="text-xs text-theme-secondary truncate">
                            {member.capabilities.join(', ')}
                          </span>
                        )}
                      </div>
                    </div>
                    <span className="text-xs text-theme-secondary flex-shrink-0 tabular-nums">
                      #{member.priority_order}
                    </span>
                    <button
                      onClick={() => handleRemoveMember(member.id)}
                      disabled={removingMemberId === member.id}
                      className="flex-shrink-0 p-1 rounded hover:bg-theme-error/10 text-theme-secondary hover:text-theme-danger transition-colors disabled:opacity-50"
                      title="Remove member"
                    >
                      {removingMemberId === member.id ? (
                        <Loader2 size={14} className="animate-spin" />
                      ) : (
                        <X size={14} />
                      )}
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Health + Autonomy */}
        <div className="space-y-6">
          <CompositionOptimizer teamId={team.id} />

          {autonomyConfig && (
            <div className="bg-theme-background border border-theme rounded-lg p-4 space-y-3">
              <h4 className="text-sm font-semibold text-theme-primary flex items-center gap-2">
                <Shield size={16} />
                Autonomy Config
              </h4>
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <span className="text-xs text-theme-secondary">Level</span>
                  <span className="text-xs text-theme-primary font-medium capitalize">
                    {autonomyConfig.autonomy_level.replace('_', ' ')}
                  </span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-xs text-theme-secondary">Max Agents</span>
                  <span className="text-xs text-theme-primary font-medium">{autonomyConfig.max_agents_per_team}</span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-xs text-theme-secondary">Agent Creation</span>
                  <BoolBadge value={autonomyConfig.allow_agent_creation} />
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-xs text-theme-secondary">Cross-Team Ops</span>
                  <BoolBadge value={autonomyConfig.allow_cross_team_ops} />
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-xs text-theme-secondary">Human Approval</span>
                  <BoolBadge value={autonomyConfig.require_human_approval} />
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-xs text-theme-secondary">Branch Protection</span>
                  <BoolBadge value={autonomyConfig.branch_protection_enabled} />
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

const BoolBadge: React.FC<{ value: boolean }> = ({ value }) => (
  <span className={cn(
    'text-xs font-medium px-1.5 py-0.5 rounded',
    value ? 'bg-theme-success/10 text-theme-success' : 'bg-theme-accent text-theme-secondary'
  )}>
    {value ? 'Yes' : 'No'}
  </span>
);
