import React from 'react';
import { AlertCircle, Loader2 } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import type { DeleteConfirmationModalProps } from './types';

export const DeleteConfirmationModal: React.FC<DeleteConfirmationModalProps> = ({
  isOpen,
  onClose,
  onConfirm,
  isDeleting,
  runId
}) => {
  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Delete Execution Run"
      size="sm"
    >
      <div className="space-y-4">
        <div className="flex items-start gap-3">
          <AlertCircle className="h-5 w-5 text-theme-warning mt-0.5 flex-shrink-0" />
          <div>
            <p className="text-sm text-theme-primary">
              Are you sure you want to delete this execution run?
            </p>
            <p className="text-xs text-theme-muted mt-1">
              Run ID: {runId}
            </p>
            <p className="text-xs text-theme-warning mt-2">
              This action cannot be undone. All execution logs and data will be permanently removed.
            </p>
          </div>
        </div>

        <div className="flex justify-end gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={onClose}
            disabled={isDeleting}
          >
            Cancel
          </Button>
          <Button
            variant="danger"
            size="sm"
            onClick={onConfirm}
            disabled={isDeleting}
          >
            {isDeleting ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin mr-2" />
                Deleting...
              </>
            ) : (
              'Delete Run'
            )}
          </Button>
        </div>
      </div>
    </Modal>
  );
};
