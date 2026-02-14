import React from 'react';
import { Zap, RefreshCw, Edit, Trash2 } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import type { AiProvider } from '@/shared/types/ai';

interface ProviderActionsBarProps {
  provider: AiProvider;
  canManageProviders: boolean;
  canDeleteProviders: boolean;
  canTestCredentials: boolean;
  testing: boolean;
  syncing: boolean;
  onClose: () => void;
  onTestConnection: () => void;
  onSyncModels: () => void;
  onEdit: () => void;
  onDelete: () => void;
}

export const ProviderActionsBar: React.FC<ProviderActionsBarProps> = ({
  provider,
  canManageProviders,
  canDeleteProviders,
  canTestCredentials,
  testing,
  syncing,
  onClose,
  onTestConnection,
  onSyncModels,
  onEdit,
  onDelete,
}) => {
  return (
    <div className="flex gap-3">
      <Button variant="outline" onClick={onClose}>
        Close
      </Button>
      {canTestCredentials && (provider.credential_count ?? 0) > 0 && (
        <Button variant="outline" onClick={onTestConnection} disabled={testing}>
          <Zap className={`h-4 w-4 mr-2 ${testing ? 'animate-pulse' : ''}`} />
          {testing ? 'Testing...' : 'Test Connection'}
        </Button>
      )}
      {canManageProviders && (
        <>
          <Button variant="outline" onClick={onSyncModels} disabled={syncing}>
            <RefreshCw className={`h-4 w-4 mr-2 ${syncing ? 'animate-spin' : ''}`} />
            {syncing ? 'Syncing...' : 'Sync Models'}
          </Button>
          <Button variant="outline" onClick={onEdit}>
            <Edit className="h-4 w-4 mr-2" />
            Edit Settings
          </Button>
        </>
      )}
      {canDeleteProviders && (
        <Button variant="danger" onClick={onDelete}>
          <Trash2 className="h-4 w-4 mr-2" />
          Delete
        </Button>
      )}
    </div>
  );
};
