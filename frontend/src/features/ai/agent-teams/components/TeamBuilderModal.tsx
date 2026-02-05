// Team Builder Modal - Create or edit agent teams
import React, { useState, useEffect } from 'react';
import Modal from '@/shared/components/ui/Modal';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { AgentTeam, CreateTeamParams, UpdateTeamParams } from '../services/agentTeamsApi';
import { CompositionHealthBanner } from './CompositionHealthBanner';
import { RoleProfileSelector } from './RoleProfileSelector';
import { ReviewConfigSection, ReviewConfig } from './ReviewConfigSection';
import type { RoleProfile } from '@/shared/services/ai/TeamsApiService';

interface TeamBuilderModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: (params: CreateTeamParams | UpdateTeamParams) => Promise<void>;
  team?: AgentTeam | null;
}

const DEFAULT_REVIEW_CONFIG: ReviewConfig = {
  auto_review_enabled: false,
  review_mode: 'blocking',
  review_task_types: ['execution'],
  max_revisions: 3,
  reviewer_role_type: 'reviewer',
  quality_threshold: 0.7,
};

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
  const [reviewConfig, setReviewConfig] = useState<ReviewConfig>(DEFAULT_REVIEW_CONFIG);
  const [selectedProfile, setSelectedProfile] = useState<RoleProfile | null>(null);

  useEffect(() => {
    if (team) {
      setFormData({
        name: team.name,
        description: team.description,
        team_type: team.team_type,
        coordination_strategy: team.coordination_strategy,
        status: team.status
      });
      // Load review config from team if editing
      if (team.team_config && typeof team.team_config === 'object' && 'review_config' in team.team_config) {
        setReviewConfig(team.team_config.review_config as ReviewConfig);
      }
    } else {
      setFormData({
        name: '',
        description: '',
        team_type: 'hierarchical',
        coordination_strategy: 'manager_worker',
        status: 'active'
      });
      setReviewConfig(DEFAULT_REVIEW_CONFIG);
    }
  }, [team, isOpen]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    setIsSubmitting(true);
    try {
      const saveData = {
        ...formData,
        team_config: {
          ...(formData.team_config || {}),
          review_config: reviewConfig
        }
      };
      await onSave(saveData);
      onClose();
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleChange = (field: keyof CreateTeamParams, value: string | undefined) => {
    if (value !== undefined) {
      setFormData(prev => ({ ...prev, [field]: value }));
    }
  };

  const handleProfileSelect = (profile: RoleProfile) => {
    setSelectedProfile(profile);
  };

  const handleApplyProfile = (profile: RoleProfile) => {
    setFormData(prev => ({
      ...prev,
      team_config: {
        ...(prev.team_config || {}),
        applied_profile: {
          id: profile.id,
          name: profile.name,
          role_type: profile.role_type
        }
      }
    }));
  };

  const handleCustomizeProfile = (profile: RoleProfile) => {
    setSelectedProfile(profile);
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
            className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-primary"
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
            onChange={(value) => handleChange('team_type', value as CreateTeamParams['team_type'])}
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
            onChange={(value) => handleChange('coordination_strategy', value as CreateTeamParams['coordination_strategy'])}
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
            onChange={(value) => handleChange('status', (value || 'active') as CreateTeamParams['status'])}
            options={statusOptions}
          />
        </div>

        {/* Composition Health Banner - shown when editing an existing team */}
        {team?.id && (
          <CompositionHealthBanner teamId={team.id} />
        )}

        {/* Role Profile Selector */}
        <RoleProfileSelector
          onProfileSelect={handleProfileSelect}
          onApplyProfile={handleApplyProfile}
          onCustomize={handleCustomizeProfile}
        />

        {/* Review Configuration */}
        <ReviewConfigSection
          config={reviewConfig}
          onChange={setReviewConfig}
        />

        {/* Actions */}
        <div className="flex justify-end gap-3 pt-4 border-t border-theme">
          <button
            type="button"
            onClick={onClose}
            className="btn-theme btn-theme-secondary btn-theme-md"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={isSubmitting || !formData.name}
            className="btn-theme btn-theme-primary btn-theme-md"
          >
            {isSubmitting ? 'Saving...' : team ? 'Update Team' : 'Create Team'}
          </button>
        </div>
      </form>
    </Modal>
  );
};
