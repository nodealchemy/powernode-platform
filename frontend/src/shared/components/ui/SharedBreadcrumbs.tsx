// Shared Breadcrumbs Component
import React from 'react';
import { useLocation, Link } from 'react-router-dom';
import { ChevronRight, Home } from 'lucide-react';

interface BreadcrumbItem {
  label: string;
  href?: string;
  icon?: React.ComponentType<any>;
}

interface SharedBreadcrumbsProps {
  items?: BreadcrumbItem[];
  className?: string;
  showHome?: boolean;
}

export const SharedBreadcrumbs: React.FC<SharedBreadcrumbsProps> = ({ 
  items = [], 
  className = '',
  showHome = true 
}) => {
  const location = useLocation();

  // Auto-generate breadcrumbs based on current path if no items provided
  const generateBreadcrumbs = (): BreadcrumbItem[] => {
    if (items.length > 0) return items;

    const pathSegments = location.pathname.split('/').filter(Boolean);
    const breadcrumbs: BreadcrumbItem[] = [];

    if (showHome) {
      breadcrumbs.push({ label: 'Dashboard', href: '/app', icon: Home });
    }

    // Build breadcrumbs from path segments
    let currentPath = '';
    pathSegments.forEach((segment, index) => {
      currentPath += `/${segment}`;
      
      // Skip the first 'dashboard' segment if we already have home
      if (segment === 'dashboard' && showHome) return;

      // Format segment name
      let label = segment.replace(/-/g, ' ').replace(/([A-Z])/g, ' $1').trim();
      label = label.charAt(0).toUpperCase() + label.slice(1);

      // Special cases for better readability
      const labelMap: Record<string, string> = {
        'admin settings': 'Admin Settings',
        'payment gateways': 'Payment Gateways',
        'email': 'Email Settings',
        'webhooks': 'Webhooks',
        'security': 'Security',
        'maintenance': 'Maintenance',
        'performance': 'Performance',
        'account': 'Account Management',
        'analytics': 'Analytics',
        'business': 'Business Management',
        'system': 'System Management'
      };

      const finalLabel = labelMap[label.toLowerCase()] || label;
      
      // Don't add href for the current (last) item
      const isLast = index === pathSegments.length - 1;
      breadcrumbs.push({
        label: finalLabel,
        href: isLast ? undefined : currentPath
      });
    });

    return breadcrumbs;
  };

  const breadcrumbItems = generateBreadcrumbs();

  if (breadcrumbItems.length === 0) return null;

  return (
    <nav className={`flex items-center space-x-1 text-sm text-theme-secondary ${className}`} aria-label="Breadcrumb">
      <ol className="flex items-center space-x-1">
        {breadcrumbItems.map((item, index) => {
          const isLast = index === breadcrumbItems.length - 1;
          
          return (
            <li key={index} className="flex items-center">
              {index > 0 && (
                <ChevronRight className="w-4 h-4 mx-1 text-theme-tertiary" />
              )}
              
              {item.href ? (
                <Link
                  to={item.href}
                  className="flex items-center hover:text-theme-primary transition-colors duration-150"
                >
                  {item.icon && <item.icon className="w-4 h-4 mr-1" />}
                  <span>{item.label}</span>
                </Link>
              ) : (
                <span className={`flex items-center ${isLast ? 'text-theme-primary font-medium' : ''}`}>
                  {item.icon && <item.icon className="w-4 h-4 mr-1" />}
                  {item.label}
                </span>
              )}
            </li>
          );
        })}
      </ol>
    </nav>
  );
};

export default SharedBreadcrumbs;