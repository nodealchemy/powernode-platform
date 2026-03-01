import React from 'react';
import { UserCog } from 'lucide-react';
import { Team, TeamRole } from '@/shared/services/ai/TeamsApiService';

interface RolesTabProps {
  selectedTeam: Team | null;
  roles: TeamRole[];
}

export const RolesTab: React.FC<RolesTabProps> = ({ selectedTeam, roles }) => {
  if (!selectedTeam) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <p className="text-theme-secondary">Select a team to view roles</p>
      </div>
    );
  }

  if (roles.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <UserCog size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No roles defined</h3>
        <p className="text-theme-secondary mb-6">Define roles for team members</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {roles.map(role => (
        <div key={role.id} className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-3">
              <h3 className="font-medium text-theme-primary">{role.role_name}</h3>
              <span className="px-2 py-1 text-xs bg-theme-accent/10 text-theme-accent rounded">{role.role_type}</span>
              <span className="text-xs text-theme-secondary">Priority: {role.priority_order}</span>
            </div>
            <div className="flex gap-2 text-xs">
              {role.can_delegate && <span className="px-2 py-1 bg-theme-info/10 text-theme-info rounded">Can Delegate</span>}
              {role.can_escalate && <span className="px-2 py-1 bg-theme-warning/10 text-theme-warning rounded">Can Escalate</span>}
            </div>
          </div>
          {role.role_description && <p className="text-sm text-theme-secondary mb-2">{role.role_description}</p>}
          <div className="flex gap-4 text-xs text-theme-secondary">
            <span>Agent: {role.agent_name || 'Unassigned'}</span>
            <span>Max tasks: {role.max_concurrent_tasks}</span>
            {role.capabilities.length > 0 && <span>{role.capabilities.length} capabilities</span>}
            {role.tools_allowed.length > 0 && <span>{role.tools_allowed.length} tools</span>}
          </div>
        </div>
      ))}
    </div>
  );
};
