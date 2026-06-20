import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Settings2, X } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { logger } from '@/shared/utils/logger';
import { setupApi } from './services/setupApi';

/**
 * Non-blocking banner (Phase 4 incremental config): shown once bootstrap is
 * complete but one or more extensions have pending setup steps — e.g. a newly
 * added/enabled extension. Opens /setup (which surfaces just the remaining
 * steps). Dismissible for the session; never blocks the app.
 */
export const SetupPendingBanner: React.FC = () => {
  const navigate = useNavigate();
  const [pending, setPending] = useState<string[]>([]);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setupApi
      .getStatus()
      .then((status) => {
        if (cancelled) return;
        if (status.bootstrap_complete && (status.extensions_pending?.length ?? 0) > 0) {
          setPending(status.extensions_pending ?? []);
        }
      })
      .catch((err) => logger.debug('SetupPendingBanner: status check failed', err));
    return () => {
      cancelled = true;
    };
  }, []);

  if (dismissed || pending.length === 0) return null;

  return (
    <div
      className="flex items-center gap-3 border-b border-theme bg-theme-interactive-primary/10 px-4 py-2 text-sm"
      data-testid="setup-pending-banner"
    >
      <Settings2 className="h-4 w-4 flex-shrink-0 text-theme-interactive-primary" aria-hidden="true" />
      <span className="text-theme-primary">
        Finish configuring {pending.join(', ')} to complete setup.
      </span>
      <Button
        type="button"
        variant="primary"
        size="sm"
        onClick={() => navigate('/setup')}
        data-testid="setup-pending-configure"
      >
        Configure
      </Button>
      <button
        type="button"
        onClick={() => setDismissed(true)}
        className="ml-auto text-theme-tertiary hover:text-theme-primary"
        aria-label="Dismiss"
        data-testid="setup-pending-dismiss"
      >
        <X className="h-4 w-4" />
      </button>
    </div>
  );
};

export default SetupPendingBanner;
