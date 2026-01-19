import React, { useState, useEffect } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { Badge } from '../ui/Badge';

export interface Tab {
  id: string;
  label: string;
  icon?: string | React.ReactNode;
  path?: string;
  badge?: {
    count: number;
    variant?: 'primary' | 'secondary' | 'success' | 'warning' | 'danger' | 'info';
  };
  disabled?: boolean;
  permissions?: string[];
}

export interface TabContainerProps {
  tabs: Tab[];
  activeTab?: string;
  onTabChange?: (tabId: string) => void;
  basePath?: string;
  className?: string;
  renderContent?: (activeTab: string) => React.ReactNode;
  children?: React.ReactNode;
  variant?: 'default' | 'pills' | 'underline';
  size?: 'sm' | 'md' | 'lg';
  fullWidth?: boolean;
  compact?: boolean;
}

export const TabContainer: React.FC<TabContainerProps> = ({
  tabs,
  activeTab: controlledActiveTab,
  onTabChange,
  basePath,
  className = '',
  renderContent,
  children,
  variant = 'underline',
  size = 'md',
  fullWidth = false,
  compact = false
}) => {
  const navigate = useNavigate();
  const location = useLocation();
  const [localActiveTab, setLocalActiveTab] = useState(tabs[0]?.id || '');

  // Determine active tab from URL or props
  const activeTab = controlledActiveTab || localActiveTab;

  useEffect(() => {
    if (basePath && location.pathname.startsWith(basePath)) {
      const pathSegment = location.pathname.replace(basePath, '').split('/')[1] || '';
      const matchingTab = tabs.find(tab => tab.path === `/${pathSegment}` || (pathSegment === '' && tab.path === '/'));
      if (matchingTab && matchingTab.id !== localActiveTab) {
        setLocalActiveTab(matchingTab.id);
      }
    }
  }, [location.pathname, basePath, tabs, localActiveTab]);

  const handleTabClick = (tab: Tab) => {
    if (tab.disabled || tab.id === activeTab) return;

    // Update local state
    setLocalActiveTab(tab.id);

    // Call parent handler
    if (onTabChange) {
      onTabChange(tab.id);
    }

    // Handle routing if path is provided (avoid redundant navigation)
    if (basePath && tab.path) {
      const targetPath = tab.path === '/' ? basePath : `${basePath}${tab.path}`;
      if (location.pathname !== targetPath) {
        navigate(targetPath);
      }
    }
  };

  // Tab size classes
  const sizeClasses = {
    sm: 'text-sm py-1.5 px-3',
    md: 'text-sm py-2 px-4',
    lg: 'text-base py-2.5 px-5'
  };

  // Tab variant classes
  const getTabClasses = (tab: Tab, isActive: boolean) => {
    const baseClasses = 'flex items-center space-x-2 font-medium transition-all duration-200';
    const sizeClass = size === 'sm' ? sizeClasses.sm : size === 'lg' ? sizeClasses.lg : sizeClasses.md;
    const disabledClass = tab.disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer';

    switch (variant) {
      case 'pills':
        return `${baseClasses} ${sizeClass} ${disabledClass} rounded-lg ${
          isActive
            ? 'bg-theme-interactive-primary text-white shadow-sm'
            : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover'
        }`;
      
      case 'underline':
        return `${baseClasses} ${sizeClass} ${disabledClass} border-b-2 -mb-px ${
          isActive
            ? 'border-theme-interactive-primary text-theme-interactive-primary'
            : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme-border'
        }`;
      
      default:
        return `${baseClasses} ${sizeClass} ${disabledClass} ${
          isActive
            ? 'text-theme-interactive-primary bg-theme-surface-selected'
            : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover'
        }`;
    }
  };

  // Container classes based on variant
  const getContainerClass = () => {
    const compactSpacing = compact ? 'space-x-1 sm:space-x-2' : 'space-x-4 sm:space-x-6 lg:space-x-8';
    switch (variant) {
      case 'pills':
        return `flex ${compact ? 'space-x-1' : 'space-x-2'} p-1 bg-theme-surface rounded-lg`;
      case 'underline':
        return `flex ${compactSpacing} border-b border-theme`;
      default:
        return `flex ${compact ? 'space-x-0.5' : 'space-x-1'} bg-theme-surface-hover p-1 rounded-lg`;
    }
  };

  const renderIcon = (icon: string | React.ReactNode) => {
    if (typeof icon === 'string') {
      return <span className="text-base">{icon}</span>;
    }
    return icon;
  };

  return (
    <div className={className}>
      {/* Tab Navigation */}
      <div className={`${getContainerClass()} ${fullWidth ? 'w-full' : ''} overflow-x-auto scrollbar-hide`}>
        {tabs.map((tab) => {
          const isActive = activeTab === tab.id;
          
          return (
            <button
              key={tab.id}
              onClick={() => handleTabClick(tab)}
              disabled={tab.disabled}
              className={getTabClasses(tab, isActive)}
              role="tab"
              aria-selected={isActive}
              aria-controls={`tabpanel-${tab.id}`}
            >
              {tab.icon && renderIcon(tab.icon)}
              <span>{tab.label}</span>
              {tab.badge && tab.badge.count > 0 && (
                <Badge variant={tab.badge.variant || 'secondary'} size="xs">
                  {tab.badge.count}
                </Badge>
              )}
            </button>
          );
        })}
      </div>

      {/* Tab Content */}
      {(renderContent || children) && (
        <div className="mt-6" role="tabpanel" id={`tabpanel-${activeTab}`}>
          {renderContent ? renderContent(activeTab) : children}
        </div>
      )}
    </div>
  );
};

// Compound component for tab panels
export interface TabPanelProps {
  tabId: string;
  activeTab: string;
  children: React.ReactNode;
  className?: string;
}

export const TabPanel: React.FC<TabPanelProps> = ({
  tabId,
  activeTab,
  children,
  className = ''
}) => {
  if (tabId !== activeTab) return null;

  return (
    <div className={className} role="tabpanel" id={`tabpanel-${tabId}`}>
      {children}
    </div>
  );
};

export default TabContainer;