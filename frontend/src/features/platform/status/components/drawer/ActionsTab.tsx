import React, { useState } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { ConfirmationModal } from '@/shared/components/ui/ConfirmationModal';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotification } from '@/shared/hooks/useNotification';
import { logger } from '@/shared/utils/logger';
import { runComponentAction } from '@/features/platform/status/api/platformStatusApi';
import type { ComponentAction } from '@/shared/types/platformStatus';

// Buttons rendered FROM DATA (design §4.4). Core learns nothing kind-specific:
// a contributor declares `{key, label, method, path, permission, destructive,
// confirm}` and this panel renders a button that sends exactly that. "Cordon
// this node" is a contributor change in an extension and no edit here.
//
// ── THE PERMISSION CHECK HERE IS A COURTESY, NOT THE GATE ──────────────────
//
// A button whose `permission` the viewer lacks is not rendered — that stops an
// operator clicking something that will refuse, and it is all it does. The real
// gate is the door the action names, which checks the same permission again
// server-side. Holding `platform.status.read` authorizes neither: it buys the
// picture, never the actuation. If this file's filter were ever deleted the
// consequence would be a refused request, not an unauthorized write — and the
// spec asserts the filter both ways so that stays true by test rather than by
// hope.
//
// ── A DESTRUCTIVE ACTION'S REASON TRAVELS WITH THE REQUEST ─────────────────
//
// When `confirm.requires_reason` is set the confirm button stays disabled until
// a reason is typed, and the reason is sent to the door so the far side can
// audit WHY rather than only what. `confirmDisabled` on the shared modal is the
// mechanism; a modal that let you confirm with an empty box would make the
// prompt decorative.

interface PendingAction {
  action: ComponentAction;
  reason: string;
}

export interface ActionsTabProps {
  actions: ComponentAction[];
  /** Component name, for the confirmation copy and the notification. */
  componentName: string;
  /** Re-read the drawer after a successful action, so it shows the result. */
  onCompleted?: () => void;
}

export const ActionsTab: React.FC<ActionsTabProps> = ({
  actions,
  componentName,
  onCompleted,
}) => {
  const { hasPermission } = usePermissions();
  const { showNotification } = useNotification();
  const [pending, setPending] = useState<PendingAction | null>(null);
  const [running, setRunning] = useState(false);

  const permitted = actions.filter((action) => hasPermission(action.permission));

  const execute = async (action: ComponentAction, reason: string) => {
    setRunning(true);
    try {
      await runComponentAction(action, { reason: reason.trim() || undefined });
      // Global notifications only — no local success banner (frontend
      // convention), so the same success reads the same everywhere.
      showNotification(`${action.label} requested for ${componentName}.`, 'success');
      setPending(null);
      onCompleted?.();
    } catch (e) {
      const message = e instanceof Error ? e.message : 'The action failed.';
      showNotification(`${action.label} failed: ${message}`, 'error');
      logger.error('[PlatformStatus] action failed', e);
    } finally {
      setRunning(false);
    }
  };

  const start = (action: ComponentAction) => {
    if (action.confirm) {
      setPending({ action, reason: '' });
      return;
    }
    void execute(action, '');
  };

  if (actions.length === 0) {
    return (
      <p className="text-sm text-theme-secondary">
        This component declares no actions. Its contributor has not bound any, which is not the same
        as you lacking permission for them.
      </p>
    );
  }

  if (permitted.length === 0) {
    // The two empty states are DIFFERENT and are said differently. "There is
    // nothing to do here" and "there are things to do and you may not do them"
    // send an operator to different places — the second to whoever grants
    // permissions.
    return (
      <p className="text-sm text-theme-secondary">
        This component declares {actions.length} action{actions.length === 1 ? '' : 's'}, none of
        which your permissions allow. Ask an administrator if you need one of them.
      </p>
    );
  }

  const requiresReason = pending?.action.confirm?.requires_reason === true;
  const reasonMissing = requiresReason && pending.reason.trim().length === 0;

  return (
    <div className="flex flex-col gap-3">
      {permitted.map((action) => (
        <div
          key={action.key}
          data-action-key={action.key}
          className="flex flex-wrap items-center justify-between gap-2 rounded-md border border-theme p-3"
        >
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <span className="text-sm text-theme-primary">{action.label}</span>
              {action.destructive && (
                <Badge variant="danger" size="xs" >
                  destructive
                </Badge>
              )}
            </div>
            <code
              className="text-xs text-theme-tertiary"
              title="The permission this action names. Checked here to decide whether to show the button, and again by the door it calls."
            >
              {action.permission}
            </code>
          </div>
          <Button
            variant={action.destructive ? 'danger' : 'secondary'}
            size="sm"
            onClick={() => start(action)}
            disabled={running}
          >
            {action.label}
          </Button>
        </div>
      ))}

      {actions.length > permitted.length && (
        <p className="text-xs text-theme-tertiary">
          {actions.length - permitted.length} further action
          {actions.length - permitted.length === 1 ? ' is' : 's are'} declared but hidden: your
          permissions do not cover {actions.length - permitted.length === 1 ? 'it' : 'them'}.
        </p>
      )}

      {pending && (
        <ConfirmationModal
          isOpen
          onClose={() => setPending(null)}
          onConfirm={() => void execute(pending.action, pending.reason)}
          title={pending.action.label}
          variant={pending.action.destructive ? 'danger' : 'warning'}
          confirmLabel={pending.action.label}
          loading={running}
          confirmDisabled={reasonMissing}
          message={
            <div className="flex flex-col gap-3">
              <p className="text-sm">{pending.action.confirm?.prompt}</p>
              <p className="text-xs text-theme-tertiary">
                {pending.action.method} {pending.action.path}
              </p>
              {requiresReason && (
                <label className="flex flex-col gap-1 text-left">
                  <span className="text-xs text-theme-tertiary">
                    Reason (required — it travels with the request and is audited)
                  </span>
                  <textarea
                    aria-label="Reason"
                    rows={3}
                    value={pending.reason}
                    onChange={(e) => setPending({ ...pending, reason: e.target.value })}
                    className="rounded-md border border-theme bg-theme-surface text-theme-primary px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-theme-info-fg"
                  />
                </label>
              )}
            </div>
          }
        />
      )}
    </div>
  );
};

export default ActionsTab;
