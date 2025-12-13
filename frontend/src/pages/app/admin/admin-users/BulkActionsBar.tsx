import React from 'react';
import { Download, UserCheck, Shield } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { BulkActionsBarProps } from './types';

export const BulkActionsBar: React.FC<BulkActionsBarProps> = ({
  selectedCount,
  onClearSelection,
  onExport,
  onActivate,
  onSuspend,
  onDelete,
  actionLoading
}) => (
  <div className="bg-theme-info-background border border-theme-info-border rounded-lg p-4 mb-6">
    <div className="flex items-center justify-between">
      <div className="flex items-center space-x-4">
        <span className="text-theme-info font-medium">
          {selectedCount} user{selectedCount > 1 ? 's' : ''} selected
        </span>
        <button
          onClick={onClearSelection}
          className="text-theme-tertiary hover:text-theme-secondary text-sm"
        >
          Clear selection
        </button>
      </div>
      <div className="flex items-center space-x-2">
        <Button
          variant="secondary"
          size="sm"
          onClick={onExport}
          disabled={actionLoading}
        >
          <Download className="h-4 w-4 mr-1" />
          Export Selected
        </Button>
        <Button
          variant="secondary"
          size="sm"
          onClick={onActivate}
          disabled={actionLoading}
        >
          <UserCheck className="h-4 w-4 mr-1" />
          Activate
        </Button>
        <Button
          variant="secondary"
          size="sm"
          onClick={onSuspend}
          disabled={actionLoading}
        >
          <Shield className="h-4 w-4 mr-1" />
          Suspend
        </Button>
        <Button
          variant="danger"
          size="sm"
          onClick={onDelete}
          disabled={actionLoading}
        >
          Delete Selected
        </Button>
      </div>
    </div>
  </div>
);
