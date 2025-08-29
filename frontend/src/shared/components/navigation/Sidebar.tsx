// Rebuilt Sidebar Component
import React, { useCallback, useEffect, useRef } from 'react';
import { NavigationItem } from './NavigationItem';
import { NavigationSection } from './NavigationSection';
import { useNavigation } from '@/shared/hooks/NavigationContext';
import { VersionDisplay } from '../ui/VersionDisplay';
import { settingsApi } from '@/shared/services/settingsApi';

interface SidebarProps {
  isOpen: boolean;
  onToggle: () => void;
}

export const Sidebar: React.FC<SidebarProps> = ({ isOpen, onToggle }) => {
  const { config, state, updateState } = useNavigation();
  const [copyrightText, setCopyrightText] = React.useState<string>('');
  const [scrollState, setScrollState] = React.useState({
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
    const timeoutId = setTimeout(() => {
      updateScrollState();
    }, 100);

    const navElement = navRef.current;
    if (navElement) {
      navElement.addEventListener('scroll', updateScrollState);
      window.addEventListener('resize', updateScrollState);
      
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
  }, [updateScrollState, state.isCollapsed]);

  // Keyboard navigation for sidebar scrolling
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      const navElement = navRef.current;
      if (!navElement || !scrollState.isScrollable) return;
      
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

  // Handle collapse toggle
  const handleCollapseToggle = useCallback(() => {
    updateState({ isCollapsed: !state.isCollapsed });
  }, [state.isCollapsed, updateState]);

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
      // const isMobile = window.innerWidth < 768;
      // Let user control mobile collapse manually for better UX
    };
    
    window.addEventListener('resize', handleResize);
    handleResize();
    
    return () => window.removeEventListener('resize', handleResize);
  }, [state.isCollapsed]);

  // Load copyright text
  useEffect(() => {
    const loadCopyright = async () => {
      try {
        const copyright = await settingsApi.getCopyright();
        setCopyrightText(copyright);
      } catch (error) {
        setCopyrightText(`© ${new Date().getFullYear()} Powernode Platform. All rights reserved.`);
      }
    };

    loadCopyright();
  }, []);


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
          state.isCollapsed ? 'w-16' : 'w-64'
        } bg-theme-surface shadow-lg transform sidebar-transition md:translate-x-0 md:static md:inset-0`}
      >
        <div className="flex flex-col h-full">
          {/* Logo */}
          <div className={`flex items-center justify-between h-16 ${state.isCollapsed ? 'px-3' : 'px-4 sm:px-6 lg:px-8'} border-b border-theme`}>
            <div className="flex items-center">
              <div className="h-8 w-8 bg-theme-interactive-primary rounded-lg flex items-center justify-center flex-shrink-0">
                <span className="text-white font-bold">P</span>
              </div>
              {!state.isCollapsed && (
                <span className="ml-2 text-xl font-semibold text-theme-primary sidebar-content-transition">
                  Powernode
                </span>
              )}
            </div>
            
            {/* Desktop collapse toggle */}
            <button
              onClick={handleCollapseToggle}
              className="hidden md:block p-1 rounded-md text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover transition-colors duration-200"
              title={state.isCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
            >
              <svg 
                className={`h-5 w-5 transform transition-transform duration-300 ${state.isCollapsed ? 'rotate-180' : ''}`} 
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
              className={`h-full ${state.isCollapsed ? 'px-2' : 'px-3'} py-6 space-y-2 overflow-y-auto sidebar-scrollbar`}
              style={{ 
                maxHeight: 'calc(100vh - 8rem)',
                overflowY: 'auto'
              }}
            >
              {/* Top-level navigation items */}
              {config.items
                .sort((a, b) => (a.order || 0) - (b.order || 0))
                .map((item) => (
                  <NavigationItem
                    key={item.id}
                    item={item}
                    isCollapsed={state.isCollapsed}
                  />
                ))
              }
              
              {/* Navigation sections (like Administration) */}
              {config.sections && config.sections
                .sort((a, b) => (a.order || 0) - (b.order || 0))
                .map((section) => (
                  <NavigationSection
                    key={section.id}
                    section={section}
                    isCollapsed={state.isCollapsed}
                  />
                ))
              }
            </nav>
          </div>

          {/* Footer */}
          {!state.isCollapsed && (
            <div className="border-t border-theme p-4">
              <div className="text-xs text-theme-tertiary">
                <VersionDisplay show="simple" className="mb-1" />
                <p>{copyrightText || `© ${new Date().getFullYear()} Powernode Platform. All rights reserved.`}</p>
              </div>
            </div>
          )}
        </div>
      </div>
    </>
  );
};

export default Sidebar;