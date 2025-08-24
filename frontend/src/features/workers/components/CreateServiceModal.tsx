import React from 'react';
import { CreateServiceData } from '@/shared/services/serviceApi';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { useForm, FormValidationRules } from '@/shared/hooks/useForm';
import { Settings, Save } from 'lucide-react';

interface CreateServiceModalProps {
  isOpen: boolean;
  onClose: () => void;
  onCreate: (data: CreateServiceData) => Promise<void>;
}

export const CreateServiceModal: React.FC<CreateServiceModalProps> = ({ isOpen, onClose, onCreate }) => {
  const defaultValues: CreateServiceData = {
    name: '',
    description: '',
    permissions: 'standard'
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

  const handleCreateService = async (formData: CreateServiceData) => {
    await onCreate(formData);
    onClose();
  };

  const form = useForm<CreateServiceData>({
    initialValues: defaultValues,
    validationRules,
    onSubmit: handleCreateService,
    enableRealTimeValidation: true,
    showSuccessNotification: true,
    successMessage: 'Service created successfully',
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
        form="create-service-form"
        loading={form.isSubmitting}
      >
        {!form.isSubmitting && <Save className="w-4 h-4 mr-2" />}
        {form.isSubmitting ? 'Creating...' : 'Create Service'}
      </Button>
    </div>
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleCancel}
      title="Create New Service"
      subtitle="Add a new service to your system"
      icon={<Settings />}
      maxWidth="md"
      footer={modalFooter}
      closeOnBackdrop={!form.isSubmitting}
      closeOnEscape={!form.isSubmitting}
    >
      <form id="create-service-form" onSubmit={form.handleSubmit} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Service Name *
          </label>
          <input
            {...form.getFieldProps('name')}
            type="text"
            className={`w-full px-3 py-2 border rounded-md text-sm bg-theme-surface text-theme-primary focus:ring-theme-interactive-primary focus:border-theme-interactive-primary ${
              form.errors.name ? 'border-theme-error' : 'border-theme'
            }`}
            placeholder="e.g., API Worker, Report Generator"
            required
            disabled={form.isSubmitting}
          />
          {form.errors.name && (
            <p className="text-theme-error text-sm mt-1">{form.errors.name}</p>
          )}
          <p className="text-xs text-theme-secondary mt-1">
            A descriptive name for this service
          </p>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Description
          </label>
          <textarea
            {...form.getFieldProps('description')}
            rows={3}
            className={`w-full px-3 py-2 border rounded-md text-sm bg-theme-surface text-theme-primary focus:ring-theme-interactive-primary focus:border-theme-interactive-primary ${
              form.errors.description ? 'border-theme-error' : 'border-theme'
            }`}
            placeholder="Optional description of what this service does"
            disabled={form.isSubmitting}
          />
          {form.errors.description && (
            <p className="text-theme-error text-sm mt-1">{form.errors.description}</p>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Permissions Level
          </label>
          <select
            {...form.getFieldProps('permissions')}
            className={`w-full px-3 py-2 border rounded-md text-sm bg-theme-surface text-theme-primary focus:ring-theme-interactive-primary focus:border-theme-interactive-primary ${
              form.errors.permissions ? 'border-theme-error' : 'border-theme'
            }`}
            disabled={form.isSubmitting}
          >
            <option value="readonly">Read Only - Can only read data</option>
            <option value="standard">Standard - Can process jobs and read/write data</option>
            <option value="admin">Admin - Can manage jobs and access admin functions</option>
            <option value="super_admin">Super Admin - Full access including service management</option>
          </select>
          {form.errors.permissions && (
            <p className="text-theme-error text-sm mt-1">{form.errors.permissions}</p>
          )}
          <p className="text-xs text-theme-secondary mt-1">
            Choose the appropriate access level for this service
          </p>
        </div>
      </form>
    </Modal>
  );
};

export default CreateServiceModal;