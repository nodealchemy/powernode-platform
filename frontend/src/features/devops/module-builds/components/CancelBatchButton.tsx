import React, { useState } from 'react';
import { Ban } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useAuth } from '@/shared/hooks/useAuth';
import { getErrorMessage } from '@/shared/services/errorHandler';
import { moduleBuildBatchesApi } from '../services/moduleBuildBatchesApi';
import type { ModuleBuildBatch } from '../types';

interface CancelBatchButtonProps {
  batch: ModuleBuildBatch;
  onCancelled: () => void;
  size?: 'sm' | 'md';
  /** Renders as an outline/danger button (detail page) instead of an icon-only affordance (list row). */
  variant?: 'button' | 'icon';
}

/**
 * Cancel action for an in-flight System::ModuleBuildBatch (system.module_builds.cancel).
 * Visible only when the batch is active AND the current user holds the
 * cancel permission — same permissions-only gating rule as everywhere else.
 */
export const CancelBatchButton: React.FC<CancelBatchButtonProps> = ({
  batch,
  onCancelled,
  size = 'sm',
  variant = 'button',
}) => {
  const { currentUser } = useAuth();
  const { showNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();
  const [cancelling, setCancelling] = useState(false);

  const canCancel = currentUser?.permissions?.includes('system.module_builds.cancel');
  if (!canCancel || !batch.active) return null;

  const handleCancel = () => {
    confirm({
      title: 'Cancel Module Build',
      message: `This stops in-flight builds for batch ${batch.id.slice(0, 8)}. Modules already published are unaffected. Continue?`,
      confirmLabel: 'Cancel Batch',
      variant: 'danger',
      onConfirm: async () => {
        setCancelling(true);
        try {
          await moduleBuildBatchesApi.cancel(batch.id);
          showNotification('Module build batch cancelled', 'success');
          onCancelled();
        } catch (err) {
          showNotification(getErrorMessage(err), 'error');
        } finally {
          setCancelling(false);
        }
      },
    });
  };

  return (
    <>
      <Button
        onClick={(e) => {
          e.stopPropagation();
          handleCancel();
        }}
        variant="danger"
        size={size}
        disabled={cancelling}
        iconOnly={variant === 'icon'}
        aria-label="Cancel build batch"
      >
        <Ban className={`w-4 h-4 ${variant === 'button' ? 'mr-1.5' : ''}`} />
        {variant === 'button' && (cancelling ? 'Cancelling...' : 'Cancel Batch')}
      </Button>
      {ConfirmationDialog}
    </>
  );
};

export default CancelBatchButton;
