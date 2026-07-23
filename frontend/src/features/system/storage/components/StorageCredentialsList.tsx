import React, { useCallback, useEffect, useState } from 'react';
import { useDispatch } from 'react-redux';
import { useArmedConfirm } from '@/shared/hooks/useArmedConfirm';
import { addNotification } from '@/shared/services/slices/uiSlice';
import type { AppDispatch } from '@/shared/services';
import { storageCredentialsApi } from '../services/storageCredentialsApi';
import { StorageCredential } from '../types';

// Credential metadata list for one storage assignment (IMP-b2c32f1e3038).
// Shows kind/status/rotation cadence and offers per-credential rotation.
// SECURITY: the API never returns credential material — rotation swaps the
// Vault-held secret and hands back a metadata row only, so there is nothing
// secret to display or copy here by design.

interface Props {
  assignmentId: string;
  /** The assignment's active_credential_id — marks the credential in use. */
  activeCredentialId?: string | null;
  /** system.storage.assignments.rotate_credential */
  canRotate: boolean;
}

const STATUS_TONE: Record<string, string> = {
  active: 'bg-theme-success-bg text-theme-success-fg',
  pending: 'bg-theme-warning-bg text-theme-warning-fg',
  retired: 'bg-theme-background-muted text-theme-secondary',
  revoked: 'bg-theme-danger-bg text-theme-error-fg',
};

export const StorageCredentialsList: React.FC<Props> = ({
  assignmentId,
  activeCredentialId,
  canRotate,
}) => {
  const dispatch = useDispatch<AppDispatch>();
  const [credentials, setCredentials] = useState<StorageCredential[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      // Paginated endpoint (default 20/page) — a long rotation history would
      // otherwise silently truncate the drill-down.
      const response = await storageCredentialsApi.list({
        storage_assignment_id: assignmentId,
        per_page: 100,
      });
      setCredentials(response.credentials);
    } catch {
      dispatch(addNotification({ type: 'error', message: 'Failed to load credentials' }));
    } finally {
      setLoading(false);
    }
  }, [assignmentId, dispatch]);

  useEffect(() => {
    load();
  }, [load]);

  if (loading) {
    return <p className="text-theme-secondary text-xs py-2">Loading credentials…</p>;
  }

  if (credentials.length === 0) {
    return (
      <p className="text-theme-secondary text-xs py-2">
        No credentials issued for this assignment yet.
      </p>
    );
  }

  return (
    <table className="w-full text-xs">
      <thead className="text-theme-secondary uppercase">
        <tr>
          <th className="text-left py-1.5 px-2">Kind</th>
          <th className="text-left py-1.5 px-2">Status</th>
          <th className="text-left py-1.5 px-2">Expires</th>
          <th className="text-left py-1.5 px-2">Last rotated</th>
          <th className="text-left py-1.5 px-2">Actions</th>
        </tr>
      </thead>
      <tbody>
        {credentials.map((credential) => (
          <CredentialRow
            key={credential.id}
            credential={credential}
            inUse={credential.id === activeCredentialId}
            canRotate={canRotate}
            onChange={load}
          />
        ))}
      </tbody>
    </table>
  );
};

const CredentialRow: React.FC<{
  credential: StorageCredential;
  inUse: boolean;
  canRotate: boolean;
  onChange: () => void;
}> = ({ credential, inUse, canRotate, onChange }) => {
  const dispatch = useDispatch<AppDispatch>();
  const tone = STATUS_TONE[credential.status] || 'bg-theme-background-muted text-theme-secondary';

  const handleRotate = async () => {
    try {
      await storageCredentialsApi.rotate(credential.id);
      dispatch(addNotification({
        type: 'success',
        message: 'Credential rotated — the node agent picks up the new material from Vault at next mount',
      }));
      onChange();
    } catch {
      dispatch(addNotification({ type: 'error', message: 'Rotate failed' }));
    }
  };

  const { armed, trigger } = useArmedConfirm(handleRotate);

  return (
    <tr className="border-t border-theme">
      <td className="py-1.5 px-2 text-theme-primary font-mono">{credential.kind}</td>
      <td className="py-1.5 px-2 space-x-1">
        <span className={`inline-block px-2 py-0.5 rounded ${tone}`}>{credential.status}</span>
        {inUse && (
          <span className="inline-block px-2 py-0.5 rounded bg-theme-info-bg text-theme-info-fg">
            in use
          </span>
        )}
        {credential.needs_rotation && (
          <span className="inline-block px-2 py-0.5 rounded bg-theme-warning-bg text-theme-warning-fg">
            needs rotation
          </span>
        )}
      </td>
      <td className="py-1.5 px-2 text-theme-secondary">
        {credential.expires_at ? new Date(credential.expires_at).toLocaleString() : '—'}
      </td>
      <td className="py-1.5 px-2 text-theme-secondary">
        {credential.last_rotated_at ? new Date(credential.last_rotated_at).toLocaleString() : '—'}
      </td>
      <td className="py-1.5 px-2">
        {canRotate && (
          <button
            type="button"
            onClick={trigger}
            className={`text-xs underline ${armed ? 'text-theme-danger-fg font-semibold' : 'text-theme-interactive-primary'}`}
          >
            {armed ? 'Click to confirm' : 'Rotate'}
          </button>
        )}
      </td>
    </tr>
  );
};
