import React from 'react';
import { AlertTriangle, X } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

interface ConfirmDeleteModalProps {
  isOpen: boolean;
  onClose: () => void;
  onConfirm: () => void;
  title?: string;
  message?: string;
  itemName?: string;
  itemType?: string;
  isDeleting?: boolean;
  confirmLabel?: string;
  cancelLabel?: string;
}

/**
 * ConfirmDeleteModal - Reusable confirmation dialog for delete operations
 *
 * @example
 * <ConfirmDeleteModal
 *   isOpen={showDeleteConfirm}
 *   onClose={() => setShowDeleteConfirm(false)}
 *   onConfirm={handleDelete}
 *   itemType="Platform"
 *   itemName={platformToDelete?.name}
 *   isDeleting={deleting}
 * />
 */
export const ConfirmDeleteModal: React.FC<ConfirmDeleteModalProps> = ({
  isOpen,
  onClose,
  onConfirm,
  title,
  message,
  itemName,
  itemType = 'item',
  isDeleting = false,
  confirmLabel = 'Delete',
  cancelLabel = 'Cancel'
}) => {
  if (!isOpen) return null;

  const displayTitle = title || `Delete ${itemType}`;
  const displayMessage = message || (
    itemName
      ? `Are you sure you want to delete "${itemName}"? This action cannot be undone.`
      : `Are you sure you want to delete this ${itemType.toLowerCase()}? This action cannot be undone.`
  );

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      <div
        className="fixed inset-0 bg-black/50 transition-opacity"
        onClick={onClose}
      />
      <div className="flex min-h-full items-center justify-center p-4">
        <div className="relative w-full max-w-md bg-theme-surface rounded-lg shadow-xl">
          {/* Header */}
          <div className="flex items-center justify-between p-4 border-b border-theme">
            <div className="flex items-center gap-3">
              <div className="flex items-center justify-center w-10 h-10 rounded-full bg-theme-error-fg/10">
                <AlertTriangle className="w-5 h-5 text-theme-error-fg" />
              </div>
              <h3 className="text-lg font-semibold text-theme-primary">
                {displayTitle}
              </h3>
            </div>
            <Button variant="ghost" size="sm" onClick={onClose} disabled={isDeleting}>
              <X className="w-5 h-5" />
            </Button>
          </div>

          {/* Body */}
          <div className="p-4">
            <p className="text-theme-secondary">
              {displayMessage}
            </p>
          </div>

          {/* Footer */}
          <div className="flex justify-end gap-3 p-4 border-t border-theme">
            <Button
              variant="outline"
              onClick={onClose}
              disabled={isDeleting}
            >
              {cancelLabel}
            </Button>
            <Button
              variant="danger"
              onClick={onConfirm}
              disabled={isDeleting}
            >
              {isDeleting ? (
                <>
                  <LoadingSpinner size="sm" className="mr-2" />
                  Deleting...
                </>
              ) : (
                confirmLabel
              )}
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ConfirmDeleteModal;
