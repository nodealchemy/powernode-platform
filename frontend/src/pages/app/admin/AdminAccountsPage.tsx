import React, { useState } from 'react';
import { useSelector } from 'react-redux';
import { Navigate } from 'react-router-dom';
import { Building2, Plus } from 'lucide-react';
import { RootState } from '@/shared/services';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { useNotifications } from '@/shared/hooks/useNotifications';
import {
  accountsApi,
  AccountProvisionFormData,
  ProvisionedAccountResponse
} from '@/features/account/services/accountsApi';

/**
 * Provision an additional tenant account.
 *
 * ACCESS CONTROL: gated on the `admin.account.create` PERMISSION only — never on
 * a role. Creating an Account creates a tenancy boundary, which is a
 * platform-tier operation: the permission is deliberately absent from the
 * tenant `owner` role and is held by `admin` and (via `system.admin`) by
 * `super_admin`, which is what a fresh core-mode install's first operator holds.
 *
 * The form always collects an initial administrator. An account with no users is
 * not a usable tenant, and the server creates both in one transaction, so the
 * UI must not offer the half-formed variant.
 */
export const AdminAccountsPage: React.FC = () => {
  const { user: currentUser } = useSelector((state: RootState) => state.auth);
  const { showNotification } = useNotifications();

  const [form, setForm] = useState<AccountProvisionFormData>({
    name: '',
    subdomain: '',
    admin_email: '',
    admin_password: '',
    admin_name: ''
  });
  const [submitting, setSubmitting] = useState(false);
  const [created, setCreated] = useState<ProvisionedAccountResponse['data'] | null>(null);

  const canCreateAccounts = currentUser?.permissions?.includes('admin.account.create') ?? false;

  if (!canCreateAccounts) {
    return <Navigate to="/app" replace />;
  }

  const updateField = (field: keyof AccountProvisionFormData) =>
    (event: React.ChangeEvent<HTMLInputElement>) => {
      setForm((previous) => ({ ...previous, [field]: event.target.value }));
    };

  const formComplete =
    form.name.trim().length > 0 &&
    form.admin_email.trim().length > 0 &&
    form.admin_password.length > 0;

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!formComplete || submitting) return;

    setSubmitting(true);
    try {
      const response = await accountsApi.createAccount({
        name: form.name.trim(),
        subdomain: form.subdomain?.trim() ? form.subdomain.trim() : undefined,
        admin_email: form.admin_email.trim(),
        admin_password: form.admin_password,
        admin_name: form.admin_name?.trim() ? form.admin_name.trim() : undefined
      });

      setCreated(response.data);
      setForm({ name: '', subdomain: '', admin_email: '', admin_password: '', admin_name: '' });
      showNotification(`Account "${response.data.name}" created`, 'success');
    } catch (error) {
      const message =
        (error as { response?: { data?: { message?: string } } })?.response?.data?.message ||
        'Failed to create account';
      showNotification(message, 'error');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <PageContainer
      title="Accounts"
      description="Provision an additional tenant account and its initial administrator."
      breadcrumbs={[
        { label: 'Administration' },
        { label: 'Accounts', icon: Building2 }
      ]}
    >
      <div className="max-w-2xl space-y-6">
        {created && (
          <div className="rounded-lg border border-theme bg-theme-surface p-4">
            <h2 className="text-theme-primary font-semibold mb-1">
              Created {created.name}
            </h2>
            <p className="text-theme-secondary text-sm">
              Subdomain <span className="font-mono">{created.subdomain}</span> · administrator{' '}
              <span className="font-mono">{created.administrator.email}</span>. The administrator can
              sign in with the password you set; nothing else was emailed.
            </p>
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <Input
            label="Account name"
            value={form.name}
            onChange={updateField('name')}
            placeholder="Federation Hub B"
            required
          />
          <Input
            label="Subdomain"
            value={form.subdomain}
            onChange={updateField('subdomain')}
            placeholder="Leave blank to derive one from the name"
            description="Lowercase letters, numbers and hyphens. Must be unique across the platform."
          />

          <div className="pt-2 border-t border-theme">
            <h3 className="text-theme-primary font-medium mt-4 mb-1">Initial administrator</h3>
            <p className="text-theme-secondary text-sm mb-4">
              Required. The account is created with this user as its owner — an account with no
              users cannot be administered.
            </p>
            <div className="space-y-4">
              <Input
                label="Administrator name"
                value={form.admin_name}
                onChange={updateField('admin_name')}
                placeholder="Admin"
              />
              <Input
                label="Administrator email"
                type="email"
                value={form.admin_email}
                onChange={updateField('admin_email')}
                required
              />
              <Input
                label="Administrator password"
                type="password"
                autoComplete="new-password"
                value={form.admin_password}
                onChange={updateField('admin_password')}
                required
              />
            </div>
          </div>

          <div className="flex justify-end pt-2">
            <Button type="submit" variant="primary" loading={submitting} disabled={!formComplete}>
              <Plus className="w-4 h-4 mr-2" />
              Create account
            </Button>
          </div>
        </form>
      </div>
    </PageContainer>
  );
};

export default AdminAccountsPage;
