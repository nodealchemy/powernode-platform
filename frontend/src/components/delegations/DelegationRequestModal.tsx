import React, { useState } from 'react';
import { DelegationRequest, DELEGATION_PERMISSIONS } from '../../services/delegationApi';

interface DelegationRequestModalProps {
  request: DelegationRequest;
  onClose: () => void;
  onApprove: (requestId: string, note?: string) => void;
  onReject: (requestId: string, reason: string) => void;
}

export const DelegationRequestModal: React.FC<DelegationRequestModalProps> = ({
  request,
  onClose,
  onApprove,
  onReject,
}) => {
  const [action, setAction] = useState<'review' | 'approve' | 'reject'>('review');
  const [note, setNote] = useState('');
  const [rejectReason, setRejectReason] = useState('');

  const formatDate = (date: string) => {
    return new Date(date).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  const getPermissionLabel = (key: string) => {
    const permission = DELEGATION_PERMISSIONS.find(p => p.key === key);
    return permission ? permission.label : key;
  };

  const getPermissionDescription = (key: string) => {
    const permission = DELEGATION_PERMISSIONS.find(p => p.key === key);
    return permission ? permission.description : '';
  };

  const handleApprove = () => {
    onApprove(request.id, note);
  };

  const handleReject = () => {
    if (rejectReason.trim()) {
      onReject(request.id, rejectReason);
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-theme-surface rounded-lg w-full max-w-2xl max-h-[90vh] overflow-hidden">
        <div className="p-6 border-b border-theme">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-xl font-semibold text-theme-primary">Delegation Request</h2>
              <p className="text-theme-secondary mt-1">Review and respond to this access request</p>
            </div>
            <button
              onClick={onClose}
              className="text-theme-secondary hover:text-theme-primary"
            >
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>

        <div className="p-6 overflow-y-auto max-h-[calc(90vh-200px)]">
          {action === 'review' && (
            <div className="space-y-6">
              {/* Request Information */}
              <div className="bg-theme-warning bg-opacity-10 border border-theme-warning border-opacity-30 rounded-lg p-4">
                <div className="flex items-start space-x-3">
                  <span className="text-theme-warning text-xl">⚠️</span>
                  <div>
                    <h3 className="font-medium text-theme-warning">Pending Approval</h3>
                    <p className="text-sm text-theme-warning opacity-80 mt-1">
                      This delegation request requires your approval to grant access.
                    </p>
                  </div>
                </div>
              </div>

              {/* Requester Information */}
              <div>
                <h3 className="text-sm font-medium text-theme-tertiary mb-3">Requested By</h3>
                <div className="bg-theme-background rounded-lg p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="font-medium text-theme-primary">{request.requestedByName}</p>
                      <p className="text-sm text-theme-secondary">{request.requestedByEmail}</p>
                      <p className="text-sm text-theme-tertiary mt-1">
                        From: {request.delegation.sourceAccountName}
                      </p>
                    </div>
                    <div className="text-right">
                      <p className="text-sm text-theme-tertiary">Requested</p>
                      <p className="text-sm text-theme-primary">{formatDate(request.createdAt)}</p>
                    </div>
                  </div>
                </div>
              </div>

              {/* Delegation Details */}
              <div>
                <h3 className="text-sm font-medium text-theme-tertiary mb-3">Delegation Details</h3>
                <div className="bg-theme-background rounded-lg p-4 space-y-4">
                  <div>
                    <p className="text-sm text-theme-tertiary">Name</p>
                    <p className="font-medium text-theme-primary">{request.delegation.name}</p>
                  </div>
                  <div>
                    <p className="text-sm text-theme-tertiary">Description</p>
                    <p className="text-theme-primary">{request.delegation.description}</p>
                  </div>
                  {request.message && (
                    <div>
                      <p className="text-sm text-theme-tertiary">Message from Requester</p>
                      <p className="text-theme-primary italic">"{request.message}"</p>
                    </div>
                  )}
                  {request.delegation.expiresAt && (
                    <div>
                      <p className="text-sm text-theme-tertiary">Expires</p>
                      <p className="text-theme-primary">{formatDate(request.delegation.expiresAt)}</p>
                    </div>
                  )}
                </div>
              </div>

              {/* Requested Permissions */}
              <div>
                <h3 className="text-sm font-medium text-theme-tertiary mb-3">Requested Permissions</h3>
                <div className="space-y-2">
                  {(request.delegation.permissions || []).map((permission) => (
                    <div key={permission} className="bg-theme-background rounded-lg p-3">
                      <div className="flex items-start space-x-3">
                        <span className="text-theme-interactive-primary mt-0.5">🔐</span>
                        <div className="flex-1">
                          <p className="font-medium text-theme-primary">{getPermissionLabel(permission)}</p>
                          <p className="text-sm text-theme-secondary">{getPermissionDescription(permission)}</p>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              {/* Users to be Granted Access */}
              {(request.delegation.users?.length || 0) > 0 && (
                <div>
                  <h3 className="text-sm font-medium text-theme-tertiary mb-3">Users to be Granted Access</h3>
                  <div className="bg-theme-background rounded-lg p-4">
                    <div className="space-y-2">
                      {(request.delegation.users || []).map((user) => (
                        <div key={user.id} className="flex items-center justify-between">
                          <div>
                            <p className="text-theme-primary">{user.name || `${user.firstName || ''} ${user.lastName || ''}`.trim()}</p>
                            <p className="text-sm text-theme-secondary">{user.email}</p>
                          </div>
                          <span className="text-sm text-theme-tertiary">{user.role || 'N/A'}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
              )}
            </div>
          )}

          {action === 'approve' && (
            <div className="space-y-6">
              <div className="bg-theme-success bg-opacity-10 border border-theme-success border-opacity-30 rounded-lg p-4">
                <div className="flex items-start space-x-3">
                  <span className="text-theme-success text-xl">✅</span>
                  <div>
                    <h3 className="font-medium text-theme-success">Approve Delegation Request</h3>
                    <p className="text-sm text-theme-success opacity-80 mt-1">
                      You are about to grant the requested access permissions.
                    </p>
                  </div>
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Approval Note (Optional)
                </label>
                <textarea
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                  className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
                  rows={4}
                  placeholder="Add any notes about this approval..."
                />
              </div>
            </div>
          )}

          {action === 'reject' && (
            <div className="space-y-6">
              <div className="bg-theme-error bg-opacity-10 border border-theme-error border-opacity-30 rounded-lg p-4">
                <div className="flex items-start space-x-3">
                  <span className="text-theme-error text-xl">❌</span>
                  <div>
                    <h3 className="font-medium text-theme-error">Reject Delegation Request</h3>
                    <p className="text-sm text-theme-error opacity-80 mt-1">
                      You are about to deny this access request.
                    </p>
                  </div>
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Rejection Reason <span className="text-theme-error">*</span>
                </label>
                <textarea
                  value={rejectReason}
                  onChange={(e) => setRejectReason(e.target.value)}
                  className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
                  rows={4}
                  placeholder="Please provide a reason for rejecting this request..."
                  required
                />
              </div>
            </div>
          )}
        </div>

        <div className="p-6 border-t border-theme bg-theme-background">
          {action === 'review' && (
            <div className="flex justify-between">
              <button
                onClick={onClose}
                className="btn-theme btn-theme-secondary"
              >
                Close
              </button>
              <div className="space-x-3">
                <button
                  onClick={() => setAction('reject')}
                  className="btn-theme btn-theme-secondary text-theme-error hover:bg-theme-error hover:text-white"
                >
                  Reject
                </button>
                <button
                  onClick={() => setAction('approve')}
                  className="btn-theme btn-theme-primary"
                >
                  Approve
                </button>
              </div>
            </div>
          )}

          {action === 'approve' && (
            <div className="flex justify-between">
              <button
                onClick={() => setAction('review')}
                className="btn-theme btn-theme-secondary"
              >
                Back
              </button>
              <button
                onClick={handleApprove}
                className="btn-theme btn-theme-primary"
              >
                Confirm Approval
              </button>
            </div>
          )}

          {action === 'reject' && (
            <div className="flex justify-between">
              <button
                onClick={() => setAction('review')}
                className="btn-theme btn-theme-secondary"
              >
                Back
              </button>
              <button
                onClick={handleReject}
                disabled={!rejectReason.trim()}
                className="btn-theme btn-theme-primary bg-theme-error hover:bg-theme-error-hover disabled:opacity-50 disabled:cursor-not-allowed"
              >
                Confirm Rejection
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};