import React, { useState, useEffect } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { cn } from '@/shared/utils/cn';

export interface Tab {
  id: string;
  label: string;
  icon?: string | React.ReactNode;
  path?: string;
  content?: React.ReactNode;
  disabled?: boolean;
  badge?: string | number;
}

export interface TabContainerProps {
  tabs: Tab[];
  activeTab?: string;
  onTabChange?: (tabId: string) => void;
  basePath?: string;
  variant?: 'default' | 'pills' | 'underline';
  size?: 'sm' | 'md' | 'lg';
  className?: string;
  contentClassName?: string;
  showContent?: boolean;
}

export const TabContainer: React.FC<TabContainerProps> = ({
TabContainer.displayName = 'TabContainer';
  tabs,
  activeTab: controlledActiveTab,
  onTabChange,
  basePath,
  variant = 'underline',
  size = 'md',
  className,
  contentClassName,
  showContent = true
}) => {
  const navigate = useNavigate();
  const location = useLocation();
  const [internalActiveTab, setInternalActiveTab] = useState(tabs[0]?.id || '');
  
  // Determine active tab from URL if using routing
  const activeTabFromUrl = basePath ? 
    tabs.find(tab => {
      const tabPath = tab.path || `/${tab.id}`;
      const fullPath = `${basePath}${tabPath === '/' ? '' : tabPath}`;
      return location.pathname === fullPath || location.pathname.startsWith(fullPath + '/');
    })?.id : null;
  
  const activeTab = controlledActiveTab || activeTabFromUrl || internalActiveTab;
  
  useEffect(() => {
    if (!controlledActiveTab && !activeTabFromUrl && tabs.length > 0) {
      setInternalActiveTab(tabs[0].id);
    }
  }, [controlledActiveTab, activeTabFromUrl, tabs]);
  
  const handleTabClick = (tab: Tab) => {
    if (tab.disabled) return;
    
    if (basePath && tab.path !== undefined) {
      const fullPath = tab.path === '/' ? basePath : `${basePath}${tab.path}`;
      navigate(fullPath);
    }
    
    if (onTabChange) {
      onTabChange(tab.id);
    } else {
      setInternalActiveTab(tab.id);
    }
  };
  
  const getTabClasses = (tab: Tab) => {
    const isActive = activeTab === tab.id;
    const sizeClasses = {
      sm: 'text-sm py-1.5 px-3',
      md: 'text-sm py-2 px-4',
      lg: 'text-base py-2.5 px-5'
    };
    
    const sizeClass = Object.prototype.hasOwnProperty.call(sizeClasses, size) ? sizeClasses[size as keyof typeof sizeClasses] : sizeClasses.md;
    const baseClasses = cn(
      'inline-flex items-center gap-2 font-medium transition-colors',
      sizeClass,
      tab.disabled && 'opacity-50 cursor-not-allowed'
    );
    
    if (variant === 'underline') {
      return cn(
        baseClasses,
        'border-b-2',
        isActive
          ? 'border-theme-interactive-primary text-theme-interactive-primary'
          : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme-border',
        !tab.disabled && 'cursor-pointer'
      );
    }
    
    if (variant === 'pills') {
      return cn(
        baseClasses,
        'rounded-md',
        isActive
          ? 'bg-theme-interactive-primary text-white'
          : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-hover',
        !tab.disabled && 'cursor-pointer'
      );
    }
    
    // Default variant
    return cn(
      baseClasses,
      'border rounded-md',
      isActive
        ? 'bg-theme-surface border-theme-interactive-primary text-theme-interactive-primary'
        : 'border-theme bg-theme-background text-theme-secondary hover:text-theme-primary hover:bg-theme-hover',
      !tab.disabled && 'cursor-pointer'
    );
  };
  
  const getContainerClasses = () => {
    if (variant === 'underline') {
      return 'border-b border-theme -mb-px';
    }
    if (variant === 'pills') {
      return 'bg-theme-muted p-1 rounded-lg';
    }
    return 'bg-theme-background p-1 rounded-lg border border-theme';
  };
  
  const renderIcon = (icon: string | React.ReactNode) => {
    if (typeof icon === 'string') {
      return <span className="text-base">{icon}</span>;
    }
    return icon;
  };
  
  const activeTabContent = tabs.find(tab => tab.id === activeTab)?.content;
  
  return (
    <div className={className}>
      {/* Tab Navigation */}
      <div className={getContainerClasses()}>
        <div className="flex space-x-1">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => handleTabClick(tab)}
              className={getTabClasses(tab)}
              disabled={tab.disabled}
              aria-selected={activeTab === tab.id}
              role="tab"
            >
              {tab.icon && renderIcon(tab.icon)}
              <span>{tab.label}</span>
              {tab.badge !== undefined && (
                <span className="ml-1.5 px-2 py-0.5 text-xs rounded-full bg-theme-badge text-theme-badge-text">
                  {tab.badge}
                </span>
              )}
            </button>
          ))}
        </div>
      </div>
      
      {/* Tab Content */}
      {showContent && activeTabContent && (
        <div className={cn('mt-6', contentClassName)}>
          {activeTabContent}
        </div>
      )}
    </div>
  );
};

// Mobile-optimized tab navigation
export const MobileTabContainer: React.FC<TabContainerProps> = (props) => {
TabContainer.displayName = 'TabContainer';
  return (
    <div className="sm:hidden">
      <select
        value={props.activeTab || props.tabs[0]?.id}
        onChange={(e) => {
          const tab = props.tabs.find(t => t.id === e.target.value);
          if (tab && props.onTabChange) {
            props.onTabChange(tab.id);
          }
        }}
        className="block w-full pl-3 pr-10 py-2 text-base border-theme bg-theme-surface focus:outline-none focus:ring-theme-focus focus:border-theme-focus sm:text-sm rounded-md"
      >
        {props.tabs.map((tab) => (
          <option key={tab.id} value={tab.id} disabled={tab.disabled}>
            {tab.label} {tab.badge ? `(${tab.badge})` : ''}
          </option>
        ))}
      </select>
    </div>
  );
};

export default TabContainer;