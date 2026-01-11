import React from 'react';
import { Plus } from 'lucide-react';
import { Input } from '@/shared/components/ui/Input';

interface CredentialFormData {
  name: string;
  api_key: string;
  org_id: string;
  expires_at: string;
}

interface AddCredentialFormProps {
  data: CredentialFormData;
  onChange: (field: string, value: string) => void;
  disabled: boolean;
}

export const AddCredentialForm: React.FC<AddCredentialFormProps> = ({
  data,
  onChange,
  disabled
}) => {
  return (
    <div className="space-y-4 p-4 bg-theme-info/5 border border-theme-info/20 rounded-lg">
      <h5 className="text-sm font-medium text-theme-primary flex items-center gap-2">
        <Plus className="h-4 w-4" />
        Add New Credential (Optional)
      </h5>
      <p className="text-xs text-theme-muted">
        Leave fields blank to update provider without adding credentials.
      </p>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Credential Name
          </label>
          <Input
            value={data.name}
            onChange={(e) => onChange('name', e.target.value)}
            placeholder="e.g., Production API Key"
            disabled={disabled}
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            API Key
          </label>
          <Input
            type="password"
            value={data.api_key}
            onChange={(e) => onChange('api_key', e.target.value)}
            placeholder="sk-..."
            disabled={disabled}
          />
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Organization ID (Optional)
          </label>
          <Input
            value={data.org_id}
            onChange={(e) => onChange('org_id', e.target.value)}
            placeholder="org-..."
            disabled={disabled}
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Expires At (Optional)
          </label>
          <Input
            type="date"
            value={data.expires_at}
            onChange={(e) => onChange('expires_at', e.target.value)}
            disabled={disabled}
          />
        </div>
      </div>

      {(data.name || data.api_key) && (
        <div className="text-xs text-theme-info">
          <strong>Note:</strong> A new credential will be created with these details when you save the provider.
        </div>
      )}
    </div>
  );
};
