import React from 'react';
import { X } from 'lucide-react';
import WebhookForm from './WebhookForm';
import { WebhookEndpoint, WebhookFormData } from '../services/webhooksApi';

interface WebhookModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
  onSubmit: (data: WebhookFormData) => Promise<void>;
  webhook?: WebhookEndpoint;
  mode: 'create' | 'edit';
}

export const WebhookModal: React.FC<WebhookModalProps> = ({
  isOpen,
  onClose,
  onSuccess,
  onSubmit,
  webhook,
  mode
}) => {
  const handleSubmit = async (data: WebhookFormData) => {
    await onSubmit(data);
    onSuccess();
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div className="bg-theme-surface rounded-lg shadow-xl max-w-4xl w-full max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between p-6 border-b border-theme">
          <h2 className="text-xl font-semibold text-theme-primary">
            {mode === 'create' ? 'Create Webhook' : 'Edit Webhook'}
          </h2>
          <button
            onClick={onClose}
            className="text-theme-secondary hover:text-theme-primary"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="p-6">
          <WebhookForm
            webhook={webhook}
            onSubmit={handleSubmit}
            onCancel={onClose}
          />
        </div>
      </div>
    </div>
  );
};