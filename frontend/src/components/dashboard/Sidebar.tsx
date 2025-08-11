import React, { useState, useEffect, useCallback, useRef } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { useSelector, useDispatch } from 'react-redux';
import { RootState, AppDispatch } from '../../store';
import { toggleSidebarCollapse } from '../../store/slices/uiSlice';
import { hasAccess, hasAdminAccess, hasBillingAccess } from '../../utils/permissionUtils';

interface SidebarProps {
  isOpen: boolean;
  onToggle: () => void;
}

interface NavigationItem {
  name: string;
  href: string;
  icon: string;
  permissions?: string[];
  roles?: string[];
  requiresBillingAccess?: boolean; // Legacy support
  adminOnly?: boolean; // Legacy support
}

const navigation: NavigationItem[] = [
  { 
    name: 'Dashboard', 
    href: '/dashboard', 
    icon: '🏠',
    permissions: ['dashboard_access']
  },
  { 
    name: 'Analytics', 
    href: '/dashboard/analytics', 
    icon: '📊',
    permissions: ['dashboard_access']
  },
  { 
    name: 'Business', 
    href: '/dashboard/business', 
    icon: '💼',
    permissions: ['dashboard_access']
  },
];

const adminNavigation: NavigationItem[] = [
  { 
    name: 'Content Management', 
    href: '/dashboard/pages', 
    icon: '📄',
    permissions: ['dashboard_access'],
    roles: ['admin']  // Only system administrators for now
  },
  { 
    name: 'Plans Management', 
    href: '/dashboard/plans', 
    icon: '💼',
    permissions: ['dashboard_access'],
    roles: ['admin']  // Only system administrators
  },
  { 
    name: 'User Management', 
    href: '/dashboard/admin/users', 
    icon: '👥',
    permissions: ['dashboard_access'],
    roles: ['admin']  // Only system administrators
  },
  { 
    name: 'System Settings', 
    href: '/dashboard/system', 
    icon: '⚙️',
    permissions: ['dashboard_access'],
    roles: ['admin']  // Only system administrators
  },
];

export const Sidebar: React.FC<SidebarProps> = ({ isOpen, onToggle }) => {
  const location = useLocation();
  const dispatch = useDispatch<AppDispatch>();
  const { user } = useSelector((state: RootState) => state.auth);
  const { sidebarCollapsed } = useSelector((state: RootState) => state.ui);
  const [hoveredItem, setHoveredItem] = useState<string | null>(null);
  const [scrollState, setScrollState] = useState({
    isScrollable: false,
    canScrollUp: false,
    canScrollDown: false
  });
  const navRef = useRef<HTMLElement>(null);
  
  // Handle scroll state updates
  const updateScrollState = useCallback(() => {
    const navElement = navRef.current;
    if (!navElement) return;
    
    const { scrollTop, scrollHeight, clientHeight } = navElement;
    const isScrollable = scrollHeight > clientHeight;
    const canScrollUp = scrollTop > 0;
    const canScrollDown = scrollTop < scrollHeight - clientHeight;
    
    setScrollState({ isScrollable, canScrollUp, canScrollDown });
  }, []);
  
  // Update scroll state on mount and when sidebar changes
  useEffect(() => {
    // Add a small delay to ensure DOM is fully rendered
    const timeoutId = setTimeout(() => {
      updateScrollState();
    }, 100);

    const navElement = navRef.current;
    if (navElement) {
      navElement.addEventListener('scroll', updateScrollState);
      // Also check when window resizes
      window.addEventListener('resize', updateScrollState);
      
      // Initial check after a short delay
      requestAnimationFrame(() => {
        updateScrollState();
      });
      
      return () => {
        navElement.removeEventListener('scroll', updateScrollState);
        window.removeEventListener('resize', updateScrollState);
        clearTimeout(timeoutId);
      };
    }
    
    return () => clearTimeout(timeoutId);
  }, [updateScrollState, sidebarCollapsed]);
  
  // Keyboard navigation for sidebar scrolling
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      const navElement = navRef.current;
      if (!navElement || !scrollState.isScrollable) return;
      
      // Only handle keyboard navigation when sidebar has focus or a sidebar item is focused
      const activeElement = document.activeElement;
      const isInSidebar = navElement.contains(activeElement);
      
      if (isInSidebar) {
        switch (event.key) {
          case 'PageUp':
            event.preventDefault();
            navElement.scrollBy({ top: -navElement.clientHeight * 0.8, behavior: 'smooth' });
            break;
          case 'PageDown':
            event.preventDefault();
            navElement.scrollBy({ top: navElement.clientHeight * 0.8, behavior: 'smooth' });
            break;
          case 'Home':
            if (event.ctrlKey) {
              event.preventDefault();
              navElement.scrollTo({ top: 0, behavior: 'smooth' });
            }
            break;
          case 'End':
            if (event.ctrlKey) {
              event.preventDefault();
              navElement.scrollTo({ top: navElement.scrollHeight, behavior: 'smooth' });
            }
            break;
        }
      }
    };
    
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [scrollState.isScrollable]);
  
  // Comprehensive permission checking using centralized utility
  const hasPermission = (requiredPermissions?: string[], requiredRoles?: string[]) => {
    return hasAccess(user, requiredPermissions, requiredRoles);
  };
  
  // Permission checks
  const hasAdminAccessLocal = hasAdminAccess(user);
  const hasBillingAccessLocal = hasBillingAccess(user);
  
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
          <div className="flex-1 relative min-h-0">
            
            <nav 
              ref={navRef}
              className={`h-full ${sidebarCollapsed ? 'px-2' : 'px-3'} py-6 space-y-1 overflow-y-auto sidebar-scrollbar`}
              style={{ 
                maxHeight: 'calc(100vh - 8rem)', /* Subtract header height and footer space */
                overflowY: 'auto'
              }}
            >
            {/* Main Navigation Section */}
            {!sidebarCollapsed && (
              <div className="px-3 pb-2">
                <p className="text-xs font-semibold text-theme-tertiary uppercase tracking-wider">
                  Main
                </p>
              </div>
            )}
            
            {/* Regular navigation items */}
            {navigation.filter(item => {
              // Legacy support for old permission properties
              if (item.adminOnly && !hasAdminAccessLocal) return false;
              if (item.requiresBillingAccess && !hasBillingAccessLocal) return false;
              
              // New comprehensive permission checking
              return hasPermission(item.permissions, item.roles);
            }).map((item) => {
              const isActive = item.href === '/dashboard' 
                ? location.pathname === item.href
                : location.pathname.startsWith(item.href);
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

            {/* Account Settings Section */}
            <div className="border-t border-theme my-4"></div>
            {!sidebarCollapsed && (
              <div className="px-3 py-2">
                <p className="text-xs font-semibold text-theme-tertiary uppercase tracking-wider">
                  Settings
                </p>
              </div>
            )}
            
            <div className="relative" onMouseEnter={() => setHoveredItem('My Account')} onMouseLeave={() => setHoveredItem(null)}>
              <Link
                to="/dashboard/account"
                className={`${
                  location.pathname.startsWith('/dashboard/account')
                    ? 'bg-theme-surface-selected border-theme-focus text-theme-link'
                    : 'border-transparent text-theme-secondary hover:bg-theme-surface-hover hover:text-theme-primary'
                } group flex items-center ${
                  sidebarCollapsed ? 'justify-center px-3 py-3' : 'px-3 py-2'
                } text-sm font-medium border-l-4 rounded-md transition-all duration-150`}
                title={sidebarCollapsed ? 'My Account' : undefined}
              >
                <span className={`text-lg sidebar-icon-transition ${sidebarCollapsed ? '' : 'mr-3'}`}>👤</span>
                {!sidebarCollapsed && (
                  <span className="sidebar-content-transition">My Account</span>
                )}
              </Link>
              
              {/* Tooltip for collapsed state */}
              {sidebarCollapsed && hoveredItem === 'My Account' && (
                <div className="absolute left-full top-0 ml-2 px-2 py-1 bg-theme-surface-pressed text-theme-inverse text-xs rounded-md whitespace-nowrap z-50 pointer-events-none shadow-md">
                  My Account
                  <div className="absolute left-0 top-1/2 transform -translate-y-1/2 -translate-x-1 border-4 border-transparent border-r-gray-900 dark:border-r-gray-100"></div>
                </div>
              )}
            </div>
            
            {/* Admin navigation section - Only show for system administrators */}
            {hasAdminAccessLocal && adminNavigation.filter(item => hasPermission(item.permissions, item.roles)).length > 0 && (
              <>
                <div className="border-t border-theme my-4"></div>
                {!sidebarCollapsed && (
                  <div className="px-3 py-2">
                    <p className="text-xs font-semibold text-theme-tertiary uppercase tracking-wider">
                      Administration
                    </p>
                  </div>
                )}
                {adminNavigation.filter(item => hasPermission(item.permissions, item.roles)).map((item) => {
                  const isActive = location.pathname.startsWith(item.href);
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
                            ? 'bg-theme-error-background border-theme-error-border text-theme-error'
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
          </div>

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