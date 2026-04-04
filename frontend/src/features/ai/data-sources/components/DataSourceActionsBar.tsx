import React from 'react';
import { Zap, Edit, Trash2 } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import type { AiDataSource } from '@/shared/types/ai';

interface DataSourceActionsBarProps {
  dataSource: AiDataSource;
  canManageDataSources: boolean;
  canDeleteDataSources: boolean;
  canTestConnection: boolean;
  testing: boolean;
  onClose: () => void;
  onTestConnection: () => void;
  onEdit: () => void;
  onDelete: () => void;
}

export const DataSourceActionsBar: React.FC<DataSourceActionsBarProps> = ({
  dataSource,
  canManageDataSources,
  canDeleteDataSources,
  canTestConnection,
  testing,
  onClose,
  onTestConnection,
  onEdit,
  onDelete,
}) => {
  return (
    <div className="flex gap-3">
      <Button variant="outline" onClick={onClose}>
        Close
      </Button>
      {canTestConnection && (dataSource.credential_count ?? 0) > 0 && (
        <Button variant="outline" onClick={onTestConnection} disabled={testing}>
          <Zap className={`h-4 w-4 mr-2 ${testing ? 'animate-pulse' : ''}`} />
          {testing ? 'Testing...' : 'Test Connection'}
        </Button>
      )}
      {canManageDataSources && (
        <Button variant="outline" onClick={onEdit}>
          <Edit className="h-4 w-4 mr-2" />
          Edit Settings
        </Button>
      )}
      {canDeleteDataSources && (
        <Button variant="danger" onClick={onDelete}>
          <Trash2 className="h-4 w-4 mr-2" />
          Delete
        </Button>
      )}
    </div>
  );
};
