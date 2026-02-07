import React, { useState } from 'react';
import { RotateCcw } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';

interface ServiceRollbackModalProps {
  isOpen: boolean;
  onClose: () => void;
  serviceName: string;
  onRollback: () => Promise<void>;
}

export const ServiceRollbackModal: React.FC<ServiceRollbackModalProps> = ({
  isOpen,
  onClose,
  serviceName,
  onRollback,
}) => {
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleRollback = async () => {
    setIsSubmitting(true);
    await onRollback();
    setIsSubmitting(false);
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Rollback Service" size="sm">
      <div className="p-4 space-y-4">
        <div className="flex items-center gap-3 p-3 rounded-lg bg-theme-warning bg-opacity-10">
          <RotateCcw className="w-5 h-5 text-theme-warning flex-shrink-0" />
          <p className="text-sm text-theme-primary">
            Are you sure you want to rollback <span className="font-semibold">{serviceName}</span> to its previous version?
          </p>
        </div>

        <p className="text-sm text-theme-secondary">
          This will revert the service to its previous configuration and image. Running tasks will be replaced.
        </p>

        <div className="flex justify-end gap-3 pt-4">
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button variant="warning" onClick={handleRollback} loading={isSubmitting}>
            <RotateCcw className="w-4 h-4 mr-2" /> Rollback
          </Button>
        </div>
      </div>
    </Modal>
  );
};
