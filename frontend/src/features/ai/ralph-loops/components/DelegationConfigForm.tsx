import React from 'react';
import { Trash2, Loader2 } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';

interface DelegationConfigFormProps {
  onSave: () => void;
  onDelete?: () => void;
  onCancel?: () => void;
  isDeleting?: boolean;
}

export const DelegationConfigForm: React.FC<DelegationConfigFormProps> = ({
  onSave,
  onDelete,
  onCancel,
  isDeleting = false,
}) => {
  return (
    <div className="flex items-center justify-between pt-4 mt-4 border-t border-theme-border-primary">
      {onDelete ? (
        <Button
          variant="ghost"
          size="sm"
          onClick={onDelete}
          disabled={isDeleting}
          className="text-theme-status-error hover:bg-theme-status-error/10"
        >
          {isDeleting ? (
            <Loader2 className="w-4 h-4 mr-1 animate-spin" />
          ) : (
            <Trash2 className="w-4 h-4 mr-1" />
          )}
          Delete Task
        </Button>
      ) : (
        <div />
      )}
      <div className="flex gap-2">
        {onCancel && (
          <Button variant="outline" size="sm" onClick={onCancel}>
            Cancel
          </Button>
        )}
        <Button variant="primary" size="sm" onClick={onSave}>
          Save Task
        </Button>
      </div>
    </div>
  );
};
