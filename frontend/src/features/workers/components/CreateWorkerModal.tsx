import React from 'react';
import { CreateWorkerData } from '@/features/workers/services/workerApi';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { useForm, FormValidationRules } from '@/shared/hooks/useForm';
import { Wrench, Save } from 'lucide-react';

interface CreateWorkerModalProps {
  isOpen: boolean;
  onClose: () => void;
  onCreate: (data: CreateWorkerData) => Promise<void>;
}

export const CreateWorkerModal: React.FC<CreateWorkerModalProps> = ({ isOpen, onClose, onCreate }) => {
  const defaultValues: CreateWorkerData = {
    name: '',
    description: '',
    permissions: 'standard',
    role: 'account'
  };

  const validationRules: FormValidationRules = {
    name: {
      required: true,
      minLength: 2,
      maxLength: 100,
    },
    description: {
      maxLength: 500,
    }
  };

  const handleCreateWorker = async (formData: CreateWorkerData) => {
    await onCreate(formData);
    onClose();
  };

  const form = useForm<CreateWorkerData>({
    initialValues: defaultValues,
    validationRules,
    onSubmit: handleCreateWorker,
    enableRealTimeValidation: true,
    showSuccessNotification: true,
    successMessage: 'Worker created successfully',
    resetAfterSubmit: true,
  });

  const handleCancel = () => {
    form.reset();
    onClose();
  };

  const modalFooter = (
    <div className="flex justify-end space-x-3">
      <Button
        variant="secondary"
        onClick={handleCancel}
        disabled={form.isSubmitting}
      >
        Cancel
      </Button>
      <Button
        variant="primary"
        type="submit"
        form="create-worker-form"
        loading={form.isSubmitting}
      >
        {!form.isSubmitting && <Save className="w-4 h-4 mr-2" />}
        {form.isSubmitting ? 'Creating...' : 'Create Worker'}
      </Button>
    </div>
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleCancel}
      title="Create New Worker"
      subtitle="Add a new worker to your system"
      icon={<Wrench />}
      maxWidth="md"
      footer={modalFooter}
      closeOnBackdrop={!form.isSubmitting}
      closeOnEscape={!form.isSubmitting}
    >
      <form id="create-worker-form" onSubmit={form.handleSubmit} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Worker Name *
          </label>
          <input
            {...form.getFieldProps('name')}
            type="text"
            className={`w-full px-3 py-2 border rounded-md bg-theme-background text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent ${
              form.errors.name ? 'border-theme-error' : 'border-theme'
            }`}
            placeholder="Enter worker name"
            required
            disabled={form.isSubmitting}
          />
          {form.errors.name && (
            <p className="text-theme-error text-sm mt-1">{form.errors.name}</p>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Description
          </label>
          <textarea
            {...form.getFieldProps('description')}
            className={`w-full px-3 py-2 border rounded-md bg-theme-background text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent ${
              form.errors.description ? 'border-theme-error' : 'border-theme'
            }`}
            placeholder="Enter description (optional)"
            rows={3}
            disabled={form.isSubmitting}
          />
          {form.errors.description && (
            <p className="text-theme-error text-sm mt-1">{form.errors.description}</p>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Permissions
          </label>
          <select
            {...form.getFieldProps('permissions')}
            className={`w-full px-3 py-2 border rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent ${
              form.errors.permissions ? 'border-theme-error' : 'border-theme'
            }`}
            disabled={form.isSubmitting}
          >
            <option value="readonly">Read Only</option>
            <option value="standard">Standard</option>
            <option value="admin">Admin</option>
            <option value="super_admin">Super Admin</option>
          </select>
          {form.errors.permissions && (
            <p className="text-theme-error text-sm mt-1">{form.errors.permissions}</p>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Role
          </label>
          <select
            {...form.getFieldProps('role')}
            className={`w-full px-3 py-2 border rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent ${
              form.errors.role ? 'border-theme-error' : 'border-theme'
            }`}
            disabled={form.isSubmitting}
          >
            <option value="account">Account Worker</option>
            <option value="system">System Worker</option>
          </select>
          {form.errors.role && (
            <p className="text-theme-error text-sm mt-1">{form.errors.role}</p>
          )}
        </div>
      </form>
    </Modal>
  );
};

export default CreateWorkerModal;