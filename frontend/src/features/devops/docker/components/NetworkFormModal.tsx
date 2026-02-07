import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import type { NetworkFormData } from '../types';

interface NetworkFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (data: NetworkFormData) => void;
  isLoading?: boolean;
}

export const NetworkFormModal: React.FC<NetworkFormModalProps> = ({
  isOpen,
  onClose,
  onSubmit,
  isLoading = false,
}) => {
  const [name, setName] = useState('');
  const [driver, setDriver] = useState('bridge');
  const [internal, setInternal] = useState(false);
  const [attachable, setAttachable] = useState(false);
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
      internal,
      attachable,
      ...(labelsText && { labels: parseLabels(labelsText) }),
    });
  };

  const handleClose = () => {
    setName('');
    setDriver('bridge');
    setInternal(false);
    setAttachable(false);
    setLabelsText('');
    onClose();
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Create Network"
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
            {isLoading ? 'Creating...' : 'Create Network'}
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
            placeholder="my-network"
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
            <option value="bridge">Bridge</option>
            <option value="overlay">Overlay</option>
            <option value="host">Host</option>
            <option value="macvlan">Macvlan</option>
            <option value="none">None</option>
          </select>
        </div>

        <div className="flex items-center gap-6">
          <label className="flex items-center gap-2 text-sm text-theme-secondary cursor-pointer">
            <input
              type="checkbox"
              checked={internal}
              onChange={(e) => setInternal(e.target.checked)}
              className="rounded border-theme text-theme-interactive-primary"
            />
            Internal
          </label>
          <label className="flex items-center gap-2 text-sm text-theme-secondary cursor-pointer">
            <input
              type="checkbox"
              checked={attachable}
              onChange={(e) => setAttachable(e.target.checked)}
              className="rounded border-theme text-theme-interactive-primary"
            />
            Attachable
          </label>
        </div>

        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">
            Labels <span className="text-theme-tertiary">(KEY=VALUE, one per line)</span>
          </label>
          <textarea
            value={labelsText}
            onChange={(e) => setLabelsText(e.target.value)}
            placeholder={"app=myapp\nenvironment=production"}
            rows={2}
            className="input-theme w-full text-sm font-mono"
          />
        </div>
      </form>
    </Modal>
  );
};
