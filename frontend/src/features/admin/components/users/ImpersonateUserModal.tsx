import React, { useState, useCallback, useEffect } from 'react';
import { useDispatch } from 'react-redux';
import type { AppDispatch } from '@/shared/services';
import { startImpersonation } from '@/shared/services/slices/authSlice';
import { impersonationApi, UserSummary } from '@/shared/services/account/impersonationApi';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';

interface ImpersonateUserModalProps {
  isOpen: boolean;
  onClose: () => void;
  preselectedUserId?: string;
}

export const ImpersonateUserModal: React.FC<ImpersonateUserModalProps> = ({
  isOpen,
  onClose,
  preselectedUserId
}) => {
  const dispatch = useDispatch<AppDispatch>();
  const [selectedUser, setSelectedUser] = useState<UserSummary | null>(null);
  const [reason, setReason] = useState('');
  const [availableUsers, setAvailableUsers] = useState<UserSummary[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadAvailableUsers = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    
    try {
      const response = await impersonationApi.getImpersonatableUsers();
      if (response.success && response.data) {
        setAvailableUsers(response.data);
      } else {
        throw new Error(response.error || 'Failed to load users');
      }
    } catch (_err) {
      const err = error as { message?: string };
      setError(err.message || 'Failed to load impersonatable users');
    } finally {
      setIsLoading(false);
    }
  }, []);

  // Load available users when modal opens
  useEffect(() => {
    if (isOpen) {
      loadAvailableUsers();
    }
  }, [isOpen, loadAvailableUsers]);

  // Handle preselected user
  useEffect(() => {
    if (preselectedUserId && availableUsers.length > 0) {
      const user = availableUsers.find(u => u.id === preselectedUserId);
      if (user) {
        setSelectedUser(user);
      }
    }
  }, [preselectedUserId, availableUsers]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedUser) return;

    setIsSubmitting(true);
    setError(null);

    try {
      await dispatch(startImpersonation({
        user_id: selectedUser.id,
        reason: reason.trim() || undefined
      })).unwrap();

      onClose();
      resetForm();
      // Refresh the page after successful impersonation start to ensure clean state
      window.location.reload();
    } catch (_err) {
      const err = error as { message?: string };
      setError(err.message || 'Failed to start impersonation');
    } finally {
      setIsSubmitting(false);
    }
  };

  const resetForm = () => {
    setSelectedUser(null);
    setReason('');
    setError(null);
  };

  const handleClose = () => {
    onClose();
    resetForm();
  };

  const getRoleColor = (role: string): string => {
    switch (role.toLowerCase()) {
      case 'admin':
        return 'bg-theme-error bg-opacity-10 text-theme-error';
      case 'manager':
        return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'member':
        return 'bg-theme-info bg-opacity-10 text-theme-info';
      default:
        return 'bg-theme-info bg-opacity-10 text-theme-info';
    }
  };

  return (
    <Modal isOpen={isOpen} onClose={handleClose} maxWidth="lg" title="Impersonate User">
      <div className="p-6">

        <div className="mb-4 p-3 bg-theme-warning-background border border-theme-warning rounded-md">
          <p className="text-sm text-theme-warning">
            <strong>Warning:</strong> Impersonation sessions are limited to 8 hours and all actions will be logged for audit purposes.
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-6">
          {isLoading ? (
            <div className="flex justify-center items-center py-8">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-interactive-primary"></div>
              <span className="ml-2 text-theme-secondary">Loading users...</span>
            </div>
          ) : availableUsers.length > 0 ? (
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Select user to impersonate
              </label>
              <div className="max-h-60 overflow-y-auto border border-theme rounded-md">
                {availableUsers.map((user) => (
                  <div
                    key={user.id}
                    className={`p-3 border-b border-theme last:border-b-0 cursor-pointer transition-colors ${
                      selectedUser?.id === user.id
                        ? 'bg-theme-interactive-background border-theme-interactive-primary'
                        : 'hover:bg-theme-surface-hover'
                    }`}
                    onClick={() => setSelectedUser(user)}
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex-1">
                        <div className="flex items-center space-x-3">
                          <div>
                            <p className="text-sm font-medium text-theme-primary">
                              {user.full_name}
                            </p>
                            <p className="text-sm text-theme-secondary">{user.email}</p>
                            {user.account && (
                              <p className="text-xs text-theme-tertiary">
                                Account: {user.account.name}
                              </p>
                            )}
                            <p className="text-xs text-theme-tertiary">
                              Status: {user.status}
                            </p>
                          </div>
                        </div>
                        <div className="mt-2 flex flex-wrap gap-1">
                          {user.roles && user.roles.length > 0 ? (
                            user.roles.slice(0, 2).map((role, index) => (
                              <span
                                key={index}
                                className={`inline-flex items-center px-2 py-1 rounded-full text-xs ${getRoleColor(role)}`}
                              >
                                {role.replace('.', ' ').replace(/\b\w/g, l => l.toUpperCase())}
                              </span>
                            ))
                          ) : (
                            <span className="inline-flex items-center px-2 py-1 rounded-full text-xs bg-theme-tertiary bg-opacity-10 text-theme-tertiary">
                              No Role
                            </span>
                          )}
                        </div>
                        {user.last_login_at && (
                          <p className="text-xs text-theme-tertiary mt-1">
                            Last login: {new Date(user.last_login_at).toLocaleString()}
                          </p>
                        )}
                      </div>
                      {selectedUser?.id === user.id && (
                        <div className="ml-3">
                          <svg className="w-5 h-5 text-theme-interactive-primary" fill="currentColor" viewBox="0 0 20 20">
                            <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                          </svg>
                        </div>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ) : (
            <div className="text-center py-8">
              <svg className="mx-auto h-12 w-12 text-theme-tertiary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z" />
              </svg>
              <h3 className="mt-2 text-sm font-medium text-theme-primary">No users available</h3>
              <p className="mt-1 text-sm text-theme-secondary">
                There are no users available for impersonation in your account.
              </p>
            </div>
          )}

          {selectedUser && (
            <div>
              <label htmlFor="reason" className="block text-sm font-medium text-theme-primary mb-2">
                Reason for impersonation (optional)
              </label>
              <textarea
                id="reason"
                rows={3}
                className="block w-full border-theme rounded-md shadow-sm focus:ring-theme-focus focus:border-theme-focus sm:text-sm bg-theme-background text-theme-primary"
                placeholder="Enter reason for impersonation..."
                value={reason}
                onChange={(e) => setReason(e.target.value)}
              />
            </div>
          )}

          {error && (
            <div className="p-3 bg-theme-error-background border border-theme-error rounded-md">
              <p className="text-sm text-theme-error">{error}</p>
            </div>
          )}

          <div className="flex justify-end space-x-3">
            <Button
              type="button"
              variant="secondary"
              onClick={handleClose}
            >
              Cancel
            </Button>
            <Button
              type="submit"
              disabled={!selectedUser || isSubmitting}
              loading={isSubmitting}
            >
              {isSubmitting ? 'Starting...' : 'Start Impersonation'}
            </Button>
          </div>
        </form>
      </div>
    </Modal>
  );
};

