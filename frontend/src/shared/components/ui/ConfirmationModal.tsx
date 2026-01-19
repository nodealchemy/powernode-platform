import React from 'react';
import { Modal } from './Modal';
import { Button } from './Button';
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
}

const variantConfig = {
  danger: {
    icon: Trash2,
    iconBg: 'bg-theme-danger/10',
    iconColor: 'text-theme-danger',
    confirmVariant: 'danger' as const
  },
  warning: {
    icon: AlertTriangle,
    iconBg: 'bg-theme-warning/10',
    iconColor: 'text-theme-warning',
    confirmVariant: 'warning' as const
  },
  info: {
    icon: Info,
    iconBg: 'bg-theme-info/10',
    iconColor: 'text-theme-info',
    confirmVariant: 'primary' as const
  },
  default: {
    icon: HelpCircle,
    iconBg: 'bg-theme-muted/10',
    iconColor: 'text-theme-muted',
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
  loading = false
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
            disabled={loading}
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

  const handleConfirm = async () => {
    if (!options) return;

    try {
      setLoading(true);
      await options.onConfirm();
      setIsOpen(false);
      setOptions(null);
    } catch (error) {
      // Let the caller handle errors via their onConfirm
      throw error;
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
    />
  ) : null;

  return { confirm, ConfirmationDialog };
};

export default ConfirmationModal;
