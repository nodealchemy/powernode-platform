import React, { useState } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';

interface ServiceScaleModalProps {
  isOpen: boolean;
  onClose: () => void;
  serviceName: string;
  currentReplicas: number;
  onScale: (replicas: number) => Promise<void>;
}

export const ServiceScaleModal: React.FC<ServiceScaleModalProps> = ({
  isOpen,
  onClose,
  serviceName,
  currentReplicas,
  onScale,
}) => {
  const [replicas, setReplicas] = useState(currentReplicas);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = async () => {
    setIsSubmitting(true);
    await onScale(replicas);
    setIsSubmitting(false);
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={`Scale ${serviceName}`} size="sm">
      <div className="p-4 space-y-4">
        <p className="text-sm text-theme-secondary">
          Current replicas: <span className="font-semibold text-theme-primary">{currentReplicas}</span>
        </p>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">Desired Replicas</label>
          <input
            type="range"
            min={0}
            max={20}
            value={replicas}
            onChange={(e) => setReplicas(parseInt(e.target.value, 10))}
            className="w-full"
          />
          <div className="flex items-center justify-between mt-2">
            <input
              type="number"
              min={0}
              max={100}
              value={replicas}
              onChange={(e) => setReplicas(Math.max(0, parseInt(e.target.value, 10) || 0))}
              className="input-theme w-20 text-center"
            />
            <span className="text-sm text-theme-tertiary">
              {replicas === 0 ? 'Service will be stopped' : `${replicas} replica(s)`}
            </span>
          </div>
        </div>

        <div className="flex justify-end gap-3 pt-4">
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button variant="primary" onClick={handleSubmit} loading={isSubmitting} disabled={replicas === currentReplicas}>
            Scale to {replicas}
          </Button>
        </div>
      </div>
    </Modal>
  );
};
