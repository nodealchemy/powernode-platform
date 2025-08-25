// User Menu Component
import React, { useState, useRef, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '@/shared/services';
import { logout } from '@/shared/services/slices/authSlice';
// import { NavigationItem } from './NavigationItem';
import { useNavigation } from '@/shared/hooks/NavigationContext';

interface UserMenuProps {
  className?: string;
}

export const UserMenu: React.FC<UserMenuProps> = ({ className = '' }) => {
  const dispatch = useDispatch<AppDispatch>();
  const { user } = useSelector((state: RootState) => state.auth);
  const { config } = useNavigation();
  const [showUserMenu, setShowUserMenu] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

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

  // Get user initials
  const getUserInitials = () => {
    if (!user?.first_name || !user?.last_name) return 'U';
    return `${user.first_name[0]}${user.last_name[0]}`.toUpperCase();
  };

  // Handle logout
  const handleLogout = () => {
    setShowUserMenu(false);
    dispatch(logout());
  };

  // Filter user menu items 
  const userMenuItems = config.userMenuItems;

  return (
    <div className={`relative ${className}`} ref={dropdownRef}>
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
            {user?.first_name} {user?.last_name}
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
                  {user?.first_name} {user?.last_name}
                </p>
                <p className="text-sm text-theme-secondary truncate">
                  {user?.email}
                </p>
                <div className="mt-1">
                  <span className="text-xs text-theme-tertiary truncate">
                    {user?.account?.name}
                  </span>
                  {/* Remove role display - use permission-based access control only */}
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
            
            {userMenuItems.slice(0, 3).map((item) => (
              <Link
                key={item.id}
                to={item.href}
                onClick={() => setShowUserMenu(false)}
                className="flex items-center px-4 py-2.5 text-sm text-theme-primary hover:bg-theme-surface-hover transition-colors duration-150"
              >
                <div className="mr-3 h-4 w-4 text-theme-secondary">
                  {typeof item.icon === 'string' ? (
                    <span>{item.icon}</span>
                  ) : (
                    <item.icon className="w-4 h-4" />
                  )}
                </div>
                <div className="flex-1">
                  <div className="font-medium">{item.name}</div>
                  {item.description && (
                    <div className="text-xs text-theme-tertiary mt-0.5">{item.description}</div>
                  )}
                </div>
              </Link>
            ))}

            {/* Support Section */}
            <div className="border-t border-theme my-1"></div>
            <div className="px-3 py-2">
              <p className="text-xs font-semibold text-theme-tertiary uppercase tracking-wider">
                Support
              </p>
            </div>
            
            {userMenuItems.slice(3, -1).map((item) => (
              <a
                key={item.id}
                href={item.href}
                className="flex items-center px-4 py-2.5 text-sm text-theme-primary hover:bg-theme-surface-hover transition-colors duration-150"
                target={item.isExternal ? '_blank' : undefined}
                rel={item.isExternal ? 'noopener noreferrer' : undefined}
              >
                <div className="mr-3 h-4 w-4 text-theme-secondary">
                  {typeof item.icon === 'string' ? (
                    <span>{item.icon}</span>
                  ) : (
                    <item.icon className="w-4 h-4" />
                  )}
                </div>
                {item.name}
              </a>
            ))}

            {/* Logout */}
            <div className="border-t border-theme my-1"></div>
            <button
              onClick={handleLogout}
              className="w-full flex items-center px-4 py-2.5 text-sm text-theme-error hover:bg-theme-error-background transition-colors duration-150"
            >
              <div className="mr-3 h-4 w-4 text-theme-error">
                {(() => {
                  const logoutItem = userMenuItems[userMenuItems.length - 1];
                  if (typeof logoutItem.icon === 'string') {
                    return <span>{logoutItem.icon}</span>;
                  } else {
                    const IconComponent = logoutItem.icon as React.ComponentType<any>;
                    return <IconComponent className="w-4 h-4" />;
                  }
                })()}
              </div>
              {userMenuItems[userMenuItems.length - 1].name}
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

export default UserMenu;