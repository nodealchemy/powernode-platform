import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import type { SecretFormData } from '../types';

interface SecretFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (data: SecretFormData) => Promise<void>;
}

export const SecretFormModal: React.FC<SecretFormModalProps> = ({ isOpen, onClose, onSubmit }) => {
  const [name, setName] = useState('');
  const [data, setData] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = async () => {
    setIsSubmitting(true);
    await onSubmit({ name, data });
    setIsSubmitting(false);
    setName('');
    setData('');
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Create Secret" size="md">
      <div className="p-4 space-y-4">
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Secret Name</label>
          <input
            type="text"
            className="input-theme w-full"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="my-secret"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Secret Value</label>
          <textarea
            className="input-theme w-full min-h-[100px] font-mono text-sm"
            value={data}
            onChange={(e) => setData(e.target.value)}
            placeholder="Enter secret value..."
          />
          <p className="text-xs text-theme-tertiary mt-1">The secret value will be stored encrypted.</p>
        </div>
        <div className="flex justify-end gap-3 pt-4">
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button variant="primary" onClick={handleSubmit} loading={isSubmitting} disabled={!name || !data}>
            Create Secret
          </Button>
        </div>
      </div>
    </Modal>
  );
};
