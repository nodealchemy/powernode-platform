import React from 'react';
import { Save, Edit, Star, Trash2, TestTube, Check, XCircle } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import type { AiProviderCredential } from '@/shared/types/ai';

interface EditCredentialData {
  name: string;
  api_key: string;
  org_id: string;
  is_active: boolean;
}

interface CredentialCardProps {
  credential: AiProviderCredential;
  isEditing: boolean;
  editData: EditCredentialData;
  isLoading: boolean;
  onStartEdit: () => void;
  onCancelEdit: () => void;
  onSaveEdit: () => void;
  onEditDataChange: (data: Partial<EditCredentialData>) => void;
  onTest: () => void;
  onDelete: () => void;
  onMakeDefault: () => void;
}

const getTestStatusBadge = (credential: AiProviderCredential) => {
  // Check if credential has test properties (they may not exist on type)
  const lastTestAt = (credential as any).last_test_at;
  const lastTestStatus = (credential as any).last_test_status;

  if (!lastTestAt) {
    return <span className="text-xs px-2 py-0.5 rounded bg-theme-secondary/20 text-theme-muted">Not tested</span>;
  }
  if (lastTestStatus === 'success') {
    return <span className="text-xs px-2 py-0.5 rounded bg-theme-success/20 text-theme-success flex items-center gap-1"><Check className="h-3 w-3" />Passed</span>;
  }
  return <span className="text-xs px-2 py-0.5 rounded bg-theme-danger/20 text-theme-danger flex items-center gap-1"><XCircle className="h-3 w-3" />Failed</span>;
};

export const CredentialCard: React.FC<CredentialCardProps> = ({
  credential,
  isEditing,
  editData,
  isLoading,
  onStartEdit,
  onCancelEdit,
  onSaveEdit,
  onEditDataChange,
  onTest,
  onDelete,
  onMakeDefault
}) => {
  if (isEditing) {
    return (
      <div className="p-3 bg-theme-secondary/10 rounded-lg border border-theme">
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-1">Name</label>
              <Input
                value={editData.name}
                onChange={(e) => onEditDataChange({ name: e.target.value })}
                placeholder="Credential name"
                className="text-sm"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-1">Status</label>
              <Select
                value={editData.is_active ? 'active' : 'inactive'}
                onChange={(value) => onEditDataChange({ is_active: value === 'active' })}
                className="text-sm"
              >
                <option value="active">Active</option>
                <option value="inactive">Inactive</option>
              </Select>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-1">New API Key (optional)</label>
              <Input
                type="password"
                value={editData.api_key}
                onChange={(e) => onEditDataChange({ api_key: e.target.value })}
                placeholder="Leave blank to keep existing"
                className="text-sm"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-1">Organization ID (optional)</label>
              <Input
                value={editData.org_id}
                onChange={(e) => onEditDataChange({ org_id: e.target.value })}
                placeholder="Leave blank to keep existing"
                className="text-sm"
              />
            </div>
          </div>
          <div className="flex items-center justify-end gap-2">
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={onCancelEdit}
              disabled={isLoading}
            >
              Cancel
            </Button>
            <Button
              type="button"
              variant="primary"
              size="sm"
              onClick={onSaveEdit}
              disabled={isLoading || !editData.name.trim()}
              className="flex items-center gap-1"
            >
              <Save className="h-3 w-3" />
              Save
            </Button>
          </div>
        </div>
      </div>
    );
  }

  // Check for test properties
  const lastTestAt = (credential as any).last_test_at;

  return (
    <div className="p-3 bg-theme-secondary/10 rounded-lg border border-theme">
      <div className="flex items-center justify-between">
        <div className="flex-1">
          <div className="flex items-center gap-2">
            <p className="text-sm font-medium text-theme-primary">{credential.name}</p>
            {credential.is_default && (
              <span className="text-xs px-2 py-0.5 rounded bg-theme-warning/20 text-theme-warning flex items-center gap-1">
                <Star className="h-3 w-3" />Default
              </span>
            )}
            {getTestStatusBadge(credential)}
          </div>
          <p className="text-xs text-theme-muted mt-1">
            {credential.is_active ? 'Active' : 'Inactive'} •
            Last used: {credential.last_used_at ? new Date(credential.last_used_at).toLocaleDateString() : 'Never'}
            {lastTestAt && ` • Last tested: ${new Date(lastTestAt).toLocaleDateString()}`}
          </p>
        </div>
        <div className="flex items-center gap-1">
          {!credential.is_default && (
            <Button
              type="button"
              variant="ghost"
              size="sm"
              onClick={onMakeDefault}
              disabled={isLoading}
              title="Make default"
              className="h-8 w-8 p-0"
            >
              <Star className="h-3 w-3" />
            </Button>
          )}
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={onStartEdit}
            disabled={isLoading}
            title="Edit credential"
            className="h-8 w-8 p-0"
          >
            <Edit className="h-3 w-3" />
          </Button>
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={onTest}
            disabled={isLoading}
            className="flex items-center gap-1"
          >
            <TestTube className="h-3 w-3" />
            Test
          </Button>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={onDelete}
            disabled={isLoading}
            title="Delete credential"
            className="h-8 w-8 p-0 text-theme-danger hover:text-theme-danger/80"
          >
            <Trash2 className="h-3 w-3" />
          </Button>
        </div>
      </div>
    </div>
  );
};
