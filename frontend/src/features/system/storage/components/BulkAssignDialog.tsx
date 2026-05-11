import React, { useState } from 'react';
import { useDispatch } from 'react-redux';
import { addNotification } from '@/shared/services/slices/uiSlice';
import type { AppDispatch } from '@/shared/services';
import { storageAssignmentsApi } from '../services/storageAssignmentsApi';
import { EncryptionMode, StorageAssignmentCreateInput } from '../types';

interface Props {
  storageId: string;
  providerType?: string;
  onClose: () => void;
  onCreated: () => void;
}

// Multi-line textarea: one node-instance UUID per line. Designed for fast
// operator workflow (paste list); a richer instance-picker is a follow-up.
export const BulkAssignDialog: React.FC<Props> = ({ storageId, providerType, onClose, onCreated }) => {
  const dispatch = useDispatch<AppDispatch>();
  const [instanceIds, setInstanceIds] = useState('');
  const [mountPathTemplate, setMountPathTemplate] = useState('/mnt/data');
  const [encryptionMode, setEncryptionMode] = useState<EncryptionMode>('inherit');
  const [sdwanNetworkId, setSdwanNetworkId] = useState('');
  const [sdwanVirtualIpId, setSdwanVirtualIpId] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const parsedIds = instanceIds
    .split(/[\s,]+/)
    .map((s) => s.trim())
    .filter(Boolean);

  const handleSubmit = async () => {
    if (parsedIds.length === 0) {
      dispatch(addNotification({ type: 'warning', message: 'No instances provided' }));
      return;
    }

    setSubmitting(true);
    try {
      const assignments: StorageAssignmentCreateInput[] = parsedIds.map((id, idx) => ({
        file_storage_id: storageId,
        node_instance_id: id,
        mount_path: mountPathTemplate.replace('{index}', String(idx + 1)),
        encryption_mode: encryptionMode,
        sdwan_network_id: sdwanNetworkId || undefined,
        sdwan_virtual_ip_id: sdwanVirtualIpId || undefined,
      }));

      const result = await storageAssignmentsApi.bulkCreate(assignments);

      if (result.errors.length > 0) {
        dispatch(
          addNotification({
            type: 'warning',
            message: `Created ${result.created.length} of ${assignments.length} (${result.errors.length} failed)`,
          }),
        );
      } else {
        dispatch(
          addNotification({ type: 'success', message: `Assigned to ${result.created.length} instance(s)` }),
        );
      }
      onCreated();
    } catch (e) {
      dispatch(addNotification({ type: 'error', message: 'Bulk assignment failed' }));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-theme-overlay">
      <div className="bg-theme-surface rounded-lg p-6 w-full max-w-2xl space-y-4">
        <h3 className="text-theme-primary text-lg font-semibold">Assign to instances</h3>

        <label className="block">
          <span className="text-theme-secondary text-xs">Node instance UUIDs (one per line)</span>
          <textarea
            value={instanceIds}
            onChange={(e) => setInstanceIds(e.target.value)}
            rows={6}
            className="mt-1 w-full bg-theme-background-secondary text-theme-primary rounded-md p-2 font-mono text-xs"
            placeholder="0190a3b4-...&#10;0190a3b5-..."
          />
          <span className="text-theme-secondary text-xs">{parsedIds.length} instance(s) parsed</span>
        </label>

        <label className="block">
          <span className="text-theme-secondary text-xs">Mount path</span>
          <input
            value={mountPathTemplate}
            onChange={(e) => setMountPathTemplate(e.target.value)}
            className="mt-1 w-full bg-theme-background-secondary text-theme-primary rounded-md p-2 font-mono text-sm"
          />
          <span className="text-theme-secondary text-xs">Use {'{index}'} to suffix per-instance.</span>
        </label>

        <div className="grid grid-cols-2 gap-4">
          <label className="block">
            <span className="text-theme-secondary text-xs">Encryption</span>
            <select
              value={encryptionMode}
              onChange={(e) => setEncryptionMode(e.target.value as EncryptionMode)}
              className="mt-1 w-full bg-theme-background-secondary text-theme-primary rounded-md p-2 text-sm"
            >
              <option value="inherit">Inherit (provider default)</option>
              <option value="none">None</option>
              <option value="fscrypt">fscrypt</option>
              <option value="luks">LUKS</option>
              <option value="client_side_aes">Client-side AES</option>
            </select>
          </label>

          <label className="block">
            <span className="text-theme-secondary text-xs">SDWAN network UUID</span>
            <input
              value={sdwanNetworkId}
              onChange={(e) => setSdwanNetworkId(e.target.value)}
              className="mt-1 w-full bg-theme-background-secondary text-theme-primary rounded-md p-2 font-mono text-xs"
              placeholder="optional"
            />
          </label>
        </div>

        <label className="block">
          <span className="text-theme-secondary text-xs">SDWAN VIP UUID</span>
          <input
            value={sdwanVirtualIpId}
            onChange={(e) => setSdwanVirtualIpId(e.target.value)}
            className="mt-1 w-full bg-theme-background-secondary text-theme-primary rounded-md p-2 font-mono text-xs"
            placeholder="optional"
          />
        </label>

        {providerType && (
          <p className="text-theme-secondary text-xs">
            Provider: <span className="font-mono">{providerType}</span>
          </p>
        )}

        <div className="flex justify-end space-x-2 pt-2">
          <button
            type="button"
            onClick={onClose}
            className="px-3 py-1.5 rounded-md bg-theme-surface-muted text-theme-primary text-sm"
            disabled={submitting}
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleSubmit}
            disabled={submitting || parsedIds.length === 0}
            className="px-3 py-1.5 rounded-md bg-theme-accent text-theme-on-accent text-sm disabled:opacity-50"
          >
            {submitting ? 'Assigning…' : `Assign to ${parsedIds.length}`}
          </button>
        </div>
      </div>
    </div>
  );
};
