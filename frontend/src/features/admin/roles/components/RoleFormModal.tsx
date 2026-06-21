
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { FormField } from '@/shared/components/ui/FormField';
import { rolesApi, Role, Permission, RoleFormData } from '../services/rolesApi';
import { useForm, FormValidationRules } from '@/shared/hooks/useForm';
import { Save, X, Shield, ShieldCheck, Lock, CheckCircle } from 'lucide-react';

interface RoleFormModalProps {
  role?: Role;
  permissions: Permission[];
  onSave: () => void;
  onClose: () => void;
}

export const RoleFormModal: React.FC<RoleFormModalProps> = ({
  role,
  permissions,
  onSave,
  onClose
}) => {
  // Global / code-defined roles are read-only (editable === false). New roles are always editable.
  const isReadOnly = role ? role.editable === false : false;

  const defaultValues: RoleFormData = {
    name: role?.name || '',
    description: role?.description || '',
    permission_names: role?.permissions.map(p => p.name) || []
  };

  const validationRules: FormValidationRules = {
    name: {
      required: true,
      minLength: 3,
      maxLength: 100,
    },
    description: {
      required: true,
      minLength: 10,
      maxLength: 500,
    },
    permission_names: {
      custom: (value: unknown) => {
        const permissions = value as string[];
        if (!permissions || permissions.length === 0) {
          return 'At least one permission must be selected';
        }
        return null;
      }
    }
  };

  const handleRoleSave = async (formData: RoleFormData) => {
    if (role) {
      await rolesApi.updateRole(role.id, formData);
    } else {
      await rolesApi.createRole(formData);
    }
    onSave();
  };

  const form = useForm<RoleFormData>({
    initialValues: defaultValues,
    validationRules,
    onSubmit: handleRoleSave,
    enableRealTimeValidation: true,
    showSuccessNotification: true,
    successMessage: role ? 'Role updated successfully' : 'Role created successfully',
  });

  // Group permissions by resource for better display
  const groupedPermissions = permissions.reduce((acc, permission) => {
    if (!acc[permission.resource]) {
      acc[permission.resource] = [];
    }
    acc[permission.resource].push(permission);
    return acc;
  }, {} as Record<string, Permission[]>);

  const handlePermissionToggle = (permissionName: string) => {
    const currentPermissions = form.values.permission_names;
    const newPermissions = currentPermissions.includes(permissionName)
      ? currentPermissions.filter(name => name !== permissionName)
      : [...currentPermissions, permissionName];

    form.setValue('permission_names', newPermissions);
  };

  const handleSelectAllInResource = (resource: string) => {
    // Get resource permissions safely to prevent object injection
    const validResources = Object.keys(groupedPermissions);
    if (!validResources.includes(resource)) return;


    const resourcePermissions = groupedPermissions[resource];
    if (!resourcePermissions || resourcePermissions.length === 0) return;

    const allSelected = resourcePermissions.every(p =>
      form.values.permission_names.includes(p.name)
    );

    if (allSelected) {
      // Deselect all permissions in this resource
      const newPermissions = form.values.permission_names.filter(name =>
        !resourcePermissions.some(p => p.name === name)
      );
      form.setValue('permission_names', newPermissions);
    } else {
      // Select all permissions in this resource
      const newPermissionNames = resourcePermissions.map(p => p.name);
      const updatedPermissions = Array.from(new Set([...form.values.permission_names, ...newPermissionNames]));
      form.setValue('permission_names', updatedPermissions);
    }
  };


  return (
    <Modal
      title={role ? 'Edit Role' : 'Create New Role'}
      icon={<ShieldCheck className="w-6 h-6" />}
      isOpen={true}
      onClose={onClose}
      maxWidth="xl"
    >
      <form onSubmit={form.handleSubmit} className="space-y-6">
        {/* Role Name */}
        <FormField
          label="Role Name"
          type="text"
          value={form.values.name}
          onChange={(value) => form.setValue('name', value)}
          placeholder="e.g., Content Manager"
          required
          disabled={role?.system_role || isReadOnly || form.isSubmitting}
          error={form.errors.name}
        />

        {/* Role Description */}
        <FormField
          label="Description"
          type="textarea"
          value={form.values.description}
          onChange={(value) => form.setValue('description', value)}
          placeholder="Describe the purpose and responsibilities of this role"
          rows={3}
          required
          disabled={role?.system_role || isReadOnly || form.isSubmitting}
          error={form.errors.description}
        />

        {/* Permissions */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Permissions <span className="text-theme-error-fg">*</span>
          </label>
          {form.errors.permission_names && (
            <p className="text-sm text-theme-error-fg mb-2">{form.errors.permission_names}</p>
          )}

          <div className="bg-theme-surface border border-theme rounded-lg p-4 max-h-96 overflow-y-auto">
            {Object.entries(groupedPermissions).map(([resource, resourcePermissions]) => {
              const allSelected = resourcePermissions.every(p =>
                form.values.permission_names.includes(p.name)
              );
              const someSelected = resourcePermissions.some(p =>
                form.values.permission_names.includes(p.name)
              );

              return (
                <div key={resource} className="mb-6 last:mb-0">
                  <div className="flex items-center justify-between mb-3 pb-2 border-b border-theme">
                    <h4 className="font-medium text-theme-primary capitalize flex items-center space-x-2">
                      <Shield className="w-4 h-4 text-theme-interactive-primary" />
                      <span>{resource.replace(/_/g, ' ')}</span>
                    </h4>
                    <Button
                      type="button"
                      onClick={() => handleSelectAllInResource(resource)}
                      variant={allSelected ? 'primary' : someSelected ? 'secondary' : 'outline'}
                      size="xs"
                      disabled={role?.system_role || isReadOnly || form.isSubmitting}
                    >
                      {allSelected ? 'Deselect All' : 'Select All'}
                    </Button>
                  </div>
                  
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
                    {resourcePermissions.map(permission => (
                      <label
                        key={permission.name}
                        className="flex items-start space-x-3 cursor-pointer hover:bg-theme-surface-hover p-3 rounded-md transition-colors"
                      >
                        <input
                          type="checkbox"
                          checked={form.values.permission_names.includes(permission.name)}
                          onChange={() => handlePermissionToggle(permission.name)}
                          className="mt-0.5 h-4 w-4 text-theme-interactive-primary rounded border-theme focus:ring-2 focus:ring-theme-interactive-primary focus:ring-offset-0"
                          disabled={role?.system_role || isReadOnly || form.isSubmitting}
                        />
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center space-x-2">
                            <code className="text-sm font-medium text-theme-interactive-primary">
                              {permission.action}
                            </code>
                          </div>
                          <p className="text-xs text-theme-secondary mt-0.5 break-words">
                            {permission.description}
                          </p>
                        </div>
                      </label>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>

          <div className="mt-3 flex items-center justify-between">
            <div className="flex items-center space-x-2">
              <Badge variant={form.values.permission_names.length > 0 ? 'success' : 'secondary'} size="sm">
                <CheckCircle className="w-3 h-3 mr-1" />
                {form.values.permission_names.length} selected
              </Badge>
              <Badge variant="secondary" size="sm">
                {permissions.length} total
              </Badge>
            </div>
            {form.values.permission_names.length > permissions.length * 0.75 && (
              <Badge variant="warning" size="sm">
                High permission level
              </Badge>
            )}
          </div>
        </div>

        {/* System Role Warning */}
        {role?.system_role && (
          <div className="bg-theme-warning-bg border border-theme-warning-border rounded-lg p-4">
            <div className="flex items-start space-x-3">
              <Lock className="w-5 h-5 text-theme-warning-fg mt-0.5" />
              <div>
                <p className="text-sm font-medium text-theme-warning-fg">System Role</p>
                <p className="text-xs text-theme-warning-fg mt-1 opacity-90">
                  This is a built-in system role and cannot be modified or deleted.
                </p>
              </div>
            </div>
          </div>
        )}

        {/* Global (read-only) Role Notice */}
        {isReadOnly && !role?.system_role && (
          <div className="bg-theme-warning-bg border border-theme-warning-border rounded-lg p-4">
            <div className="flex items-start space-x-3">
              <Lock className="w-5 h-5 text-theme-warning-fg mt-0.5" />
              <div>
                <p className="text-sm font-medium text-theme-warning-fg">Global Role</p>
                <p className="text-xs text-theme-warning-fg mt-1 opacity-90">
                  Global roles are code-defined and read-only.
                </p>
              </div>
            </div>
          </div>
        )}

        {/* Form Actions */}
        <div className="flex justify-end space-x-3 pt-4 border-t border-theme">
          <Button
            type="button"
            variant="secondary"
            onClick={onClose}
            disabled={form.isSubmitting}
          >
            <X className="w-4 h-4 mr-2" />
            {isReadOnly || role?.system_role ? 'Close' : 'Cancel'}
          </Button>
          {!role?.system_role && !isReadOnly && (
            <Button
              type="submit"
              variant="primary"
              disabled={form.isSubmitting || !form.isValid}
              loading={form.isSubmitting}
            >
              <Save className="w-4 h-4 mr-2" />
              {form.isSubmitting ? 'Saving...' : (role ? 'Update Role' : 'Create Role')}
            </Button>
          )}
        </div>
      </form>
    </Modal>
  );
};