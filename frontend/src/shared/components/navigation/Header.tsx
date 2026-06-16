// Rebuilt Header Component
import React, { Suspense, useEffect, useState } from 'react';
import { useLocation } from 'react-router-dom';
import { useSelector } from 'react-redux';
import type { RootState } from '@/shared/services';
import { UserMenu } from '@/shared/components/navigation/UserMenu';
import { WebSocketStatusIndicator } from '@/shared/components/ui/WebSocketStatusIndicator';
import { ThemeToggle } from '@/shared/components/ui/ThemeToggle';
import { AccountSwitcher } from '@/features/account/switcher';
import { NotificationBell } from '@/features/account/notifications';
import { featureRegistry } from '@/shared/services/featureRegistry';

export const Header: React.FC = () => {
  const location = useLocation();
  const permissions = useSelector((state: RootState) => state.auth.user?.permissions);

  // Re-render when extensions register header widgets (they register at module
  // import time, but subscribing keeps this robust to any later registration).
  const [, setRegistryVersion] = useState(() => featureRegistry.getVersion());
  useEffect(() => {
    return featureRegistry.subscribe(() => setRegistryVersion(featureRegistry.getVersion()));
  }, []);

  // Extension-contributed header widgets, shown when their route matches and
  // the user holds the (optional) required permission. Keyed by namespace —
  // core never names a specific extension (e.g. the trading portfolio switcher
  // is registered by the trading extension).
  const headerWidgets = featureRegistry.getHeaderWidgets().filter(
    (widget) =>
      widget.match(location.pathname) &&
      (!widget.permission || permissions?.includes(widget.permission))
  );

  return (
    <header className="relative z-20 bg-theme-surface h-16 border-b border-theme">
      <div className="flex items-center justify-between px-4 sm:px-6 lg:px-8 h-full gap-2 sm:gap-4">
        {/* Left side - Account Switcher + extension-contributed header widgets */}
        <div className="flex items-center justify-center flex-1 min-w-0 gap-2">
          <AccountSwitcher />
          {headerWidgets.map((widget, index) => {
            const WidgetComponent = widget.component;
            return (
              <Suspense key={`header-widget-${index}`} fallback={null}>
                <WidgetComponent />
              </Suspense>
            );
          })}
        </div>

        {/* Right side */}
        <div className="flex items-center shrink-0 space-x-2 sm:space-x-4">
          {/* WebSocket Connection Status */}
          <WebSocketStatusIndicator />

          {/* Notifications */}
          <NotificationBell />

          {/* Theme Toggle */}
          <ThemeToggle />

          {/* User Profile Dropdown */}
          <UserMenu />
        </div>
      </div>
    </header>
  );
};

export default Header;