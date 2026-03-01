import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import type { VolumeFormData } from '../types';

interface VolumeFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (data: VolumeFormData) => void;
  isLoading?: boolean;
}

export const VolumeFormModal: React.FC<VolumeFormModalProps> = ({
  isOpen,
  onClose,
  onSubmit,
  isLoading = false,
}) => {
  const [name, setName] = useState('');
  const [driver, setDriver] = useState('local');
  const [labelsText, setLabelsText] = useState('');

  const parseLabels = (text: string): Record<string, string> => {
    const result: Record<string, string> = {};
    text.split('\n').filter(Boolean).forEach((line) => {
      const idx = line.indexOf('=');
      if (idx > 0) {
        result[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
      }
    });
    return result;
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSubmit({
      name,
      driver,
      ...(labelsText && { labels: parseLabels(labelsText) }),
    });
  };

  const handleClose = () => {
    setName('');
    setDriver('local');
    setLabelsText('');
    onClose();
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Create Volume"
      size="lg"
      footer={
        <>
          <button
            onClick={handleClose}
            className="px-4 py-2 text-sm font-medium text-theme-secondary bg-theme-surface border border-theme rounded-lg hover:bg-theme-surface-hover transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleSubmit}
            disabled={!name || isLoading}
            className="px-4 py-2 text-sm font-medium text-white bg-theme-interactive-primary rounded-lg hover:bg-theme-interactive-primary-hover transition-colors disabled:opacity-50"
          >
            {isLoading ? 'Creating...' : 'Create Volume'}
          </button>
        </>
      }
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">Name *</label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="my-volume"
            className="input-theme w-full text-sm"
            required
          />
        </div>

        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">Driver</label>
          <select
            value={driver}
            onChange={(e) => setDriver(e.target.value)}
            className="input-theme w-full text-sm"
          >
            <option value="local">Local</option>
          </select>
        </div>

        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">
            Labels <span className="text-theme-tertiary">(KEY=VALUE, one per line)</span>
          </label>
          <textarea
            value={labelsText}
            onChange={(e) => setLabelsText(e.target.value)}
            placeholder={"app=myapp\nbackup=true"}
            rows={2}
            className="input-theme w-full text-sm font-mono"
          />
        </div>
      </form>
    </Modal>
  );
};
