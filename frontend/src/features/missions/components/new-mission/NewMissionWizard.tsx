import React, { useState } from 'react';
import { Rocket } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { StepTypeAndRepo } from './StepTypeAndRepo';
import { StepTeamConfig } from './StepTeamConfig';
import { StepObjective } from './StepObjective';
import type { CreateMissionParams, MissionType } from '../../types/mission';

interface NewMissionWizardProps {
  isOpen: boolean;
  onClose: () => void;
  onCreate: (data: CreateMissionParams) => Promise<void>;
}

const STEPS = ['Type & Repository', 'Team (Optional)', 'Objective'] as const;

export const NewMissionWizard: React.FC<NewMissionWizardProps> = ({ isOpen, onClose, onCreate }) => {
  const [step, setStep] = useState(0);
  const [submitting, setSubmitting] = useState(false);

  // Wizard state
  const [name, setName] = useState('');
  const [missionType, setMissionType] = useState<MissionType>('development');
  const [repositoryId, setRepositoryId] = useState<string>('');
  const [baseBranch, setBaseBranch] = useState('main');
  const [teamId, setTeamId] = useState<string>('');
  const [objective, setObjective] = useState('');
  const [description, setDescription] = useState('');

  const canProceed = (): boolean => {
    switch (step) {
      case 0: return name.trim().length > 0;
      case 1: return true; // team is optional
      case 2: return true; // objective is optional
      default: return false;
    }
  };

  const handleSubmit = async () => {
    setSubmitting(true);
    try {
      await onCreate({
        name: name.trim(),
        description: description.trim() || undefined,
        mission_type: missionType,
        objective: objective.trim() || undefined,
        repository_id: repositoryId || undefined,
        team_id: teamId || undefined,
        base_branch: baseBranch || undefined,
      });
    } finally {
      setSubmitting(false);
    }
  };

  const handleClose = () => {
    setStep(0);
    setName('');
    setMissionType('development');
    setRepositoryId('');
    setBaseBranch('main');
    setTeamId('');
    setObjective('');
    setDescription('');
    onClose();
  };

  const footer = (
    <>
      <Button
        variant="ghost"
        onClick={() => step > 0 ? setStep(step - 1) : handleClose()}
        disabled={submitting}
      >
        {step > 0 ? 'Back' : 'Cancel'}
      </Button>
      {step < STEPS.length - 1 ? (
        <Button
          onClick={() => setStep(step + 1)}
          disabled={!canProceed()}
        >
          Next
        </Button>
      ) : (
        <Button
          onClick={handleSubmit}
          disabled={!canProceed() || submitting}
          loading={submitting}
        >
          Create Mission
        </Button>
      )}
    </>
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="New Mission"
      subtitle={`Step ${step + 1} of ${STEPS.length}: ${STEPS[step]}`}
      icon={<Rocket />}
      maxWidth="lg"
      footer={footer}
    >
      {/* Step indicators */}
      <div className="flex items-center gap-2 mb-5">
        {STEPS.map((_, i) => (
          <div
            key={i}
            className={`h-1 flex-1 rounded-full ${
              i <= step ? 'bg-theme-interactive-primary' : 'bg-theme-surface-hover'
            }`}
          />
        ))}
      </div>

      {/* Step content */}
      {step === 0 && (
        <StepTypeAndRepo
          name={name}
          onNameChange={setName}
          missionType={missionType}
          onMissionTypeChange={setMissionType}
          repositoryId={repositoryId}
          onRepositoryIdChange={setRepositoryId}
          baseBranch={baseBranch}
          onBaseBranchChange={setBaseBranch}
        />
      )}
      {step === 1 && (
        <StepTeamConfig
          teamId={teamId}
          onTeamIdChange={setTeamId}
        />
      )}
      {step === 2 && (
        <StepObjective
          objective={objective}
          onObjectiveChange={setObjective}
          description={description}
          onDescriptionChange={setDescription}
        />
      )}
    </Modal>
  );
};
