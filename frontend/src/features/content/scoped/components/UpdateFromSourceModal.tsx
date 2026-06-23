import React, { useEffect, useState, useCallback } from 'react';
import { ArrowDownToLine, Check, AlertTriangle } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type {
  UpdateFromSourcePreview,
  ConflictResolutions,
} from '../types';

/** Render an arbitrary field value (string / number / object) for diff display. */
function formatValue(value: unknown): string {
  if (value === null || value === undefined) return '—';
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

/** Humanize a snake_case field name for labels. */
function fieldLabel(field: string): string {
  return field.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}

type ConflictChoice = 'mine' | 'origin';

interface UpdateFromSourceModalProps {
  isOpen: boolean;
  onClose: () => void;
  /** Display title for the item being updated. */
  itemName?: string;
  /** Fetch the 3-way preview (e.g. `() => skillsApi.updateFromSourcePreview(id)`). */
  fetchPreview: () => Promise<UpdateFromSourcePreview>;
  /** Apply the merge with optional conflict resolutions. */
  applyUpdate: (resolutions: ConflictResolutions) => Promise<unknown>;
  /** Called after a successful merge so the caller can refresh. */
  onApplied?: () => void;
}

/**
 * Modal for refreshing an account copy from its platform origin. Shows the
 * fields that auto-pull, then a per-conflict chooser (Keep mine / Take origin)
 * for fields both sides changed, and POSTs the chosen resolutions.
 */
export const UpdateFromSourceModal: React.FC<UpdateFromSourceModalProps> = ({
  isOpen,
  onClose,
  itemName,
  fetchPreview,
  applyUpdate,
  onApplied,
}) => {
  const { showNotification } = useNotifications();
  const [loading, setLoading] = useState(false);
  const [applying, setApplying] = useState(false);
  const [preview, setPreview] = useState<UpdateFromSourcePreview | null>(null);
  const [choices, setChoices] = useState<Record<string, ConflictChoice>>({});

  const loadPreview = useCallback(async () => {
    setLoading(true);
    setPreview(null);
    setChoices({});
    try {
      const result = await fetchPreview();
      setPreview(result);
    } catch {
      showNotification('Failed to load update preview', 'error');
      setPreview(null);
    } finally {
      setLoading(false);
    }
  }, [fetchPreview, showNotification]);

  useEffect(() => {
    if (isOpen) loadPreview();
  }, [isOpen, loadPreview]);

  const conflictFields = preview ? Object.keys(preview.conflicts) : [];
  const allResolved = conflictFields.every((f) => choices[f] != null);

  const handleApply = async () => {
    if (!preview) return;
    // Only conflicts where the user picked the origin value need an explicit
    // resolution; "Keep mine" is the default (no change for that field).
    const resolutions: ConflictResolutions = {};
    for (const field of conflictFields) {
      if (choices[field] === 'origin') {
        resolutions[field] = preview.conflicts[field].base;
      }
    }
    setApplying(true);
    try {
      await applyUpdate(resolutions);
      showNotification('Updated from baseline', 'success');
      onApplied?.();
      onClose();
    } catch {
      showNotification('Failed to apply update', 'error');
    } finally {
      setApplying(false);
    }
  };

  const nothingToDo =
    preview != null &&
    !preview.error &&
    preview.pulled.length === 0 &&
    conflictFields.length === 0;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Update from source"
      subtitle={itemName ? `Refresh "${itemName}" from the platform baseline` : undefined}
      icon={<ArrowDownToLine className="w-4 h-4" />}
      maxWidth="2xl"
      footer={
        <>
          <Button variant="secondary" onClick={onClose} disabled={applying}>
            {nothingToDo || preview?.error ? 'Close' : 'Cancel'}
          </Button>
          {preview && !preview.error && !nothingToDo && (
            <Button
              variant="primary"
              onClick={handleApply}
              loading={applying}
              disabled={!allResolved}
            >
              Apply update
            </Button>
          )}
        </>
      }
    >
      {loading ? (
        <LoadingSpinner className="py-8" />
      ) : !preview ? (
        <p className="text-sm text-theme-secondary py-4">No preview available.</p>
      ) : preview.error ? (
        <div className="flex items-start gap-2 py-4 text-sm text-theme-secondary">
          <AlertTriangle className="w-4 h-4 text-theme-warning-fg mt-0.5 flex-shrink-0" />
          <span>This item has no origin to update from.</span>
        </div>
      ) : nothingToDo ? (
        <div className="flex items-center gap-2 py-4 text-sm text-theme-secondary">
          <Check className="w-4 h-4 text-theme-success-fg flex-shrink-0" />
          <span>Already up to date with the baseline. Nothing to apply.</span>
        </div>
      ) : (
        <div className="space-y-6">
          {/* Auto-pulled fields */}
          {preview.pulled.length > 0 && (
            <section>
              <h4 className="text-sm font-medium text-theme-primary mb-2 flex items-center gap-1.5">
                <ArrowDownToLine className="w-4 h-4 text-theme-info-fg" />
                Auto-updated from baseline
              </h4>
              <p className="text-xs text-theme-tertiary mb-2">
                These fields changed in the baseline and will be pulled in (you had
                not edited them).
              </p>
              <div className="flex flex-wrap gap-1.5">
                {preview.pulled.map((field) => (
                  <span
                    key={field}
                    className="px-2 py-0.5 text-xs rounded-full bg-theme-info-bg text-theme-info-fg"
                  >
                    {fieldLabel(field)}
                  </span>
                ))}
              </div>
            </section>
          )}

          {/* Conflicts requiring a choice */}
          {conflictFields.length > 0 && (
            <section>
              <h4 className="text-sm font-medium text-theme-primary mb-2 flex items-center gap-1.5">
                <AlertTriangle className="w-4 h-4 text-theme-warning-fg" />
                Conflicts — choose per field
              </h4>
              <p className="text-xs text-theme-tertiary mb-3">
                You and the baseline both changed these. Pick which value to keep.
              </p>
              <div className="space-y-4">
                {conflictFields.map((field) => {
                  const conflict = preview.conflicts[field];
                  const choice = choices[field];
                  return (
                    <div
                      key={field}
                      className="border border-theme rounded-lg p-3 bg-theme-surface"
                    >
                      <div className="text-sm font-medium text-theme-primary mb-2">
                        {fieldLabel(field)}
                      </div>
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                        <button
                          type="button"
                          onClick={() => setChoices((c) => ({ ...c, [field]: 'mine' }))}
                          className={`text-left rounded-md border p-2 transition-colors ${
                            choice === 'mine'
                              ? 'border-theme-interactive-primary bg-theme-surface-selected'
                              : 'border-theme hover:border-theme-interactive-primary'
                          }`}
                        >
                          <div className="flex items-center justify-between mb-1">
                            <span className="text-xs font-medium text-theme-secondary">
                              Keep mine
                            </span>
                            {choice === 'mine' && (
                              <Check className="w-3.5 h-3.5 text-theme-interactive-primary" />
                            )}
                          </div>
                          <pre className="text-xs text-theme-primary whitespace-pre-wrap break-words max-h-32 overflow-y-auto">
                            {formatValue(conflict.yours)}
                          </pre>
                        </button>
                        <button
                          type="button"
                          onClick={() => setChoices((c) => ({ ...c, [field]: 'origin' }))}
                          className={`text-left rounded-md border p-2 transition-colors ${
                            choice === 'origin'
                              ? 'border-theme-interactive-primary bg-theme-surface-selected'
                              : 'border-theme hover:border-theme-interactive-primary'
                          }`}
                        >
                          <div className="flex items-center justify-between mb-1">
                            <span className="text-xs font-medium text-theme-secondary">
                              Take origin
                            </span>
                            {choice === 'origin' && (
                              <Check className="w-3.5 h-3.5 text-theme-interactive-primary" />
                            )}
                          </div>
                          <pre className="text-xs text-theme-primary whitespace-pre-wrap break-words max-h-32 overflow-y-auto">
                            {formatValue(conflict.base)}
                          </pre>
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
              {!allResolved && (
                <p className="text-xs text-theme-warning-fg mt-3">
                  Resolve all conflicts to apply the update.
                </p>
              )}
            </section>
          )}
        </div>
      )}
    </Modal>
  );
};

export default UpdateFromSourceModal;
