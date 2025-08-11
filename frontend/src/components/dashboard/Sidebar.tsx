import React, { useState, useEffect, useCallback } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '../../store';
import { toggleSidebarCollapse } from '../../store/slices/uiSlice';

interface SidebarProps {
  isOpen: boolean;
  onToggle: () => void;
}

const navigation = [
  { name: 'Dashboard', href: '/dashboard', icon: '📊' },
  { name: 'Analytics', href: '/dashboard/analytics', icon: '📈' },
  { name: 'Reports', href: '/dashboard/reports', icon: '📋' },
  { name: 'Subscriptions', href: '/dashboard/subscriptions', icon: '💳' },
  { name: 'Customers', href: '/dashboard/customers', icon: '👥' },
  { name: 'Plans', href: '/dashboard/plans', icon: '💎' },
  { name: 'Billing', href: '/dashboard/billing', icon: '💰' },
  { name: 'Settings', href: '/dashboard/settings', icon: '⚙️' },
];

const adminNavigation = [
  { name: 'Admin Settings', href: '/dashboard/admin-settings', icon: '🔧', adminOnly: true },
  { name: 'Payment Gateways', href: '/dashboard/payment-gateways', icon: '💳', adminOnly: true },
  { name: 'Services', href: '/dashboard/services', icon: '🤖', adminOnly: true },
];

export const Sidebar: React.FC<SidebarProps> = ({ isOpen, onToggle }) => {
  const location = useLocation();
  const dispatch = useDispatch<AppDispatch>();
  const { user } = useSelector((state: RootState) => state.auth);
  const { sidebarCollapsed } = useSelector((state: RootState) => state.ui);
  const [hoveredItem, setHoveredItem] = useState<string | null>(null);
  
  // Check if user has admin access
  const hasAdminAccess = user?.role === 'owner' || user?.role === 'admin';
  
  const handleCollapseToggle = useCallback(() => {
    dispatch(toggleSidebarCollapse());
  }, [dispatch]);
  
  // Keyboard shortcut: Ctrl/Cmd + B to toggle collapse
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key === 'b') {
        event.preventDefault();
        handleCollapseToggle();
      }
    };
    
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [handleCollapseToggle]);
  
  // Auto-collapse on mobile screens
  useEffect(() => {
    const handleResize = () => {
      const isMobile = window.innerWidth < 768; // md breakpoint
      // Only auto-collapse if we're on mobile and sidebar is currently expanded
      if (isMobile && !sidebarCollapsed) {
        // Don't auto-collapse on mobile - let user control it
        // This gives better UX control
      }
    };
    
    window.addEventListener('resize', handleResize);
    handleResize(); // Check on initial load
    
    return () => window.removeEventListener('resize', handleResize);
  }, [sidebarCollapsed, dispatch]);
  
  return (
    <>
      {/* Mobile sidebar overlay */}
      {isOpen && (
        <div className="fixed inset-0 flex z-40 md:hidden">
          <div
            className="fixed inset-0 bg-black bg-opacity-50 dark:bg-opacity-75"
            onClick={onToggle}
          />
        </div>
      )}

      {/* Sidebar */}
      <div
        className={`${
          isOpen ? 'translate-x-0' : '-translate-x-full'
        } fixed inset-y-0 left-0 z-50 ${
          sidebarCollapsed ? 'w-16' : 'w-64'
        } bg-theme-surface shadow-lg transform sidebar-transition md:translate-x-0 md:static md:inset-0`}
      >
        <div className="flex flex-col h-full">
          {/* Logo */}
          <div className={`flex items-center justify-between h-16 ${sidebarCollapsed ? 'px-3' : 'px-4 sm:px-6 lg:px-8'} border-b border-theme`}>
            <div className="flex items-center">
              <div className="h-8 w-8 bg-theme-interactive-primary rounded-lg flex items-center justify-center flex-shrink-0">
                <span className="text-white font-bold">P</span>
              </div>
              {!sidebarCollapsed && (
                <span className="ml-2 text-xl font-semibold text-theme-primary sidebar-content-transition">
                  Powernode
                </span>
              )}
            </div>
            {/* Desktop collapse toggle */}
            <button
              onClick={handleCollapseToggle}
              className="hidden md:block p-1 rounded-md text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover transition-colors duration-200"
              title={sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
            >
              <svg 
                className={`h-5 w-5 transform transition-transform duration-300 ${sidebarCollapsed ? 'rotate-180' : ''}`} 
                fill="none" 
                stroke="currentColor" 
                viewBox="0 0 24 24"
              >
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 19l-7-7 7-7m8 14l-7-7 7-7" />
              </svg>
            </button>
            {/* Mobile close button */}
            <button
              onClick={onToggle}
              className="md:hidden p-1 rounded-md text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover"
            >
              <svg className="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          {/* Navigation */}
          <nav className={`flex-1 ${sidebarCollapsed ? 'px-2' : 'px-3'} py-6 space-y-1`}>
            {/* Regular navigation items */}
            {navigation.map((item) => {
              const isActive = location.pathname === item.href;
              return (
                <div
                  key={item.name}
                  className="relative"
                  onMouseEnter={() => setHoveredItem(item.name)}
                  onMouseLeave={() => setHoveredItem(null)}
                >
                  <Link
                    to={item.href}
                    className={`${
                      isActive
                        ? 'bg-theme-surface-selected border-theme-focus text-theme-link'
                        : 'border-transparent text-theme-secondary hover:bg-theme-surface-hover hover:text-theme-primary'
                    } group flex items-center ${
                      sidebarCollapsed ? 'justify-center px-3 py-3' : 'px-3 py-2'
                    } text-sm font-medium border-l-4 rounded-md transition-all duration-150`}
                    title={sidebarCollapsed ? item.name : undefined}
                  >
                    <span className={`text-lg sidebar-icon-transition ${sidebarCollapsed ? '' : 'mr-3'}`}>{item.icon}</span>
                    {!sidebarCollapsed && (
                      <span className="sidebar-content-transition">{item.name}</span>
                    )}
                  </Link>
                  
                  {/* Tooltip for collapsed state */}
                  {sidebarCollapsed && hoveredItem === item.name && (
                    <div className="absolute left-full top-0 ml-2 px-2 py-1 bg-theme-surface-pressed text-theme-inverse text-xs rounded-md whitespace-nowrap z-50 pointer-events-none shadow-md">
                      {item.name}
                      <div className="absolute left-0 top-1/2 transform -translate-y-1/2 -translate-x-1 border-4 border-transparent border-r-gray-900 dark:border-r-gray-100"></div>
                    </div>
                  )}
                </div>
              );
            })}

            {/* Admin navigation section */}
            {hasAdminAccess && (
              <>
                <div className="border-t border-theme my-4"></div>
                {!sidebarCollapsed && (
                  <div className="px-3 py-2">
                    <p className="text-xs font-semibold text-theme-tertiary uppercase tracking-wider">
                      Administration
                    </p>
                  </div>
                )}
                {adminNavigation.map((item) => {
                  const isActive = location.pathname === item.href;
                  return (
                    <div
                      key={item.name}
                      className="relative"
                      onMouseEnter={() => setHoveredItem(item.name)}
                      onMouseLeave={() => setHoveredItem(null)}
                    >
                      <Link
                        to={item.href}
                        className={`${
                          isActive
                            ? 'bg-red-50 dark:bg-red-900/30 border-red-500 text-red-700 dark:text-red-400'
                            : 'border-transparent text-theme-secondary hover:bg-theme-surface-hover hover:text-theme-primary'
                        } group flex items-center ${
                          sidebarCollapsed ? 'justify-center px-3 py-3' : 'px-3 py-2'
                        } text-sm font-medium border-l-4 rounded-md transition-all duration-150`}
                        title={sidebarCollapsed ? item.name : undefined}
                      >
                        <span className={`text-lg sidebar-icon-transition ${sidebarCollapsed ? '' : 'mr-3'}`}>{item.icon}</span>
                        {!sidebarCollapsed && (
                          <span className="sidebar-content-transition">{item.name}</span>
                        )}
                      </Link>
                      
                      {/* Tooltip for collapsed state */}
                      {sidebarCollapsed && hoveredItem === item.name && (
                        <div className="absolute left-full top-0 ml-2 px-2 py-1 bg-theme-surface-pressed text-theme-inverse text-xs rounded-md whitespace-nowrap z-50 pointer-events-none shadow-md">
                          {item.name}
                          <div className="absolute left-0 top-1/2 transform -translate-y-1/2 -translate-x-1 border-4 border-transparent border-r-gray-900 dark:border-r-gray-100"></div>
                        </div>
                      )}
                    </div>
                  );
                })}
              </>
            )}
          </nav>

          {/* Footer */}
          {!sidebarCollapsed && (
            <div className="border-t border-theme p-4">
              <div className="text-xs text-theme-tertiary">
                <p>Version 1.0.0</p>
                <p>© 2025 Powernode</p>
              </div>
            </div>
          )}
        </div>
      </div>
    </>
  );
};