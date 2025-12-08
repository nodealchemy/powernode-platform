// Rebuilt Header Component
import React from 'react';
import { UserMenu } from './UserMenu';
import { WebSocketStatusIndicator } from '../ui/WebSocketStatusIndicator';
import { ThemeToggle } from '../ui/ThemeToggle';
import { AccountSwitcher } from '@/features/account-switcher';
import { NotificationBell } from '@/features/notifications';

interface HeaderProps {
  onToggleSidebar: () => void;
}

export const Header: React.FC<HeaderProps> = ({ onToggleSidebar }) => {
  return (
    <header className="bg-theme-surface h-16 border-b border-theme">
      <div className="grid grid-cols-3 items-center px-4 sm:px-6 lg:px-8 h-full">
        {/* Left side */}
        <div className="flex items-center space-x-3">
          {/* Mobile sidebar toggle */}
          <button
            onClick={onToggleSidebar}
            className="md:hidden p-2 rounded-md text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover"
            title="Toggle sidebar"
          >
            <svg className="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
            </svg>
          </button>
        </div>

        {/* Center - Account Switcher */}
        <div className="flex justify-center">
          <AccountSwitcher />
        </div>

        {/* Right side */}
        <div className="flex items-center justify-end space-x-4">
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