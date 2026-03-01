// Team Expanded View - Full-width management interface for an expanded team card

import React, { useState, useEffect } from 'react';
import {
  Play, Save, Trash2, Zap, Crown, X, Loader2,
  Edit2, History, Activity,
} from 'lucide-react';
import { AgentTeam, TeamMember, AutonomyConfigResponse, agentTeamsApi, UpdateTeamParams } from '../services/agentTeamsApi';
import { TeamExecutionHistory } from './TeamExecutionHistory';
import { TeamExecutionDiagram } from './diagram';
import { CompositionOptimizer } from './CompositionOptimizer';
import { TeamSettingsForm } from './TeamSettingsForm';
import { MembersList } from './MembersList';
import { AutonomyConfig } from './AutonomyConfig';
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

  const [isEditing, setIsEditing] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [editData, setEditData] = useState<UpdateTeamParams>({
    name: team.name,
    description: team.description,
    team_type: team.team_type,
    coordination_strategy: team.coordination_strategy,
    status: team.status,
  });

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

      {/* Team Details */}
      <TeamSettingsForm
        team={team}
        isEditing={isEditing}
        editData={editData}
        setEditData={setEditData}
      />

      {/* Members + Health/Autonomy layout */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2">
          <MembersList
            members={members}
            removingMemberId={removingMemberId}
            onRemoveMember={handleRemoveMember}
          />
        </div>

        <div className="space-y-6">
          <CompositionOptimizer teamId={team.id} />
          {autonomyConfig && (
            <AutonomyConfig autonomyConfig={autonomyConfig} />
          )}
        </div>
      </div>
    </div>
  );
};
