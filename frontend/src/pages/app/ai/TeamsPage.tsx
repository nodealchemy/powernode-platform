// Teams Management Page — Full-Width Index Table
import React, { useState } from 'react';
import { Plus, Users, Play } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Modal } from '@/shared/components/ui/Modal';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useNotification } from '@/shared/hooks/useNotification';
import { teamsApi } from '@/shared/services/ai/TeamsApiService';
import type { Team } from '@/shared/services/ai/TeamsApiService';
import { TeamsIndexTable } from '@/features/ai/agent-teams/components/TeamsIndexTable';

const TeamsPage: React.FC = () => {
  const { confirm, ConfirmationDialog } = useConfirmation();
  const { showNotification } = useNotification();

  // Create team modal
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [newTeamName, setNewTeamName] = useState('');
  const [newTeamDescription, setNewTeamDescription] = useState('');
  const [newTeamTopology, setNewTeamTopology] = useState<string>('hierarchical');

  // Start execution modal
  const [showExecutionModal, setShowExecutionModal] = useState(false);
  const [executionTeam, setExecutionTeam] = useState<Team | null>(null);
  const [executionObjective, setExecutionObjective] = useState('');

  // Refresh key to trigger table reload
  const [refreshKey, setRefreshKey] = useState(0);

  const handleCreateTeam = async () => {
    if (!newTeamName.trim()) return;
    try {
      await teamsApi.createTeam({
        name: newTeamName,
        description: newTeamDescription || undefined,
        team_topology: newTeamTopology as Team['team_topology'],
      });
      showNotification('Team created', 'success');
      setShowCreateModal(false);
      setNewTeamName('');
      setNewTeamDescription('');
      setRefreshKey(prev => prev + 1);
    } catch {
      showNotification('Failed to create team', 'error');
    }
  };

  const handleDeleteTeam = (teamId: string) => {
    confirm({
      title: 'Delete Team',
      message: 'Are you sure you want to delete this team? This will permanently remove all roles, channels, and execution history.',
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await teamsApi.deleteTeam(teamId);
          showNotification('Team deleted', 'success');
          setRefreshKey(prev => prev + 1);
        } catch {
          showNotification('Failed to delete team', 'error');
        }
      },
    });
  };

  const handleStartExecution = async () => {
    if (!executionTeam || !executionObjective.trim()) return;
    try {
      await teamsApi.startExecution(executionTeam.id, { objective: executionObjective });
      showNotification('Execution started', 'success');
      setShowExecutionModal(false);
      setExecutionObjective('');
      setExecutionTeam(null);
    } catch {
      showNotification('Failed to start execution', 'error');
    }
  };

  const handleOpenExecution = (team: Team) => {
    setExecutionTeam(team);
    setShowExecutionModal(true);
  };

  return (
    <PageContainer
      title="Team Orchestration"
      description="Multi-agent team management and execution"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Teams' },
      ]}
      actions={[
        { id: 'create-team', label: 'Create Team', onClick: () => setShowCreateModal(true), icon: Plus, variant: 'primary' as const },
      ]}
    >
      <TeamsIndexTable
        onStartExecution={handleOpenExecution}
        onDeleteTeam={handleDeleteTeam}
        refreshKey={refreshKey}
      />

      {/* Create Team Modal */}
      <Modal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        title="Create Team"
        maxWidth="md"
        icon={<Users />}
        footer={
          <div className="flex justify-end gap-3">
            <button onClick={() => setShowCreateModal(false)} className="btn-theme btn-theme-secondary">Cancel</button>
            <button onClick={handleCreateTeam} disabled={!newTeamName.trim()} className="btn-theme btn-theme-primary">Create</button>
          </div>
        }
      >
        <div className="space-y-4 p-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Name</label>
            <input type="text" value={newTeamName} onChange={(e) => setNewTeamName(e.target.value)} placeholder="Team name" className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent" />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Topology</label>
            <select value={newTeamTopology} onChange={(e) => setNewTeamTopology(e.target.value)} className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent">
              <option value="hierarchical">Hierarchical</option>
              <option value="flat">Flat</option>
              <option value="mesh">Mesh</option>
              <option value="pipeline">Pipeline</option>
              <option value="hybrid">Hybrid</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Description</label>
            <textarea value={newTeamDescription} onChange={(e) => setNewTeamDescription(e.target.value)} placeholder="Optional description" rows={3} className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent" />
          </div>
        </div>
      </Modal>

      {/* Start Execution Modal */}
      <Modal
        isOpen={showExecutionModal}
        onClose={() => { setShowExecutionModal(false); setExecutionTeam(null); }}
        title="Start Team Execution"
        maxWidth="md"
        icon={<Play />}
        footer={
          <div className="flex justify-end gap-3">
            <button onClick={() => { setShowExecutionModal(false); setExecutionTeam(null); }} className="btn-theme btn-theme-secondary">Cancel</button>
            <button onClick={handleStartExecution} disabled={!executionObjective.trim()} className="btn-theme btn-theme-primary">Start</button>
          </div>
        }
      >
        <div className="space-y-4 p-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Team</label>
            <p className="text-sm text-theme-secondary">{executionTeam?.name || 'No team selected'}</p>
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Objective</label>
            <textarea value={executionObjective} onChange={(e) => setExecutionObjective(e.target.value)} placeholder="Describe the objective for this execution..." rows={4} className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-accent" />
          </div>
        </div>
      </Modal>

      {ConfirmationDialog}
    </PageContainer>
  );
};

export default TeamsPage;
