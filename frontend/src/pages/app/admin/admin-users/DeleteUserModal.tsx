import React from 'react';
import { Button } from '@/shared/components/ui/Button';
import { Modal } from '@/shared/components/ui/Modal';
import { DeleteUserModalProps } from './types';

export const DeleteUserModal: React.FC<DeleteUserModalProps> = ({
  isOpen,
  userName,
  actionLoading,
  onClose,
  onConfirm
}) => (
  <Modal
    isOpen={isOpen}
    onClose={onClose}
    title="Delete User"
    maxWidth="sm"
  >
    <div className="text-theme-primary">
      Are you sure you want to delete <strong>{userName}</strong>?
      This action cannot be undone.
    </div>
    <div className="flex justify-end space-x-3 mt-6">
      <Button variant="secondary" onClick={onClose}>
        Cancel
      </Button>
      <Button
        variant="danger"
        onClick={onConfirm}
        disabled={actionLoading}
      >
        {actionLoading ? 'Deleting...' : 'Delete User'}
      </Button>
    </div>
  </Modal>
);
