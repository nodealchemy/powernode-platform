import React from 'react';
import { Link, useLocation } from 'react-router-dom';

interface Tab {
  id: string;
  label: string;
  path: string;
  icon?: string;
  badge?: string | number;
  disabled?: boolean;
}

interface TabNavigationProps {
  tabs: Tab[];
  basePath: string;
  className?: string;
}

export const TabNavigation: React.FC<TabNavigationProps> = ({ tabs, basePath, className = '' }) => {
  const location = useLocation();
  const currentPath = location.pathname;

  return (
    <div className={`border-b border-theme ${className}`}>
      <nav className="-mb-px flex space-x-8" aria-label="Tabs">
        {tabs.map((tab) => {
          const isActive = currentPath === tab.path || currentPath.startsWith(`${tab.path}/`);
          const isDisabled = tab.disabled;

          const tabClass = `
            ${isActive 
              ? 'border-theme-interactive-primary text-theme-interactive-primary' 
              : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme-tertiary'
            }
            ${isDisabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}
            whitespace-nowrap py-4 px-1 border-b-2 font-medium text-sm flex items-center space-x-2 transition-all duration-150
          `;

          if (isDisabled) {
            return (
              <span key={tab.id} className={tabClass}>
                {tab.icon && <span className="text-base">{tab.icon}</span>}
                <span>{tab.label}</span>
                {tab.badge && (
                  <span className="ml-2 px-2 py-0.5 text-xs rounded-full bg-theme-surface-hover text-theme-secondary">
                    {tab.badge}
                  </span>
                )}
              </span>
            );
          }

          return (
            <Link
              key={tab.id}
              to={tab.path}
              className={tabClass}
              aria-current={isActive ? 'page' : undefined}
            >
              {tab.icon && <span className="text-base">{tab.icon}</span>}
              <span>{tab.label}</span>
              {tab.badge && (
                <span className={`ml-2 px-2 py-0.5 text-xs rounded-full ${
                  isActive 
                    ? 'bg-theme-interactive-primary text-white' 
                    : 'bg-theme-surface-hover text-theme-secondary'
                }`}>
                  {tab.badge}
                </span>
              )}
            </Link>
          );
        })}
      </nav>
    </div>
  );
};

interface MobileTabNavigationProps extends TabNavigationProps {
  currentTabLabel?: string;
}

export const MobileTabNavigation: React.FC<MobileTabNavigationProps> = ({ 
  tabs, 
  basePath, 
  currentTabLabel,
  className = '' 
}) => {
  const location = useLocation();
  const currentPath = location.pathname;
  const currentTab = tabs.find(tab => currentPath === tab.path || currentPath.startsWith(`${tab.path}/`));
  // const displayLabel = currentTabLabel || currentTab?.label || 'Select';

  return (
    <div className={`sm:hidden ${className}`}>
      <label htmlFor="tabs" className="sr-only">
        Select a tab
      </label>
      <select
        id="tabs"
        name="tabs"
        className="block w-full rounded-md border-theme bg-theme-surface px-3 py-2 text-theme-primary focus:border-theme-focus focus:outline-none focus:ring-2 focus:ring-theme-focus"
        value={currentTab?.path || ''}
        onChange={(e) => {
          if (e.target.value) {
            window.location.href = e.target.value;
          }
        }}
      >
        {tabs.map((tab) => (
          <option key={tab.id} value={tab.path} disabled={tab.disabled}>
            {tab.icon && `${tab.icon} `}{tab.label}{tab.badge ? ` (${tab.badge})` : ''}
          </option>
        ))}
      </select>
    </div>
  );
};