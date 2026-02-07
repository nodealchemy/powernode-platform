import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import type { NetworkFormData } from '../types';

interface NetworkFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (data: NetworkFormData) => Promise<void>;
}

export const NetworkFormModal: React.FC<NetworkFormModalProps> = ({ isOpen, onClose, onSubmit }) => {
  const [name, setName] = useState('');
  const [driver, setDriver] = useState('overlay');
  const [internal, setInternal] = useState(false);
  const [attachable, setAttachable] = useState(true);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = async () => {
    setIsSubmitting(true);
    await onSubmit({ name, driver, internal, attachable });
    setIsSubmitting(false);
    setName('');
    setDriver('overlay');
    setInternal(false);
    setAttachable(true);
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Create Network" size="md">
      <div className="p-4 space-y-4">
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Network Name</label>
          <input
            type="text"
            className="input-theme w-full"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="my-network"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Driver</label>
          <select className="input-theme w-full" value={driver} onChange={(e) => setDriver(e.target.value)}>
            <option value="overlay">Overlay</option>
            <option value="bridge">Bridge</option>
            <option value="macvlan">Macvlan</option>
          </select>
        </div>
        <div className="flex items-center gap-6">
          <label className="flex items-center gap-2 text-sm text-theme-secondary cursor-pointer">
            <input type="checkbox" checked={internal} onChange={(e) => setInternal(e.target.checked)} className="rounded" />
            Internal only
          </label>
          <label className="flex items-center gap-2 text-sm text-theme-secondary cursor-pointer">
            <input type="checkbox" checked={attachable} onChange={(e) => setAttachable(e.target.checked)} className="rounded" />
            Attachable
          </label>
        </div>
        <div className="flex justify-end gap-3 pt-4">
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button variant="primary" onClick={handleSubmit} loading={isSubmitting} disabled={!name}>
            Create Network
          </Button>
        </div>
      </div>
    </Modal>
  );
};
