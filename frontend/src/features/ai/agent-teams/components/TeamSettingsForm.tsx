import React from 'react';
import { Settings } from 'lucide-react';
import { cn } from '@/shared/utils/cn';
import { formatDateTime } from '@/shared/utils/formatters';
import { AgentTeam, UpdateTeamParams } from '../services/agentTeamsApi';

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

interface TeamSettingsFormProps {
  team: AgentTeam;
  isEditing: boolean;
  editData: UpdateTeamParams;
  setEditData: React.Dispatch<React.SetStateAction<UpdateTeamParams>>;
}

export const TeamSettingsForm: React.FC<TeamSettingsFormProps> = ({
  team,
  isEditing,
  editData,
  setEditData,
}) => {
  return (
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
  );
};
