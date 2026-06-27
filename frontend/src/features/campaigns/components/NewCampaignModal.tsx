import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Select } from '@/shared/components/ui/Select';
import type { CreateCampaignParams, DecisionAuthority } from '../types/campaign';
import { DECISION_AUTHORITY_OPTIONS } from '../constants/campaign';

interface NewCampaignModalProps {
  isOpen: boolean;
  onClose: () => void;
  onCreate: (data: CreateCampaignParams) => Promise<void>;
}

export const NewCampaignModal: React.FC<NewCampaignModalProps> = ({ isOpen, onClose, onCreate }) => {
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [decisionAuthority, setDecisionAuthority] = useState<DecisionAuthority>('trusted');
  const [maxFailed, setMaxFailed] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reset = () => {
    setName('');
    setDescription('');
    setDecisionAuthority('trusted');
    setMaxFailed('');
    setError(null);
  };

  const handleClose = () => {
    if (submitting) return;
    reset();
    onClose();
  };

  const handleSubmit = async () => {
    if (!name.trim()) {
      setError('Name is required.');
      return;
    }
    setSubmitting(true);
    setError(null);
    try {
      const stopConditions: Record<string, unknown> = {};
      if (maxFailed.trim()) stopConditions.max_failed = Number(maxFailed);
      await onCreate({
        name: name.trim(),
        description: description.trim() || undefined,
        decision_authority: decisionAuthority,
        stop_conditions: stopConditions,
      });
      reset();
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to start campaign.');
    } finally {
      setSubmitting(false);
    }
  };

  const authorityDescription = DECISION_AUTHORITY_OPTIONS.find(o => o.value === decisionAuthority)?.description;

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Start Improvement Campaign"
      subtitle="An agent drives a backlog of improvements to verified, committed outcomes."
      size="lg"
      footer={
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={handleClose} disabled={submitting}>Cancel</Button>
          <Button variant="primary" onClick={handleSubmit} loading={submitting}>Start Campaign</Button>
        </div>
      }
    >
      <div className="space-y-4">
        {error && (
          <div className="rounded-md border border-theme-error-border bg-theme-error-bg px-3 py-2 text-sm text-theme-error-fg">
            {error}
          </div>
        )}

        <Input
          label="Name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="e.g. Harden billing edge cases"
          autoFocus
        />

        <Textarea
          label="Scope & intent (optional)"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          placeholder="What should this campaign focus on? Posture, ordering, and any constraints."
          rows={3}
        />

        <div>
          <Select
            label="Decision authority"
            value={decisionAuthority}
            onChange={(value) => setDecisionAuthority(value as DecisionAuthority)}
            options={DECISION_AUTHORITY_OPTIONS.map(o => ({ value: o.value, label: o.label }))}
          />
          {authorityDescription && (
            <p className="mt-1 text-xs text-theme-tertiary">{authorityDescription}</p>
          )}
        </div>

        <Input
          label="Stop after N failed tasks (optional)"
          type="number"
          value={maxFailed}
          onChange={(e) => setMaxFailed(e.target.value)}
          placeholder="Leave blank for no failure cap"
        />
      </div>
    </Modal>
  );
};
