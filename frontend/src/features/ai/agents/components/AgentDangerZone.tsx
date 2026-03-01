import React from 'react';
import { Button } from '@/shared/components/ui/Button';

interface AgentDangerZoneProps {
  agentName: string;
  showDeleteConfirm: boolean;
  deleting: boolean;
  onConfirmDelete: () => void;
  onCancelDelete: () => void;
}

export const AgentDangerZone: React.FC<AgentDangerZoneProps> = ({
  agentName,
  showDeleteConfirm,
  deleting,
  onConfirmDelete,
  onCancelDelete,
}) => {
  if (!showDeleteConfirm) return null;

  return (
    <div className="bg-theme-error-background border border-theme-error rounded-lg p-4">
      <h5 className="font-semibold text-theme-error mb-2">Confirm Deletion</h5>
      <p className="text-sm text-theme-secondary mb-4">
        Are you sure you want to delete &quot;{agentName}&quot;? This action cannot be undone.
        All associated executions and data will be permanently removed.
      </p>
      <div className="flex items-center gap-2">
        <Button
          variant="danger"
          size="sm"
          onClick={onConfirmDelete}
          loading={deleting}
        >
          Yes, Delete Agent
        </Button>
        <Button
          variant="ghost"
          size="sm"
          onClick={onCancelDelete}
          disabled={deleting}
        >
          Cancel
        </Button>
      </div>
    </div>
  );
};
