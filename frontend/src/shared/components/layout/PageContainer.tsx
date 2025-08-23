import React, { useEffect } from 'react';
import { SharedBreadcrumbs } from '../ui/SharedBreadcrumbs';
import { useBreadcrumb } from '@/shared/hooks/BreadcrumbContext';

export interface BreadcrumbItem {
  label: string;
  href?: string;
  icon?: React.ComponentType<any> | string;
}

export interface PageAction {
  id: string;
  label: string;
  onClick: () => void;
  variant?: 'primary' | 'secondary' | 'outline' | 'danger' | 'warning' | 'success';
  icon?: React.ComponentType<any> | string;
  disabled?: boolean;
  size?: 'sm' | 'md' | 'lg';
}

export interface PageContainerProps {
  title: string;
  description?: string;
  breadcrumbs?: BreadcrumbItem[];
  actions?: PageAction[];
  className?: string;
  children: React.ReactNode;
  pageId?: string;
  useDynamicBreadcrumbs?: boolean;
}

export const PageContainer: React.FC<PageContainerProps> = ({
  title,
  description,
  breadcrumbs,
  actions,
  className = '',
  children,
  pageId,
  useDynamicBreadcrumbs = false
}) => {
  const { setBreadcrumbs, getCurrentBreadcrumbs, setCurrentPage } = useBreadcrumb();
  const getButtonClasses = (variant: PageAction['variant'] = 'secondary', size: PageAction['size'] = 'md') => {
    const baseClasses = 'btn-theme';
    const sizeClass = size === 'sm' ? 'btn-theme-sm' : size === 'lg' ? 'btn-theme-lg' : '';
    
    let variantClass = '';
    switch (variant) {
      case 'primary':
        variantClass = 'btn-theme-primary';
        break;
      case 'outline':
        variantClass = 'btn-theme-outline';
        break;
      case 'danger':
        variantClass = 'btn-theme-danger';
        break;
      case 'secondary':
      default:
        variantClass = 'btn-theme-secondary';
        break;
    }
    
    return `${baseClasses} ${variantClass} ${sizeClass}`.trim();
  };

  const renderIcon = (icon: React.ComponentType<any> | string | undefined, className: string = '') => {
    if (!icon) return null;
    
    if (typeof icon === 'string') {
      return <span className={className}>{icon}</span>;
    }
    
    const IconComponent = icon;
    return <IconComponent className={className} />;
  };

  // Handle dynamic breadcrumbs
  useEffect(() => {
    if (useDynamicBreadcrumbs && breadcrumbs) {
      setBreadcrumbs(breadcrumbs);
    }
    
    if (pageId) {
      setCurrentPage(pageId);
    }
  }, [useDynamicBreadcrumbs, breadcrumbs, pageId, setBreadcrumbs, setCurrentPage]);

  // Determine which breadcrumbs to display
  const displayBreadcrumbs = useDynamicBreadcrumbs ? getCurrentBreadcrumbs() : breadcrumbs;

  return (
    <div className={`space-y-6 ${className}`}>
      {/* Breadcrumbs */}
      {displayBreadcrumbs && displayBreadcrumbs.length > 0 && (
        <SharedBreadcrumbs 
          items={displayBreadcrumbs.map(item => ({
            label: item.label,
            href: item.href,
            icon: typeof item.icon === 'string' ? undefined : item.icon
          }))}
          className="mb-4"
        />
      )}

      {/* Page Header */}
      <div className="flex justify-between items-start">
        <div className="flex-1">
          <h1 className="text-2xl font-bold text-theme-primary">{title}</h1>
          {description && (
            <p className="text-theme-secondary mt-1">
              {description}
            </p>
          )}
        </div>
        
        {/* Page Actions */}
        {actions && actions.length > 0 && (
          <div className="flex items-center space-x-3 ml-6">
            {actions.map((action) => (
              <button
                key={action.id}
                onClick={action.onClick}
                disabled={action.disabled}
                className={`${getButtonClasses(action.variant, action.size)} ${action.disabled ? 'opacity-50 cursor-not-allowed' : ''}`}
              >
                {renderIcon(action.icon, 'w-4 h-4 mr-2')}
                {action.label}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Page Content */}
      <div>
        {children}
      </div>
    </div>
  );
};