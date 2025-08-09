import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { User } from '../../store/slices/authSlice';
import { WebSocketStatusIndicator } from '../common/WebSocketStatusIndicator';

interface HeaderProps {
  user: User | null;
  onLogout: () => void;
  onToggleSidebar: () => void;
}

export const Header: React.FC<HeaderProps> = ({ user, onLogout, onToggleSidebar }) => {
  const [showUserMenu, setShowUserMenu] = useState(false);
  
  // Check if user has admin access
  const hasAdminAccess = user?.role === 'owner' || user?.role === 'admin';

  return (
    <header className="bg-white border-b border-gray-200">
      <div className="flex justify-between items-center px-4 sm:px-6 lg:px-8 h-16">
        {/* Left side */}
        <div className="flex items-center">
          <button
            onClick={onToggleSidebar}
            className="md:hidden p-2 rounded-md text-gray-400 hover:text-gray-500 hover:bg-gray-100"
          >
            <svg className="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
            </svg>
          </button>
        </div>

        {/* Right side */}
        <div className="flex items-center space-x-4">
          {/* WebSocket Connection Status */}
          <WebSocketStatusIndicator />

          {/* User menu */}
          <div className="relative">
            <button
              onClick={() => setShowUserMenu(!showUserMenu)}
              className="flex items-center space-x-3 p-2 rounded-lg text-sm text-gray-700 hover:bg-gray-100"
            >
              <div className="h-8 w-8 rounded-full bg-blue-600 flex items-center justify-center">
                <span className="text-white text-sm font-medium">
                  {user?.firstName?.[0]}{user?.lastName?.[0]}
                </span>
              </div>
              <div className="hidden md:block text-left">
                <p className="font-medium">{user?.firstName} {user?.lastName}</p>
                <p className="text-xs text-gray-500">{user?.account?.name}</p>
              </div>
              <svg className="h-4 w-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
              </svg>
            </button>

            {/* Dropdown menu */}
            {showUserMenu && (
              <>
                <div
                  className="fixed inset-0 z-10"
                  onClick={() => setShowUserMenu(false)}
                />
                <div className="absolute right-0 mt-2 w-48 bg-white rounded-md shadow-lg border border-gray-200 z-20">
                  <div className="py-1">
                    <button
                      type="button"
                      className="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
                      onClick={() => {
                        setShowUserMenu(false);
                        // Navigate to profile page
                      }}
                    >
                      Your Profile
                    </button>
                    <Link
                      to="/dashboard/settings"
                      className="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
                      onClick={() => setShowUserMenu(false)}
                    >
                      Settings
                    </Link>
                    {hasAdminAccess && (
                      <Link
                        to="/dashboard/admin-settings"
                        className="block px-4 py-2 text-sm text-red-700 hover:bg-red-50 font-medium"
                        onClick={() => setShowUserMenu(false)}
                      >
                        🔧 Admin Settings
                      </Link>
                    )}
                    <div className="border-t border-gray-100" />
                    <button
                      onClick={() => {
                        setShowUserMenu(false);
                        onLogout();
                      }}
                      className="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
                    >
                      Sign out
                    </button>
                  </div>
                </div>
              </>
            )}
          </div>
        </div>
      </div>
    </header>
  );
};