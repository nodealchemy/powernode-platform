import React from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { AlertTriangle, Trash2, Info, HelpCircle } from 'lucide-react';

export type ConfirmationVariant = 'danger' | 'warning' | 'info' | 'default';

export interface ConfirmationModalProps {
  isOpen: boolean;
  onClose: () => void;
  onConfirm: () => void;
  title: string;
  message: string | React.ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  variant?: ConfirmationVariant;
  loading?: boolean;
  /**
   * Disable the confirm button while the dialog stays open — for a body that
   * collects something the action REQUIRES (a typed reason, an acknowledgement)
   * and is not yet valid. `loading` already disables both buttons during the
   * action itself; this is about the state before it can start.
   */
  confirmDisabled?: boolean;
}

const variantConfig = {
  danger: {
    icon: Trash2,
    iconBg: 'bg-theme-danger-fg/10',
    iconColor: 'text-theme-danger-fg',
    confirmVariant: 'danger' as const
  },
  warning: {
    icon: AlertTriangle,
    iconBg: 'bg-theme-warning-fg/10',
    iconColor: 'text-theme-warning-fg',
    confirmVariant: 'warning' as const
  },
  info: {
    icon: Info,
    iconBg: 'bg-theme-info-fg/10',
    iconColor: 'text-theme-info-fg',
    confirmVariant: 'primary' as const
  },
  default: {
    icon: HelpCircle,
    iconBg: 'bg-theme-background-secondary/10',
    iconColor: 'text-theme-tertiary',
    confirmVariant: 'primary' as const
  }
};

export const ConfirmationModal: React.FC<ConfirmationModalProps> = ({
  isOpen,
  onClose,
  onConfirm,
  title,
  message,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  variant = 'default',
  loading = false,
  confirmDisabled = false
}) => {
  const config = variantConfig[variant];
  const IconComponent = config.icon;

  const handleConfirm = () => {
    onConfirm();
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={title}
      size="sm"
      variant="centered"
      icon={
        <div className={`p-2 rounded-lg ${config.iconBg}`}>
          <IconComponent className={`h-6 w-6 ${config.iconColor}`} />
        </div>
      }
      footer={
        <div className="flex gap-3 w-full justify-end">
          <Button
            variant="secondary"
            onClick={onClose}
            disabled={loading}
          >
            {cancelLabel}
          </Button>
          <Button
            variant={config.confirmVariant}
            onClick={handleConfirm}
            disabled={loading || confirmDisabled}
          >
            {loading ? 'Processing...' : confirmLabel}
          </Button>
        </div>
      }
    >
      <div className="text-theme-secondary">
        {typeof message === 'string' ? <p>{message}</p> : message}
      </div>
    </Modal>
  );
};

// Hook for easier confirmation modal usage
export interface UseConfirmationOptions {
  title: string;
  message: string | React.ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  variant?: ConfirmationVariant;
  /**
   * Disable the confirm button until the dialog's body is valid.
   *
   * Pass a FUNCTION when the answer depends on something the body collects.
   * `options` is snapshotted state, so a plain boolean captured at `confirm()`
   * time can never change; the predicate is re-evaluated on every render of
   * the owning component, which is what a body that reports its value upward
   * (see the reason-carrying wrappers) triggers as the operator types.
   */
  confirmDisabled?: boolean | (() => boolean);
  onConfirm: () => void | Promise<void>;
}

export const useConfirmation = () => {
  const [isOpen, setIsOpen] = React.useState(false);
  const [loading, setLoading] = React.useState(false);
  const [options, setOptions] = React.useState<UseConfirmationOptions | null>(null);

  const confirm = (opts: UseConfirmationOptions) => {
    setOptions(opts);
    setIsOpen(true);
  };

  const handleClose = () => {
    if (!loading) {
      setIsOpen(false);
      setOptions(null);
    }
  };

  /**
   * Drop a pending confirmation unconditionally.
   *
   * `handleClose` is the operator's dismiss and deliberately no-ops while an
   * action is in flight. This is for the owning component instead: a modal that
   * renders `null` when closed rather than unmounting keeps this hook's state,
   * so a confirmation the operator left open re-appears the next time that
   * modal opens — still carrying the `onConfirm` captured against the PREVIOUS
   * subject. Components that stack a confirmation inside such a modal must call
   * this when they close.
   */
  const close = React.useCallback(() => {
    setIsOpen(false);
    setOptions(null);
    setLoading(false);
  }, []);

  const handleConfirm = async () => {
    if (!options) return;

    setLoading(true);
    try {
      await options.onConfirm();
      setIsOpen(false);
      setOptions(null);
    } finally {
      setLoading(false);
    }
  };

  const ConfirmationDialog = options ? (
    <ConfirmationModal
      isOpen={isOpen}
      onClose={handleClose}
      onConfirm={handleConfirm}
      title={options.title}
      message={options.message}
      confirmLabel={options.confirmLabel}
      cancelLabel={options.cancelLabel}
      variant={options.variant}
      loading={loading}
      confirmDisabled={
        typeof options.confirmDisabled === 'function'
          ? options.confirmDisabled()
          : options.confirmDisabled
      }
    />
  ) : null;

  return { confirm, close, ConfirmationDialog };
};

export default ConfirmationModal;
