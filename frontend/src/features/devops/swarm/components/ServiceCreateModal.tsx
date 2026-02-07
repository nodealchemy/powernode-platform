import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import type { ServiceFormData } from '../types';

interface ServiceCreateModalProps {
  isOpen: boolean;
  onClose: () => void;
  onCreate: (data: ServiceFormData) => Promise<unknown>;
}

const defaultFormData: ServiceFormData = {
  service_name: '',
  image: '',
  mode: 'replicated',
  replicas: 1,
  ports: [],
  environment: [],
  constraints: [],
};

export const ServiceCreateModal: React.FC<ServiceCreateModalProps> = ({
  isOpen,
  onClose,
  onCreate,
}) => {
  const [formData, setFormData] = useState<ServiceFormData>({ ...defaultFormData });
  const [portInput, setPortInput] = useState({ published: '', target: '' });
  const [envInput, setEnvInput] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  const resetForm = () => {
    setFormData({ ...defaultFormData });
    setPortInput({ published: '', target: '' });
    setEnvInput('');
  };

  const handleSubmit = async () => {
    setIsSubmitting(true);
    const result = await onCreate(formData);
    setIsSubmitting(false);
    if (result) {
      resetForm();
      onClose();
    }
  };

  const addPort = () => {
    if (!portInput.published || !portInput.target) return;
    setFormData((prev) => ({
      ...prev,
      ports: [...(prev.ports || []), { published: parseInt(portInput.published, 10), target: parseInt(portInput.target, 10), protocol: 'tcp' }],
    }));
    setPortInput({ published: '', target: '' });
  };

  const removePort = (index: number) => {
    setFormData((prev) => ({
      ...prev,
      ports: (prev.ports || []).filter((_, i) => i !== index),
    }));
  };

  const addEnv = () => {
    if (!envInput || !envInput.includes('=')) return;
    setFormData((prev) => ({
      ...prev,
      environment: [...(prev.environment || []), envInput],
    }));
    setEnvInput('');
  };

  const removeEnv = (index: number) => {
    setFormData((prev) => ({
      ...prev,
      environment: (prev.environment || []).filter((_, i) => i !== index),
    }));
  };

  return (
    <Modal isOpen={isOpen} onClose={() => { resetForm(); onClose(); }} title="Create Service" size="lg">
      <div className="p-4 space-y-4 max-h-[70vh] overflow-y-auto">
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Service Name</label>
          <input
            type="text"
            className="input-theme w-full"
            value={formData.service_name}
            onChange={(e) => setFormData((prev) => ({ ...prev, service_name: e.target.value }))}
            placeholder="my-service"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Image</label>
          <input
            type="text"
            className="input-theme w-full"
            value={formData.image}
            onChange={(e) => setFormData((prev) => ({ ...prev, image: e.target.value }))}
            placeholder="nginx:latest"
          />
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Mode</label>
            <select
              className="input-theme w-full"
              value={formData.mode}
              onChange={(e) => setFormData((prev) => ({ ...prev, mode: e.target.value as 'replicated' | 'global' }))}
            >
              <option value="replicated">Replicated</option>
              <option value="global">Global</option>
            </select>
          </div>

          {formData.mode === 'replicated' && (
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-1">Replicas</label>
              <input
                type="number"
                className="input-theme w-full"
                min={1}
                value={formData.replicas || 1}
                onChange={(e) => setFormData((prev) => ({ ...prev, replicas: Math.max(1, parseInt(e.target.value, 10) || 1) }))}
              />
            </div>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Ports</label>
          <div className="flex gap-2 mb-2">
            <input
              type="number"
              className="input-theme w-24"
              placeholder="Published"
              value={portInput.published}
              onChange={(e) => setPortInput((prev) => ({ ...prev, published: e.target.value }))}
            />
            <span className="text-theme-secondary self-center">:</span>
            <input
              type="number"
              className="input-theme w-24"
              placeholder="Target"
              value={portInput.target}
              onChange={(e) => setPortInput((prev) => ({ ...prev, target: e.target.value }))}
            />
            <Button size="sm" variant="secondary" onClick={addPort}>Add</Button>
          </div>
          {(formData.ports || []).map((port, i) => (
            <div key={i} className="flex items-center gap-2 text-sm text-theme-secondary mb-1">
              <span>{port.published}:{port.target}/tcp</span>
              <button className="text-theme-error hover:underline text-xs" onClick={() => removePort(i)}>remove</button>
            </div>
          ))}
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Environment Variables</label>
          <div className="flex gap-2 mb-2">
            <input
              type="text"
              className="input-theme flex-1"
              placeholder="KEY=value"
              value={envInput}
              onChange={(e) => setEnvInput(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addEnv(); } }}
            />
            <Button size="sm" variant="secondary" onClick={addEnv}>Add</Button>
          </div>
          {(formData.environment || []).map((env, i) => (
            <div key={i} className="flex items-center gap-2 text-sm text-theme-secondary mb-1">
              <span className="font-mono text-xs">{env}</span>
              <button className="text-theme-error hover:underline text-xs" onClick={() => removeEnv(i)}>remove</button>
            </div>
          ))}
        </div>

        <div className="flex justify-end gap-3 pt-4">
          <Button variant="secondary" onClick={() => { resetForm(); onClose(); }}>Cancel</Button>
          <Button
            variant="primary"
            onClick={handleSubmit}
            loading={isSubmitting}
            disabled={!formData.service_name || !formData.image}
          >
            Create Service
          </Button>
        </div>
      </div>
    </Modal>
  );
};
