import React, { useState, useCallback, useEffect } from 'react';
import { useDispatch } from 'react-redux';
import type { AppDispatch } from '../../store';
import { startImpersonation } from '../../store/slices/authSlice';
import { impersonationApi, UserSummary } from '../../services/impersonationApi';
import Modal from '../ui/Modal';
import Button from '../ui/Button';

interface ImpersonateUserModalProps {
  isOpen: boolean;
  onClose: () => void;
  preselectedUserId?: string;
}

const ImpersonateUserModal: React.FC<ImpersonateUserModalProps> = ({
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
    } catch (error: any) {
      setError(error.message || 'Failed to load impersonatable users');
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
    } catch (error: any) {
      setError(error.message || 'Failed to start impersonation');
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
      case 'owner':
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

        <div className="mb-4 p-3 bg-orange-50 border border-orange-200 rounded-md">
          <p className="text-sm text-orange-800">
            <strong>Warning:</strong> Impersonation sessions are limited to 8 hours and all actions will be logged for audit purposes.
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-6">
          {isLoading ? (
            <div className="flex justify-center items-center py-8">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
              <span className="ml-2 text-gray-500">Loading users...</span>
            </div>
          ) : availableUsers.length > 0 ? (
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Select user to impersonate
              </label>
              <div className="max-h-60 overflow-y-auto border border-gray-200 rounded-md">
                {availableUsers.map((user) => (
                  <div
                    key={user.id}
                    className={`p-3 border-b border-gray-100 last:border-b-0 cursor-pointer transition-colors ${
                      selectedUser?.id === user.id
                        ? 'bg-blue-50 border-blue-200'
                        : 'hover:bg-gray-50'
                    }`}
                    onClick={() => setSelectedUser(user)}
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex-1">
                        <div className="flex items-center space-x-3">
                          <div>
                            <p className="text-sm font-medium text-gray-900">
                              {user.full_name}
                            </p>
                            <p className="text-sm text-gray-500">{user.email}</p>
                            {user.account && (
                              <p className="text-xs text-gray-400">
                                Account: {user.account.name}
                              </p>
                            )}
                            <p className="text-xs text-gray-400">
                              Status: {user.status}
                            </p>
                          </div>
                        </div>
                        <div className="mt-2 flex flex-wrap gap-1">
                          <span
                            className={`inline-flex items-center px-2 py-1 rounded-full text-xs ${getRoleColor(user.role)}`}
                          >
                            {user.role.charAt(0).toUpperCase() + user.role.slice(1)}
                          </span>
                        </div>
                        {user.last_login_at && (
                          <p className="text-xs text-gray-400 mt-1">
                            Last login: {new Date(user.last_login_at).toLocaleString()}
                          </p>
                        )}
                      </div>
                      {selectedUser?.id === user.id && (
                        <div className="ml-3">
                          <svg className="w-5 h-5 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
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
              <svg className="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z" />
              </svg>
              <h3 className="mt-2 text-sm font-medium text-gray-900">No users available</h3>
              <p className="mt-1 text-sm text-gray-500">
                There are no users available for impersonation in your account.
              </p>
            </div>
          )}

          {selectedUser && (
            <div>
              <label htmlFor="reason" className="block text-sm font-medium text-gray-700 mb-2">
                Reason for impersonation (optional)
              </label>
              <textarea
                id="reason"
                rows={3}
                className="block w-full border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                placeholder="Enter reason for impersonation..."
                value={reason}
                onChange={(e) => setReason(e.target.value)}
              />
            </div>
          )}

          {error && (
            <div className="p-3 bg-red-50 border border-red-200 rounded-md">
              <p className="text-sm text-red-800">{error}</p>
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

export default ImpersonateUserModal;