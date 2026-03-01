
import { Worker, UpdateWorkerData } from '@/features/admin/workers/services/workerApi';
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
    roles: worker.roles
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
    roles: {
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
            Roles *
          </label>
          <div className="space-y-2">
            <div className="text-sm text-theme-secondary">Select applicable roles (permissions are inherited from roles):</div>
            <div className="space-y-2 max-h-48 overflow-y-auto border border-theme rounded p-3 bg-theme-background">
              {[
                { name: 'member', display: 'Member' },
                { name: 'developer', display: 'App Developer' },
                { name: 'billing_admin', display: 'Billing Administrator' },
                { name: 'admin', display: 'Administrator' },
                { name: 'super_admin', display: 'Super Administrator' },
                { name: 'system_worker', display: 'System Worker' },
                { name: 'task_worker', display: 'Task Worker' }
              ].map((role) => (
                <label key={role.name} className="flex items-center space-x-2">
                  <input
                    type="checkbox"
                    checked={form.values.roles?.includes(role.name) || false}
                    onChange={(e) => {
                      const currentRoles = form.values.roles || [];
                      const newRoles = e.target.checked
                        ? [...currentRoles, role.name]
                        : currentRoles.filter(r => r !== role.name);
                      form.setValue('roles', newRoles);
                    }}
                    className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
                    disabled={form.isSubmitting}
                  />
                  <span className="text-sm text-theme-primary">{role.display}</span>
                </label>
              ))}
            </div>
          </div>
          {form.errors.roles && (
            <p className="text-theme-error text-sm mt-1">{form.errors.roles}</p>
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