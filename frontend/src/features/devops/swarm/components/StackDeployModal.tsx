import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { StackComposeEditor } from './StackComposeEditor';

interface StackDeployModalProps {
  isOpen: boolean;
  onClose: () => void;
  onDeploy: (name: string, composeFile: string) => Promise<void>;
}

export const StackDeployModal: React.FC<StackDeployModalProps> = ({ isOpen, onClose, onDeploy }) => {
  const [name, setName] = useState('');
  const [composeFile, setComposeFile] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleDeploy = async () => {
    setIsSubmitting(true);
    await onDeploy(name, composeFile);
    setIsSubmitting(false);
    setName('');
    setComposeFile('');
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Deploy Stack" size="2xl">
      <div className="p-4 space-y-4">
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Stack Name</label>
          <input
            type="text"
            className="input-theme w-full"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="my-stack"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Docker Compose File</label>
          <StackComposeEditor value={composeFile} onChange={setComposeFile} />
        </div>

        <div className="flex justify-end gap-3 pt-4">
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button variant="primary" onClick={handleDeploy} loading={isSubmitting} disabled={!name || !composeFile}>
            Deploy
          </Button>
        </div>
      </div>
    </Modal>
  );
};
