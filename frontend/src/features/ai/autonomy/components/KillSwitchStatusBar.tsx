// Global kill-switch status indicator. Fetches its own status (light polling
// via useKillSwitchStatus) and renders nothing unless autonomy is halted, so
// it is safe to mount unconditionally on every page.
import React from 'react';
import { useKillSwitchStatus } from '../api/autonomyApi';

export const KillSwitchStatusBar: React.FC = () => {
  const { data: status } = useKillSwitchStatus();
  if (!status?.halted) return null;

  return (
    <div className="flex items-center gap-3 p-3 mb-4 rounded-lg border border-theme-error-border/50 bg-theme-error-fg/5">
      <div className="h-3 w-3 rounded-full bg-theme-error-bg animate-pulse" />
      <div className="flex-1">
        <p className="text-sm font-medium text-theme-error-fg">AI Activity Suspended</p>
        {status.reason && <p className="text-xs text-theme-secondary">{status.reason}</p>}
      </div>
      <span className="text-xs text-theme-tertiary">Since {new Date(status.halted_since!).toLocaleString()}</span>
    </div>
  );
};

export default KillSwitchStatusBar;
