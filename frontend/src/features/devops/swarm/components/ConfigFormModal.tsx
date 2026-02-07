import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import type { ConfigFormData } from '../types';

interface ConfigFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (data: ConfigFormData) => Promise<void>;
}

export const ConfigFormModal: React.FC<ConfigFormModalProps> = ({ isOpen, onClose, onSubmit }) => {
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
    <Modal isOpen={isOpen} onClose={onClose} title="Create Config" size="md">
      <div className="p-4 space-y-4">
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Config Name</label>
          <input
            type="text"
            className="input-theme w-full"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="my-config"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Config Data</label>
          <textarea
            className="input-theme w-full min-h-[100px] font-mono text-sm"
            value={data}
            onChange={(e) => setData(e.target.value)}
            placeholder="Enter config data (plain text or JSON)..."
          />
        </div>
        <div className="flex justify-end gap-3 pt-4">
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button variant="primary" onClick={handleSubmit} loading={isSubmitting} disabled={!name || !data}>
            Create Config
          </Button>
        </div>
      </div>
    </Modal>
  );
};
