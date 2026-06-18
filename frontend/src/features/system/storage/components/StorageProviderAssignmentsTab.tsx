import React, { useCallback, useEffect, useState } from 'react';
import { useDispatch } from 'react-redux';
import { useAuth } from '@/shared/hooks/useAuth';
import { useArmedConfirm } from '@/shared/hooks/useArmedConfirm';
import { addNotification } from '@/shared/services/slices/uiSlice';
import type { AppDispatch } from '@/shared/services';
import { storageAssignmentsApi } from '../services/storageAssignmentsApi';
import {
  StorageAssignment,
  StorageAssignmentStatus,
} from '../types';
import { BulkAssignDialog } from './BulkAssignDialog';

interface Props {
  /** The FileManagement::Storage UUID this tab belongs to. */
  storageId: string;
  /** The storage provider type, used to render type-aware help text. */
  providerType?: string;
}

const STATUS_TONE: Record<StorageAssignmentStatus, string> = {
  pending: 'bg-theme-warning-bg text-theme-warning-fg',
  provisioning: 'bg-theme-warning-bg text-theme-warning-fg',
  mounted: 'bg-theme-success-bg text-theme-success-fg',
  degraded: 'bg-theme-warning-bg text-theme-warning-fg',
  unmounting: 'bg-theme-info-bg text-theme-info-fg',
  failed: 'bg-theme-danger-bg text-theme-error-fg',
  disabled: 'bg-theme-background-muted text-theme-secondary',
};

export const StorageProviderAssignmentsTab: React.FC<Props> = ({ storageId, providerType }) => {
  const dispatch = useDispatch<AppDispatch>();
  const { currentUser } = useAuth();
  const canAssign = currentUser?.permissions?.includes('system.storage.assignments.create');
  const canRotate = currentUser?.permissions?.includes('system.storage.assignments.rotate_credential');
  const canDelete = currentUser?.permissions?.includes('system.storage.assignments.delete');

  const [assignments, setAssignments] = useState<StorageAssignment[]>([]);
  const [loading, setLoading] = useState(true);
  const [showBulkDialog, setShowBulkDialog] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const response = await storageAssignmentsApi.list({ file_storage_id: storageId });
      setAssignments(response.assignments);
    } catch (e) {
      dispatch(addNotification({ type: 'error', message: 'Failed to load assignments' }));
    } finally {
      setLoading(false);
    }
  }, [storageId, dispatch]);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <div className="bg-theme-surface rounded-lg p-6 space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-theme-primary text-lg font-semibold">Assignments</h3>
        {canAssign && (
          <button
            type="button"
            onClick={() => setShowBulkDialog(true)}
            className="px-3 py-1.5 rounded-md bg-theme-interactive-primary text-theme-interactive-primary text-sm"
          >
            Assign to instances
          </button>
        )}
      </div>

      {loading ? (
        <p className="text-theme-secondary text-sm">Loading…</p>
      ) : assignments.length === 0 ? (
        <p className="text-theme-secondary text-sm">No assignments yet. Use “Assign to instances” to attach this storage.</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="text-theme-secondary text-xs uppercase">
              <tr>
                <th className="text-left py-2 px-2">Instance</th>
                <th className="text-left py-2 px-2">Mount path</th>
                <th className="text-left py-2 px-2">Encryption</th>
                <th className="text-left py-2 px-2">Status</th>
                <th className="text-left py-2 px-2">Last status</th>
                <th className="text-left py-2 px-2">Actions</th>
              </tr>
            </thead>
            <tbody>
              {assignments.map((a) => (
                <AssignmentRow
                  key={a.id}
                  assignment={a}
                  canRotate={!!canRotate}
                  canDelete={!!canDelete}
                  onChange={load}
                />
              ))}
            </tbody>
          </table>
        </div>
      )}

      {showBulkDialog && (
        <BulkAssignDialog
          storageId={storageId}
          providerType={providerType}
          onClose={() => setShowBulkDialog(false)}
          onCreated={() => {
            setShowBulkDialog(false);
            load();
          }}
        />
      )}
    </div>
  );
};

const AssignmentRow: React.FC<{
  assignment: StorageAssignment;
  canRotate: boolean;
  canDelete: boolean;
  onChange: () => void;
}> = ({ assignment, canRotate, canDelete, onChange }) => {
  const dispatch = useDispatch<AppDispatch>();
  const tone = STATUS_TONE[assignment.status] || 'bg-theme-background-muted text-theme-secondary';

  const handleRotate = async () => {
    try {
      await storageAssignmentsApi.rotateCredential(assignment.id);
      dispatch(addNotification({ type: 'success', message: 'Credential rotated' }));
      onChange();
    } catch (e) {
      dispatch(addNotification({ type: 'error', message: 'Rotate failed' }));
    }
  };

  const handleDelete = async () => {
    try {
      await storageAssignmentsApi.destroy(assignment.id);
      dispatch(addNotification({ type: 'success', message: 'Assignment deleted' }));
      onChange();
    } catch (e) {
      dispatch(addNotification({ type: 'error', message: 'Delete failed' }));
    }
  };

  const { armed, trigger } = useArmedConfirm(handleDelete);

  return (
    <tr className="border-t border-theme">
      <td className="py-2 px-2 text-theme-primary font-mono text-xs">{assignment.node_instance_id.slice(0, 8)}</td>
      <td className="py-2 px-2 text-theme-primary">{assignment.mount_path}</td>
      <td className="py-2 px-2 text-theme-secondary">{assignment.effective_encryption_mode || assignment.encryption_mode}</td>
      <td className="py-2 px-2">
        <span className={`inline-block px-2 py-0.5 rounded text-xs ${tone}`}>{assignment.status}</span>
      </td>
      <td className="py-2 px-2 text-theme-secondary text-xs">
        {assignment.last_status_at ? new Date(assignment.last_status_at).toLocaleString() : '—'}
      </td>
      <td className="py-2 px-2 space-x-2">
        {canRotate && (
          <button
            type="button"
            onClick={handleRotate}
            className="text-theme-interactive-primary text-xs underline"
          >
            Rotate
          </button>
        )}
        {canDelete && (
          <button
            type="button"
            onClick={trigger}
            className={`text-xs underline ${armed ? 'text-theme-danger-fg font-semibold' : 'text-theme-danger-fg'}`}
          >
            {armed ? 'Click to confirm' : 'Delete'}
          </button>
        )}
      </td>
    </tr>
  );
};
