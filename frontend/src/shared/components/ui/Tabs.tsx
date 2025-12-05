import React, { createContext, useContext, useState } from 'react';

interface TabsContextType {
  activeTab: string;
  setActiveTab: (tab: string) => void;
}

const TabsContext = createContext<TabsContextType | undefined>(undefined);

export interface TabsProps {
  defaultValue?: string;
  value?: string;
  onValueChange?: (value: string) => void;
  children: React.ReactNode;
  className?: string;
}

export const Tabs: React.FC<TabsProps> = ({ 
  defaultValue, 
  value,
  onValueChange,
  children, 
  className = '' 
}) => {
  const [internalActiveTab, setInternalActiveTab] = useState(defaultValue || '');
  
  // Use controlled state if value is provided, otherwise use internal state
  const activeTab = value !== undefined ? value : internalActiveTab;
  const setActiveTab = value !== undefined ? onValueChange || (() => {}) : setInternalActiveTab;

  return (
    <TabsContext.Provider value={{ activeTab, setActiveTab }}>
      <div className={className}>
        {children}
      </div>
    </TabsContext.Provider>
  );
};

export interface TabsListProps {
  children: React.ReactNode;
  className?: string;
}

export const TabsList: React.FC<TabsListProps> = ({ 
  children, 
  className = '' 
}) => {
  return (
    <div className={`flex border-b border-theme-border bg-theme-surface ${className}`}>
      {children}
    </div>
  );
};

export interface TabsTriggerProps {
  value: string;
  children: React.ReactNode;
  className?: string;
}

export const TabsTrigger: React.FC<TabsTriggerProps> = ({ 
  value, 
  children, 
  className = '' 
}) => {
  const context = useContext(TabsContext);
  
  if (!context) {
    throw new Error('TabsTrigger must be used within a Tabs component');
  }

  const { activeTab, setActiveTab } = context;
  const isActive = activeTab === value;

  return (
    <button
      type="button"
      onClick={() => setActiveTab(value)}
      className={`
        px-4 py-2 font-medium text-sm transition-colors duration-200
        border-b-2 whitespace-nowrap
        ${isActive 
          ? 'border-theme-interactive-primary text-theme-interactive-primary bg-theme-surface-selected' 
          : 'border-transparent text-theme-muted hover:text-theme-primary hover:bg-theme-surface-hover'
        }
        ${className}
      `.replace(/\s+/g, ' ').trim()}
    >
      {children}
    </button>
  );
};

export interface TabsContentProps {
  value: string;
  children: React.ReactNode;
  className?: string;
}

export const TabsContent: React.FC<TabsContentProps> = ({ 
  value, 
  children, 
  className = '' 
}) => {
  const context = useContext(TabsContext);
  
  if (!context) {
    throw new Error('TabsContent must be used within a Tabs component');
  }

  const { activeTab } = context;
  
  if (activeTab !== value) {
    return null;
  }

  return (
    <div className={`mt-4 ${className}`}>
      {children}
    </div>
  );
};