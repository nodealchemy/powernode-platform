import React, { useState } from 'react';
import { ChevronDown, Play, Pause, Trash2, Download, X } from 'lucide-react';

export interface WorkerActionsProps {
  selectedCount: number;
  onBulkAction: (action: string) => void;
}

export const WorkerActions: React.FC<WorkerActionsProps> = ({
  selectedCount,
  onBulkAction
}) => {
  const [showActions, setShowActions] = useState(false);
  const [showConfirm, setShowConfirm] = useState<string | null>(null);

  const handleAction = (action: string) => {
    if (action === 'delete') {
      setShowConfirm(action);
    } else {
      onBulkAction(action);
    }
    setShowActions(false);
  };

  const confirmAction = (action: string) => {
    onBulkAction(action);
    setShowConfirm(null);
  };

  const actions = [
    {
      id: 'activate',
      label: 'Activate Workers',
      icon: Play,
      description: 'Activate selected workers',
      color: 'text-theme-success hover:bg-theme-success-background'
    },
    {
      id: 'suspend',
      label: 'Suspend Workers',
      icon: Pause,
      description: 'Suspend selected workers',
      color: 'text-theme-warning hover:bg-theme-warning-background'
    },
    {
      id: 'export',
      label: 'Export Data',
      icon: Download,
      description: 'Export selected workers data',
      color: 'text-theme-primary hover:bg-theme-background'
    },
    {
      id: 'delete',
      label: 'Delete Workers',
      icon: Trash2,
      description: 'Permanently delete selected workers',
      color: 'text-theme-error hover:bg-theme-error-background'
    }
  ];

  return (
    <>
      <div className="relative">
        {/* Bulk Actions Button */}
        <button
          onClick={() => setShowActions(!showActions)}
          className="flex items-center gap-2 px-4 py-2 bg-theme-interactive-primary text-white rounded-lg hover:bg-theme-interactive-primary/80 transition-colors"
        >
          <span className="text-sm font-medium">
            {selectedCount} worker{selectedCount === 1 ? '' : 's'} selected
          </span>
          <ChevronDown className={`w-4 h-4 transition-transform ${showActions ? 'rotate-180' : ''}`} />
        </button>

        {/* Actions Dropdown */}
        {showActions && (
          <div className="absolute top-full left-0 mt-2 w-64 bg-theme-surface border border-theme rounded-lg shadow-xl z-20">
            <div className="p-2 border-b border-theme">
              <div className="text-sm font-medium text-theme-primary">
                Bulk Actions ({selectedCount} workers)
              </div>
              <div className="text-xs text-theme-secondary">
                Choose an action to apply to all selected workers
              </div>
            </div>
            
            <div className="py-1">
              {actions.map((action) => {
                const Icon = action.icon;
                return (
                  <button
                    key={action.id}
                    onClick={() => handleAction(action.id)}
                    className={`w-full flex items-center gap-3 px-3 py-2 text-sm transition-colors ${action.color}`}
                  >
                    <Icon className="w-4 h-4" />
                    <div className="text-left">
                      <div className="font-medium">{action.label}</div>
                      <div className="text-xs opacity-75">{action.description}</div>
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
        )}
      </div>

      {/* Confirmation Modal */}
      {showConfirm && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
          <div className="bg-theme-surface rounded-lg p-6 w-full max-w-md">
            <div className="flex justify-between items-center mb-4">
              <h3 className="text-lg font-semibold text-theme-primary">
                Confirm Bulk Action
              </h3>
              <button
                onClick={() => setShowConfirm(null)}
                className="text-theme-secondary hover:text-theme-primary"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="mb-6">
              {showConfirm === 'delete' && (
                <div className="space-y-3">
                  <div className="p-3 bg-theme-error-background rounded-lg">
                    <div className="flex items-center gap-2 text-theme-error font-medium">
                      <Trash2 className="w-4 h-4" />
                      <span>Permanent Deletion Warning</span>
                    </div>
                  </div>
                  <p className="text-theme-secondary">
                    You are about to permanently delete <strong>{selectedCount}</strong> worker{selectedCount === 1 ? '' : 's'}. 
                    This action cannot be undone and will:
                  </p>
                  <ul className="text-sm text-theme-secondary space-y-1 ml-4">
                    <li>• Revoke all worker tokens immediately</li>
                    <li>• Remove all worker permissions and access</li>
                    <li>• Delete all worker activity history</li>
                    <li>• Cannot be reversed or restored</li>
                  </ul>
                  <p className="text-theme-error text-sm font-medium">
                    Please type "DELETE" to confirm this destructive action.
                  </p>
                </div>
              )}
            </div>

            <div className="flex justify-end space-x-3">
              <button
                onClick={() => setShowConfirm(null)}
                className="px-4 py-2 border border-theme rounded-md text-theme-secondary hover:text-theme-primary transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={() => confirmAction(showConfirm)}
                className={`px-4 py-2 rounded-md transition-colors font-medium ${
                  showConfirm === 'delete'
                    ? 'bg-theme-error text-white hover:bg-theme-error/80'
                    : 'bg-theme-interactive-primary text-white hover:bg-theme-interactive-primary/80'
                }`}
              >
                {showConfirm === 'delete' ? 'Delete Workers' : 'Confirm Action'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Click overlay for closing dropdown */}
      {showActions && (
        <div 
          className="fixed inset-0 z-10"
          onClick={() => setShowActions(false)}
        />
      )}
    </>
  );
};

export default WorkerActions;