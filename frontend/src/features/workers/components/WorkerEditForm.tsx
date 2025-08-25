import React from 'react';
import { Worker, UpdateWorkerData } from '@/features/workers/services/workerApi';
import { Button } from '@/shared/components/ui/Button';
import { useForm, FormValidationRules } from '@/shared/hooks/useForm';
import { Save } from 'lucide-react';

interface WorkerEditFormProps {
  worker: Worker;
  onUpdate: (data: UpdateWorkerData) => Promise<void>;
  onCancel: () => void;
}

export const WorkerEditForm: React.FC<WorkerEditFormProps> = ({ worker, onUpdate, onCancel }) => {
  const defaultValues: UpdateWorkerData = {
    name: worker.name,
    description: worker.description || '',
    permissions: worker.permissions
  };

  const validationRules: FormValidationRules = {
    name: {
      required: true,
      minLength: 2,
      maxLength: 100,
    },
    description: {
      maxLength: 500,
    },
    permissions: {
      required: true,
    }
  };

  const handleUpdateWorker = async (formData: UpdateWorkerData) => {
    await onUpdate(formData);
  };

  const form = useForm<UpdateWorkerData>({
    initialValues: defaultValues,
    validationRules,
    onSubmit: handleUpdateWorker,
    enableRealTimeValidation: true,
    showSuccessNotification: true,
    successMessage: 'Worker updated successfully',
    resetAfterSubmit: false, // Don't reset after update
  });

  const handleCancel = () => {
    form.reset();
    onCancel();
  };

  return (
    <div className="space-y-6">
      <h3 className="text-lg font-semibold text-theme-primary">Edit Worker</h3>
      
      <form onSubmit={form.handleSubmit} className="space-y-4">
        <div>
          <label className="label-theme">
            Worker Name *
          </label>
          <input
            {...form.getFieldProps('name')}
            type="text"
            className={`input-theme ${form.errors.name ? 'border-theme-error' : ''}`}
            disabled={form.isSubmitting}
            required
          />
          {form.errors.name && (
            <p className="text-theme-error text-sm mt-1">{form.errors.name}</p>
          )}
        </div>

        <div>
          <label className="label-theme">
            Description
          </label>
          <textarea
            {...form.getFieldProps('description')}
            className={`input-theme ${form.errors.description ? 'border-theme-error' : ''}`}
            rows={3}
            disabled={form.isSubmitting}
          />
          {form.errors.description && (
            <p className="text-theme-error text-sm mt-1">{form.errors.description}</p>
          )}
        </div>

        <div>
          <label className="label-theme">
            Permissions *
          </label>
          <select
            {...form.getFieldProps('permissions')}
            className={`select-theme ${form.errors.permissions ? 'border-theme-error' : ''}`}
            disabled={form.isSubmitting}
            required
          >
            <option value="readonly">Read Only - Can only read data</option>
            <option value="standard">Standard - Can process jobs and read/write data</option>
            <option value="admin">Admin - Can manage jobs and access admin functions</option>
            <option value="super_admin">Super Admin - Full access including service management</option>
          </select>
          {form.errors.permissions && (
            <p className="text-theme-error text-sm mt-1">{form.errors.permissions}</p>
          )}
        </div>


        <div className="flex justify-end space-x-3 pt-4">
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
            loading={form.isSubmitting}
          >
            {!form.isSubmitting && <Save className="w-4 h-4 mr-2" />}
            {form.isSubmitting ? 'Updating...' : 'Update Worker'}
          </Button>
        </div>
      </form>
    </div>
  );
};

export default WorkerEditForm;