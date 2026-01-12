import React, { useState } from 'react';
import {
  TrashIcon,
  ExclamationTriangleIcon,
  ClockIcon,
} from '@heroicons/react/24/outline';
import type { DataDeletionRequest } from '../services/privacyApi';

interface DataDeletionCardProps {
  deletionRequest: DataDeletionRequest | null;
  onRequestDeletion: (options: { deletion_type: string; reason?: string }) => Promise<void>;
  onCancelDeletion: (id: string, reason?: string) => Promise<void>;
  loading?: boolean;
}

export const DataDeletionCard: React.FC<DataDeletionCardProps> = ({
  deletionRequest,
  onRequestDeletion,
  onCancelDeletion,
  loading = false,
}) => {
  const [showConfirm, setShowConfirm] = useState(false);
  const [deletionType, setDeletionType] = useState<'full' | 'anonymize'>('full');
  const [reason, setReason] = useState('');
  const [requesting, setRequesting] = useState(false);

  const handleRequestDeletion = async () => {
    setRequesting(true);
    try {
      await onRequestDeletion({ deletion_type: deletionType, reason });
      setShowConfirm(false);
      setReason('');
    } finally {
      setRequesting(false);
    }
  };

  const handleCancelDeletion = async () => {
    if (!deletionRequest) return;
    await onCancelDeletion(deletionRequest.id);
  };

  // If there's an active deletion request
  if (deletionRequest && ['pending', 'approved', 'processing'].includes(deletionRequest.status)) {
    return (
      <div className="bg-theme-danger/10 dark:bg-theme-danger/20 rounded-lg border border-theme-danger/30 dark:border-theme-danger/50 p-6">
        <div className="flex items-start space-x-3">
          <ExclamationTriangleIcon className="h-6 w-6 text-theme-danger" />
          <div className="flex-1">
            <h3 className="text-lg font-semibold text-theme-danger dark:text-theme-danger">
              Account Deletion Scheduled
            </h3>
            <p className="text-sm text-theme-danger mt-1">
              {deletionRequest.in_grace_period ? (
                <>
                  Your account is scheduled for deletion in{' '}
                  <strong>{deletionRequest.days_until_deletion} days</strong>.
                  You can cancel this request before the grace period ends.
                </>
              ) : (
                'Your deletion request is being processed.'
              )}
            </p>

            {deletionRequest.grace_period_ends_at && (
              <div className="mt-4 p-3 bg-theme-background dark:bg-theme-surface rounded">
                <div className="flex items-center space-x-2 text-sm">
                  <ClockIcon className="h-5 w-5 text-theme-danger" />
                  <span className="text-theme-danger">
                    Grace period ends:{' '}
                    {new Date(deletionRequest.grace_period_ends_at).toLocaleDateString()}
                  </span>
                </div>
              </div>
            )}

            {deletionRequest.can_be_cancelled && (
              <button
                onClick={handleCancelDeletion}
                disabled={loading}
                className="mt-4 px-4 py-2 bg-theme-background dark:bg-theme-surface text-theme-danger border border-theme-danger/40 dark:border-theme-danger/60 rounded-lg hover:bg-theme-danger/10 dark:hover:bg-theme-danger/30 transition-colors"
              >
                Cancel Deletion Request
              </button>
            )}
          </div>
        </div>
      </div>
    );
  }

  // Normal state - show deletion options
  return (
    <div className="bg-theme-surface rounded-lg border border-theme p-6">
      <div className="flex items-center space-x-3 mb-4">
        <TrashIcon className="h-6 w-6 text-theme-danger" />
        <div>
          <h3 className="text-lg font-semibold text-theme-primary">Delete Your Data</h3>
          <p className="text-sm text-theme-secondary">
            Request permanent deletion of your personal data
          </p>
        </div>
      </div>

      {!showConfirm ? (
        <div>
          <p className="text-sm text-theme-secondary mb-4">
            You have the right to request deletion of your personal data under GDPR Article 17.
            This action has a 30-day grace period during which you can cancel.
          </p>
          <button
            onClick={() => setShowConfirm(true)}
            className="px-4 py-2 bg-theme-danger text-white rounded-lg hover:opacity-90 transition-colors"
          >
            Request Data Deletion
          </button>
        </div>
      ) : (
        <div className="space-y-4">
          <div className="p-4 bg-theme-warning/10 dark:bg-theme-warning/20 rounded-lg">
            <div className="flex items-start space-x-3">
              <ExclamationTriangleIcon className="h-5 w-5 text-theme-warning mt-0.5" />
              <div className="text-sm text-theme-warning dark:text-theme-warning">
                <p className="font-medium">Important Notice</p>
                <ul className="mt-2 list-disc list-inside space-y-1">
                  <li>This action cannot be undone after the grace period</li>
                  <li>Some data may be retained for legal compliance</li>
                  <li>You have 30 days to cancel this request</li>
                </ul>
              </div>
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Deletion Type
            </label>
            <div className="space-y-2">
              <label className="flex items-start space-x-3 p-3 bg-theme-background rounded-lg cursor-pointer">
                <input
                  type="radio"
                  name="deletionType"
                  value="full"
                  checked={deletionType === 'full'}
                  onChange={() => setDeletionType('full')}
                  className="mt-1"
                />
                <div>
                  <span className="font-medium text-theme-primary">Full Deletion</span>
                  <p className="text-sm text-theme-secondary">
                    Delete all personal data except legally required records
                  </p>
                </div>
              </label>
              <label className="flex items-start space-x-3 p-3 bg-theme-background rounded-lg cursor-pointer">
                <input
                  type="radio"
                  name="deletionType"
                  value="anonymize"
                  checked={deletionType === 'anonymize'}
                  onChange={() => setDeletionType('anonymize')}
                  className="mt-1"
                />
                <div>
                  <span className="font-medium text-theme-primary">Anonymization</span>
                  <p className="text-sm text-theme-secondary">
                    Remove identifying information but keep anonymous records
                  </p>
                </div>
              </label>
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Reason (Optional)
            </label>
            <textarea
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Help us improve by sharing why you're leaving..."
              className="w-full px-3 py-2 bg-theme-background border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-red-500"
              rows={3}
            />
          </div>

          <div className="flex items-center space-x-3 pt-2">
            <button
              onClick={handleRequestDeletion}
              disabled={requesting || loading}
              className="px-4 py-2 bg-theme-danger text-white rounded-lg hover:opacity-90 transition-colors disabled:opacity-50"
            >
              {requesting ? 'Submitting...' : 'Confirm Deletion Request'}
            </button>
            <button
              onClick={() => setShowConfirm(false)}
              className="px-4 py-2 bg-theme-background text-theme-primary border border-theme rounded-lg hover:bg-theme-surface transition-colors"
            >
              Cancel
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

export default DataDeletionCard;
