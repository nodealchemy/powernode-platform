import React, { useEffect, useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Button } from '@/shared/components/ui/Button';

const POLICY_TYPES = [
  'data_access', 'model_usage', 'output_filter', 'rate_limit',
  'cost_limit', 'approval_required', 'retention', 'audit', 'custom',
] as const;

const ENFORCEMENT_LEVELS = ['log', 'warn', 'block', 'require_approval'] as const;

export interface CreatePolicyFormData {
  name: string;
  policy_type: typeof POLICY_TYPES[number];
  enforcement_level: typeof ENFORCEMENT_LEVELS[number];
  category: string;
  description: string;
}

const emptyCreatePolicyForm: CreatePolicyFormData = {
  name: '',
  policy_type: 'data_access',
  enforcement_level: 'log',
  category: '',
  description: '',
};

export const CreatePolicyModal: React.FC<{
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (data: CreatePolicyFormData) => void;
  submitting: boolean;
}> = ({ isOpen, onClose, onSubmit, submitting }) => {
  const [form, setForm] = useState<CreatePolicyFormData>(emptyCreatePolicyForm);

  useEffect(() => {
    if (isOpen) setForm(emptyCreatePolicyForm);
  }, [isOpen]);

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Create Compliance Policy" maxWidth="lg">
      <div className="space-y-4">
        <Input
          label="Name"
          type="text"
          value={form.name}
          onChange={(e) => setForm((prev) => ({ ...prev, name: e.target.value }))}
          placeholder="e.g., PII Access Restriction"
        />
        <div className="grid grid-cols-2 gap-4">
          <Select
            label="Policy Type"
            value={form.policy_type}
            onChange={(value) => setForm((prev) => ({ ...prev, policy_type: value as CreatePolicyFormData['policy_type'] }))}
            options={POLICY_TYPES.map((t) => ({ value: t, label: t.replace(/_/g, ' ') }))}
          />
          <Select
            label="Enforcement"
            value={form.enforcement_level}
            onChange={(value) => setForm((prev) => ({ ...prev, enforcement_level: value as CreatePolicyFormData['enforcement_level'] }))}
            options={ENFORCEMENT_LEVELS.map((l) => ({ value: l, label: l.replace(/_/g, ' ') }))}
          />
        </div>
        <Input
          label="Category (optional)"
          type="text"
          value={form.category}
          onChange={(e) => setForm((prev) => ({ ...prev, category: e.target.value }))}
        />
        <Textarea
          label="Description (optional)"
          value={form.description}
          onChange={(e) => setForm((prev) => ({ ...prev, description: e.target.value }))}
          rows={3}
        />
        <div className="flex justify-end gap-3 pt-2">
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button
            variant="primary"
            disabled={!form.name.trim() || submitting}
            loading={submitting}
            onClick={() => onSubmit(form)}
          >
            Create Policy
          </Button>
        </div>
      </div>
    </Modal>
  );
};
