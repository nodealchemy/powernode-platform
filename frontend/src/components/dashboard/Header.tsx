import React, { useState, useRef, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { User } from '../../store/slices/authSlice';
import { WebSocketStatusIndicator } from '../common/WebSocketStatusIndicator';
import { ThemeToggle } from '../common/ThemeToggle';
import { NotificationContainer } from '../common/NotificationContainer';

interface HeaderProps {
  user: User | null;
  onLogout: () => void;
  onToggleSidebar: () => void;
}

export const Header: React.FC<HeaderProps> = ({ user, onLogout, onToggleSidebar }) => {
  const [showUserMenu, setShowUserMenu] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Check if user has admin access
  const hasAdminAccess = user?.role === 'owner' || user?.role === 'admin';

  // Get user initials
  const getUserInitials = () => {
    if (!user?.firstName || !user?.lastName) return 'U';
    return `${user.firstName[0]}${user.lastName[0]}`.toUpperCase();
  };

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setShowUserMenu(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, []);


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

        {/* Center - Notifications */}
        <div className="flex justify-center">
          <NotificationContainer />
        </div>

        {/* Right side */}
        <div className="flex items-center justify-end space-x-4">
          {/* WebSocket Connection Status */}
          <WebSocketStatusIndicator />
          
          {/* Theme Toggle */}
          <ThemeToggle />

          {/* User Profile Dropdown */}
          <div className="relative" ref={dropdownRef}>
            <button
              onClick={() => setShowUserMenu(!showUserMenu)}
              className="flex items-center space-x-3 p-2 rounded-lg text-sm hover:bg-theme-surface-hover transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 focus:ring-offset-theme-surface"
              aria-expanded={showUserMenu}
              aria-haspopup="true"
            >
              {/* User Avatar */}
              <div className="relative">
                <div className="h-9 w-9 rounded-full bg-gradient-to-br from-theme-interactive-primary to-theme-interactive-secondary flex items-center justify-center shadow-sm">
                  <span className="text-white text-sm font-semibold">
                    {getUserInitials()}
                  </span>
                </div>
                {/* Online status indicator */}
                <div className="absolute -bottom-0.5 -right-0.5 h-3 w-3 bg-theme-success border-2 border-theme-surface rounded-full"></div>
              </div>
              
              {/* User Info - Hidden on mobile */}
              <div className="hidden md:block text-left">
                <p className="font-medium text-theme-primary text-sm leading-tight">
                  {user?.firstName} {user?.lastName}
                </p>
                <p className="text-xs text-theme-tertiary leading-tight">
                  {user?.account?.name}
                </p>
              </div>

              {/* Dropdown Arrow */}
              <svg 
                className={`h-4 w-4 text-theme-secondary transition-transform duration-200 ${showUserMenu ? 'rotate-180' : ''}`} 
                fill="none" 
                stroke="currentColor" 
                viewBox="0 0 24 24"
              >
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
              </svg>
            </button>

            {/* Dropdown Menu */}
            {showUserMenu && (
              <div className="absolute right-0 mt-2 w-72 bg-theme-surface rounded-xl shadow-xl border border-theme z-50 py-1">
                {/* User Header */}
                <div className="px-4 py-4 border-b border-theme">
                  <div className="flex items-center space-x-3">
                    <div className="h-12 w-12 rounded-full bg-gradient-to-br from-theme-interactive-primary to-theme-interactive-secondary flex items-center justify-center">
                      <span className="text-white text-lg font-semibold">
                        {getUserInitials()}
                      </span>
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-semibold text-theme-primary text-base truncate">
                        {user?.firstName} {user?.lastName}
                      </p>
                      <p className="text-sm text-theme-secondary truncate">
                        {user?.email}
                      </p>
                      <div className="mt-1">
                        <span className="text-xs text-theme-tertiary truncate">
                          {user?.account?.name}
                        </span>
                      </div>
                    </div>
                  </div>
                </div>

                {/* Menu Items */}
                <div className="py-1">
                  {/* Account Section */}
                  <div className="px-3 py-2">
                    <p className="text-xs font-semibold text-theme-tertiary uppercase tracking-wider">
                      Account
                    </p>
                  </div>
                  
                  <Link
                    to="/dashboard/account/profile"
                    className="flex items-center px-4 py-2.5 text-sm text-theme-primary hover:bg-theme-surface-hover transition-colors duration-150"
                    onClick={() => setShowUserMenu(false)}
                  >
                    <svg className="mr-3 h-4 w-4 text-theme-secondary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                    </svg>
                    My Profile
                  </Link>
                  
                  <Link
                    to="/dashboard/account/settings"
                    className="flex items-center px-4 py-2.5 text-sm text-theme-primary hover:bg-theme-surface-hover transition-colors duration-150"
                    onClick={() => setShowUserMenu(false)}
                  >
                    <svg className="mr-3 h-4 w-4 text-theme-secondary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                    </svg>
                    Account Settings
                  </Link>
                  
                  <Link
                    to="/dashboard/account/invitations"
                    className="flex items-center px-4 py-2.5 text-sm text-theme-primary hover:bg-theme-surface-hover transition-colors duration-150"
                    onClick={() => setShowUserMenu(false)}
                  >
                    <svg className="mr-3 h-4 w-4 text-theme-secondary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" />
                    </svg>
                    Team Invitations
                  </Link>

                  <Link
                    to="/dashboard/business"
                    className="flex items-center px-4 py-2.5 text-sm text-theme-primary hover:bg-theme-surface-hover transition-colors duration-150"
                    onClick={() => setShowUserMenu(false)}
                  >
                    <svg className="mr-3 h-4 w-4 text-theme-secondary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
                    </svg>
                    Business Management
                  </Link>

                  {/* Admin Section */}
                  {hasAdminAccess && (
                    <>
                      <div className="border-t border-theme my-1"></div>
                      <div className="px-3 py-2">
                        <p className="text-xs font-semibold text-theme-tertiary uppercase tracking-wider">
                          Administration
                        </p>
                      </div>
                      
                      <Link
                        to="/dashboard/system/admin"
                        className="flex items-center px-4 py-2.5 text-sm text-theme-error hover:bg-theme-error-background transition-colors duration-150"
                        onClick={() => setShowUserMenu(false)}
                      >
                        <svg className="mr-3 h-4 w-4 text-theme-error" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                        </svg>
                        Admin Settings
                      </Link>
                      
                      <Link
                        to="/dashboard/account/users"
                        className="flex items-center px-4 py-2.5 text-sm text-theme-error hover:bg-theme-error-background transition-colors duration-150"
                        onClick={() => setShowUserMenu(false)}
                      >
                        <svg className="mr-3 h-4 w-4 text-theme-error" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
                        </svg>
                        User Management
                      </Link>
                    </>
                  )}

                  {/* Support & Help */}
                  <div className="border-t border-theme my-1"></div>
                  <div className="px-3 py-2">
                    <p className="text-xs font-semibold text-theme-tertiary uppercase tracking-wider">
                      Support
                    </p>
                  </div>
                  
                  <a
                    href="mailto:support@powernode.com"
                    className="flex items-center px-4 py-2.5 text-sm text-theme-primary hover:bg-theme-surface-hover transition-colors duration-150"
                  >
                    <svg className="mr-3 h-4 w-4 text-theme-secondary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8.228 9c.549-1.165 2.03-2 3.772-2 2.21 0 4 1.343 4 3 0 1.4-1.278 2.575-3.006 2.907-.542.104-.994.54-.994 1.093m0 3h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                    Help & Support
                  </a>

                  {/* Logout */}
                  <div className="border-t border-theme my-1"></div>
                  <button
                    onClick={() => {
                      setShowUserMenu(false);
                      onLogout();
                    }}
                    className="w-full flex items-center px-4 py-2.5 text-sm text-theme-error hover:bg-theme-error-background transition-colors duration-150"
                  >
                    <svg className="mr-3 h-4 w-4 text-theme-error" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
                    </svg>
                    Sign Out
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </header>
  );
};