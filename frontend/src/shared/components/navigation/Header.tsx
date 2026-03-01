// Rebuilt Header Component
import React from 'react';
import { UserMenu } from '@/shared/components/navigation/UserMenu';
import { WebSocketStatusIndicator } from '@/shared/components/ui/WebSocketStatusIndicator';
import { ThemeToggle } from '@/shared/components/ui/ThemeToggle';
import { AccountSwitcher } from '@/features/account/switcher';
import { NotificationBell } from '@/features/account/notifications';

export const Header: React.FC = () => {
  return (
    <header className="bg-theme-surface h-16 border-b border-theme">
      <div className="flex items-center justify-between px-4 sm:px-6 lg:px-8 h-full gap-2 sm:gap-4">
        {/* Left side - Account Switcher */}
        <div className="flex justify-center flex-1 min-w-0">
          <AccountSwitcher />
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