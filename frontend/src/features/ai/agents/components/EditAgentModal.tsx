import React from 'react';
import { Brain, Trash2 } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { useEditAgentForm, AGENT_TYPES } from './useEditAgentForm';
import { AgentStatsSection } from './AgentStatsSection';
import { AgentFormFields } from './AgentFormFields';
import { AgentSkillsSection } from './AgentSkillsSection';
import { AgentDangerZone } from './AgentDangerZone';
import type { AiAgent } from '@/shared/types/ai';

interface EditAgentModalProps {
  isOpen: boolean;
  onClose: () => void;
  agent: AiAgent | null;
  onAgentUpdated?: (agent: AiAgent) => void;
  onAgentDeleted?: (agentId: string) => void;
}

export const EditAgentModal: React.FC<EditAgentModalProps> = ({
  isOpen,
  onClose,
  agent,
  onAgentUpdated,
  onAgentDeleted
}) => {
  const {
    form,
    selectedProvider,
    loadingProviders,
    agentStats,
    showDeleteConfirm,
    setShowDeleteConfirm,
    deleting,
    assignedSkills,
    availableSkills,
    loadingSkills,
    handleAssignSkill,
    handleRemoveSkill,
    handleDeleteAgent,
    getProviderOptions,
    getModelOptions,
    handleClose,
  } = useEditAgentForm({ agent, isOpen, onAgentUpdated, onAgentDeleted, onClose });

  const modalFooter = (
    <>
      <div className="flex items-center gap-2">
        <Button
          variant="danger"
          size="sm"
          onClick={() => setShowDeleteConfirm(true)}
          disabled={form.isSubmitting || deleting}
        >
          <Trash2 className="h-4 w-4 mr-1" />
          Delete
        </Button>
      </div>
      <div className="flex items-center gap-2">
        <Button
          variant="ghost"
          onClick={handleClose}
          disabled={form.isSubmitting || deleting}
        >
          Cancel
        </Button>
        <Button
          onClick={form.handleSubmit}
          loading={form.isSubmitting}
          disabled={!form.isValid || deleting}
        >
          Update Agent
        </Button>
      </div>
    </>
  );

  if (!agent) return null;

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title={`Edit ${agent.name}`}
      subtitle="Modify configuration and settings for this AI agent"
      icon={<Brain />}
      maxWidth="3xl"
      footer={modalFooter}
    >
      <div className="space-y-6">
        {agentStats && (
          <AgentStatsSection agent={agent} agentStats={agentStats} />
        )}

        <AgentFormFields
          form={form}
          agentTypes={AGENT_TYPES}
          providerOptions={getProviderOptions()}
          modelOptions={getModelOptions()}
          loadingProviders={loadingProviders}
          selectedProvider={selectedProvider}
        />

        <AgentSkillsSection
          assignedSkills={assignedSkills}
          availableSkills={availableSkills}
          loadingSkills={loadingSkills}
          onAssignSkill={handleAssignSkill}
          onRemoveSkill={handleRemoveSkill}
        />

        <AgentDangerZone
          agentName={agent.name}
          showDeleteConfirm={showDeleteConfirm}
          deleting={deleting}
          onConfirmDelete={handleDeleteAgent}
          onCancelDelete={() => setShowDeleteConfirm(false)}
        />
      </div>
    </Modal>
  );
};
