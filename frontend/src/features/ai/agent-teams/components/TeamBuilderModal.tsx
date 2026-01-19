// Team Builder Modal - Create or edit agent teams
import React, { useState, useEffect } from 'react';
import Modal from '@/shared/components/ui/Modal';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { AgentTeam, CreateTeamParams, UpdateTeamParams } from '../services/agentTeamsApi';

interface TeamBuilderModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: (params: CreateTeamParams | UpdateTeamParams) => Promise<void>;
  team?: AgentTeam | null;
}

export const TeamBuilderModal: React.FC<TeamBuilderModalProps> = ({
  isOpen,
  onClose,
  onSave,
  team
}) => {
  const [formData, setFormData] = useState<CreateTeamParams>({
    name: '',
    description: '',
    team_type: 'hierarchical',
    coordination_strategy: 'manager_worker',
    status: 'active'
  });
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    if (team) {
      setFormData({
        name: team.name,
        description: team.description,
        team_type: team.team_type,
        coordination_strategy: team.coordination_strategy,
        status: team.status
      });
    } else {
      setFormData({
        name: '',
        description: '',
        team_type: 'hierarchical',
        coordination_strategy: 'manager_worker',
        status: 'active'
      });
    }
  }, [team, isOpen]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    setIsSubmitting(true);
    try {
      await onSave(formData);
      onClose();
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleChange = (field: keyof CreateTeamParams, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }));
  };

  const teamTypeOptions = [
    { value: 'hierarchical', label: 'Hierarchical - Manager-led team structure' },
    { value: 'mesh', label: 'Mesh - Peer-to-peer collaboration' },
    { value: 'sequential', label: 'Sequential - Step-by-step execution' },
    { value: 'parallel', label: 'Parallel - Concurrent agent execution' }
  ];

  const coordinationOptions = [
    { value: 'manager_worker', label: 'Manager-Worker - Central coordination' },
    { value: 'peer_to_peer', label: 'Peer-to-Peer - Equal collaboration' },
    { value: 'hybrid', label: 'Hybrid - Mixed coordination' }
  ];

  const statusOptions = [
    { value: 'active', label: 'Active' },
    { value: 'inactive', label: 'Inactive' },
    { value: 'archived', label: 'Archived' }
  ];

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={team ? 'Edit Agent Team' : 'Create Agent Team'}
      maxWidth="lg"
    >
      <form onSubmit={handleSubmit} className="space-y-6">
        {/* Team Name */}
        <div>
          <label htmlFor="name" className="block text-sm font-medium text-theme-primary mb-2">
            Team Name *
          </label>
          <Input
            id="name"
            type="text"
            value={formData.name}
            onChange={(e) => handleChange('name', e.target.value)}
            placeholder="e.g., Content Creation Crew"
            required
          />
        </div>

        {/* Description */}
        <div>
          <label htmlFor="description" className="block text-sm font-medium text-theme-primary mb-2">
            Description
          </label>
          <textarea
            id="description"
            value={formData.description}
            onChange={(e) => handleChange('description', e.target.value)}
            placeholder="Describe the team's purpose and goals..."
            rows={3}
            className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
        </div>

        {/* Team Type */}
        <div>
          <label htmlFor="team_type" className="block text-sm font-medium text-theme-primary mb-2">
            Team Type *
          </label>
          <Select
            id="team_type"
            value={formData.team_type}
            onChange={(value) => handleChange('team_type', value as any)}
            options={teamTypeOptions}
            required
          />
        </div>

        {/* Coordination Strategy */}
        <div>
          <label htmlFor="coordination_strategy" className="block text-sm font-medium text-theme-primary mb-2">
            Coordination Strategy *
          </label>
          <Select
            id="coordination_strategy"
            value={formData.coordination_strategy}
            onChange={(value) => handleChange('coordination_strategy', value as any)}
            options={coordinationOptions}
            required
          />
        </div>

        {/* Status */}
        <div>
          <label htmlFor="status" className="block text-sm font-medium text-theme-primary mb-2">
            Status
          </label>
          <Select
            id="status"
            value={formData.status || 'active'}
            onChange={(value) => handleChange('status', value as any)}
            options={statusOptions}
          />
        </div>

        {/* Actions */}
        <div className="flex justify-end gap-3 pt-4 border-t border-theme">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-sm font-medium text-theme-primary bg-theme-accent rounded-md hover:bg-theme-hover transition-colors"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={isSubmitting || !formData.name}
            className="px-4 py-2 text-sm font-medium text-white bg-theme-primary rounded-md hover:opacity-90 disabled:opacity-50 disabled:cursor-not-allowed transition-opacity"
          >
            {isSubmitting ? 'Saving...' : team ? 'Update Team' : 'Create Team'}
          </button>
        </div>
      </form>
    </Modal>
  );
};

