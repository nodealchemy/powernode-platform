// Rebuilt Header Component
import React, { lazy, Suspense } from 'react';
import { useLocation } from 'react-router-dom';
import { useSelector } from 'react-redux';
import type { RootState } from '@/shared/services';
import { UserMenu } from '@/shared/components/navigation/UserMenu';
import { WebSocketStatusIndicator } from '@/shared/components/ui/WebSocketStatusIndicator';
import { ThemeToggle } from '@/shared/components/ui/ThemeToggle';
import { AccountSwitcher } from '@/features/account/switcher';
import { NotificationBell } from '@/features/account/notifications';

const PortfolioSwitcherWrapper = (typeof __EXTENSIONS__ !== 'undefined' && __EXTENSIONS__.includes('trading'))
  ? lazy(() => import('@ext/trading/shared/components/PortfolioSwitcherWrapper'))
  : null;

export const Header: React.FC = () => {
  const location = useLocation();
  const permissions = useSelector((state: RootState) => state.auth.user?.permissions);
  const showPortfolioSwitcher = PortfolioSwitcherWrapper &&
    location.pathname.startsWith('/app/trading') &&
    permissions?.includes('trading.view');

  return (
    <header className="relative z-[60] bg-theme-surface h-16 border-b border-theme">
      <div className="flex items-center justify-between px-4 sm:px-6 lg:px-8 h-full gap-2 sm:gap-4">
        {/* Left side - Account Switcher + Portfolio Switcher */}
        <div className="flex items-center justify-center flex-1 min-w-0 gap-2">
          <AccountSwitcher />
          {showPortfolioSwitcher && (
            <Suspense fallback={null}>
              <PortfolioSwitcherWrapper />
            </Suspense>
          )}
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