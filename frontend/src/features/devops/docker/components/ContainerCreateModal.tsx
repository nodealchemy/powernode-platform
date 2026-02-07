import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import type { ContainerCreateData } from '../types';

interface ContainerCreateModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (data: ContainerCreateData) => void;
  isLoading?: boolean;
}

export const ContainerCreateModal: React.FC<ContainerCreateModalProps> = ({
  isOpen,
  onClose,
  onSubmit,
  isLoading = false,
}) => {
  const [name, setName] = useState('');
  const [image, setImage] = useState('');
  const [command, setCommand] = useState('');
  const [envText, setEnvText] = useState('');
  const [portsText, setPortsText] = useState('');
  const [restartPolicy, setRestartPolicy] = useState('no');
  const [labelsText, setLabelsText] = useState('');

  const parseKeyValue = (text: string): Record<string, string> => {
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
    const data: ContainerCreateData = {
      name,
      image,
      ...(command && { command }),
      ...(envText && { environment: parseKeyValue(envText) }),
      ...(portsText && { ports: parseKeyValue(portsText) }),
      restart_policy: restartPolicy,
      ...(labelsText && { labels: parseKeyValue(labelsText) }),
    };
    onSubmit(data);
  };

  const handleClose = () => {
    setName('');
    setImage('');
    setCommand('');
    setEnvText('');
    setPortsText('');
    setRestartPolicy('no');
    setLabelsText('');
    onClose();
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Create Container"
      size="2xl"
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
            disabled={!name || !image || isLoading}
            className="px-4 py-2 text-sm font-medium text-white bg-theme-interactive-primary rounded-lg hover:bg-theme-interactive-primary-hover transition-colors disabled:opacity-50"
          >
            {isLoading ? 'Creating...' : 'Create'}
          </button>
        </>
      }
    >
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-xs font-medium text-theme-secondary mb-1">Name *</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="my-container"
              className="input-theme w-full text-sm"
              required
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-theme-secondary mb-1">Image *</label>
            <input
              type="text"
              value={image}
              onChange={(e) => setImage(e.target.value)}
              placeholder="nginx:latest"
              className="input-theme w-full text-sm"
              required
            />
          </div>
        </div>

        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">Command</label>
          <input
            type="text"
            value={command}
            onChange={(e) => setCommand(e.target.value)}
            placeholder="/bin/sh -c 'echo hello'"
            className="input-theme w-full text-sm"
          />
        </div>

        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">
            Environment Variables <span className="text-theme-tertiary">(KEY=VALUE, one per line)</span>
          </label>
          <textarea
            value={envText}
            onChange={(e) => setEnvText(e.target.value)}
            placeholder={"NODE_ENV=production\nPORT=3000"}
            rows={3}
            className="input-theme w-full text-sm font-mono"
          />
        </div>

        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">
            Port Mappings <span className="text-theme-tertiary">(host=container, one per line)</span>
          </label>
          <textarea
            value={portsText}
            onChange={(e) => setPortsText(e.target.value)}
            placeholder={"8080=80\n8443=443"}
            rows={2}
            className="input-theme w-full text-sm font-mono"
          />
        </div>

        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">Restart Policy</label>
          <select
            value={restartPolicy}
            onChange={(e) => setRestartPolicy(e.target.value)}
            className="input-theme w-full text-sm"
          >
            <option value="no">No</option>
            <option value="always">Always</option>
            <option value="on-failure">On Failure</option>
            <option value="unless-stopped">Unless Stopped</option>
          </select>
        </div>

        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">
            Labels <span className="text-theme-tertiary">(KEY=VALUE, one per line)</span>
          </label>
          <textarea
            value={labelsText}
            onChange={(e) => setLabelsText(e.target.value)}
            placeholder={"app=myapp\nversion=1.0"}
            rows={2}
            className="input-theme w-full text-sm font-mono"
          />
        </div>
      </form>
    </Modal>
  );
};
