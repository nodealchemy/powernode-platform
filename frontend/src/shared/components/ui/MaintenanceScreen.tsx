import React, { useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { clearMaintenanceMode } from '@/shared/services/slices/uiSlice';
import { logout } from '@/shared/services/slices/authSlice';

// An ISO-8601-looking timestamp is formatted for display; anything else
// (an admin's free-text ETA like "30 minutes", see MaintenanceModeTab's
// placeholder) is shown verbatim rather than mangled by Date parsing.
const ISO_LIKE = /^\d{4}-\d{2}-\d{2}T/;

function formatEstimatedCompletion(value: string): string {
  if (!ISO_LIKE.test(value)) return value;

  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;

  // Pinned to UTC so the rendered string is deterministic regardless of the
  // viewer's local timezone (and of the test runner's TZ).
  return parsed.toLocaleString(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'UTC'
  });
}

/**
 * Full-page overlay shown when api.ts's response interceptor sees a 503
 * carrying { code: 'maintenance_mode' } — Admin::MaintenanceMode's gate
 * (server/app/controllers/concerns/authentication.rb). Renders nothing
 * otherwise. "Retry" clears the flag and reloads, which either re-triggers
 * the overlay (still down) or resumes the app (maintenance lifted).
 *
 * Rendered as a MODAL takeover, not just an overlay: portaled to
 * document.body (outside #root, the app's own mount point — see Modal.tsx
 * for the same pattern) specifically so the app underneath can be made
 * `inert`/`aria-hidden` WITHOUT also hiding this overlay itself, which sits
 * as a sibling of the routed app content inside #root (App.tsx).
 */
export const MaintenanceScreen: React.FC = () => {
  const dispatch = useDispatch<AppDispatch>();
  const maintenance = useSelector((state: RootState) => state.ui.maintenance);
  const dialogRef = useRef<HTMLDivElement>(null);
  const active = Boolean(maintenance?.active);

  useEffect(() => {
    if (!active) return;

    // Move focus into the dialog immediately (WAI-ARIA alertdialog pattern):
    // this is an unannounced, unrequested interruption, so focus must not be
    // left wherever it was in the now-inert app underneath.
    dialogRef.current?.focus();

    const appRoot = document.getElementById('root');
    if (!appRoot) return;

    const hadAriaHidden = appRoot.hasAttribute('aria-hidden');
    const previousAriaHidden = appRoot.getAttribute('aria-hidden');
    const hadInert = appRoot.hasAttribute('inert');

    appRoot.setAttribute('aria-hidden', 'true');
    appRoot.setAttribute('inert', '');

    return () => {
      if (hadAriaHidden) {
        appRoot.setAttribute('aria-hidden', previousAriaHidden as string);
      } else {
        appRoot.removeAttribute('aria-hidden');
      }
      if (!hadInert) {
        appRoot.removeAttribute('inert');
      }
    };
  }, [active]);

  if (!active || !maintenance) return null;

  const handleRetry = () => {
    dispatch(clearMaintenanceMode());
    window.location.reload();
  };

  const handleSignOut = () => {
    dispatch(clearMaintenanceMode());
    // Fire-and-forget: the user is being signed out of a system they cannot
    // currently reach anyway — a failed logout call must not block clearing
    // their local session.
    dispatch(logout());
  };

  return createPortal(
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-theme-background">
      <div
        ref={dialogRef}
        role="alertdialog"
        aria-modal="true"
        aria-live="assertive"
        aria-labelledby="maintenance-screen-title"
        aria-describedby="maintenance-screen-message"
        tabIndex={-1}
        className="max-w-md w-full mx-4 p-8 rounded-xl border border-theme bg-theme-surface text-center space-y-4 focus:outline-none"
      >
        <div className="text-5xl" aria-hidden="true">🔧</div>
        <h1 id="maintenance-screen-title" className="text-xl font-semibold text-theme-primary">
          System Under Maintenance
        </h1>
        <p id="maintenance-screen-message" className="text-theme-secondary">
          {maintenance.message || 'System is under maintenance'}
        </p>
        {maintenance.estimatedCompletion && (
          <p className="text-sm text-theme-secondary">
            <span className="font-medium">Estimated completion:</span>{' '}
            {formatEstimatedCompletion(maintenance.estimatedCompletion)}
          </p>
        )}
        <div className="flex items-center justify-center gap-3">
          <button
            onClick={handleRetry}
            className="btn-theme btn-theme-primary"
          >
            Retry
          </button>
          <button
            onClick={handleSignOut}
            className="btn-theme btn-theme-secondary"
          >
            Sign out
          </button>
        </div>
      </div>
    </div>,
    document.body
  );
};
