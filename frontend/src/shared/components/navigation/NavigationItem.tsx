// Navigation Item Component
import React, { useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { ExternalLink } from 'lucide-react';
import { NavigationItem as NavItem } from '@/shared/types/navigation';
import { useNavigation } from '@/shared/hooks/NavigationContext';

interface NavigationItemProps {
  item: NavItem;
  level?: number;
  isCollapsed?: boolean;
  showTooltip?: boolean;
}

export const NavigationItem: React.FC<NavigationItemProps> = ({ 
NavigationItem.displayName = 'NavigationItem';
  item, 
  level = 0, 
  isCollapsed = false,
  showTooltip = false 
}) => {
  const location = useLocation();
  const navigate = useNavigate();
  const { hasPermission } = useNavigation();
  const [hoveredItem, setHoveredItem] = useState<string | null>(null);

  // Check permissions - ONLY use permissions, ignore roles
  if (!hasPermission(item.permissions)) {
    return null;
  }

  // Check if item is active
  const isActive = item.href === '/app' 
    ? location.pathname === item.href
    : location.pathname.startsWith(item.href);

  // Render icon
  const renderIcon = () => {
    if (typeof item.icon === 'string') {
      return <span className="text-lg">{item.icon}</span>;
    }
    const IconComponent = item.icon as React.ComponentType<any>;
    return <IconComponent className="w-5 h-5" />;
  };

  // Handle special actions and provide fallback navigation
  const handleClick = (e: React.MouseEvent) => {
    // Debug logging for navigation issues
    
    if (item.id === 'logout') {
      e.preventDefault();
      // Handle logout logic here
      return;
    }

    // Fallback navigation mechanism for reliability
    if (!item.isExternal && item.href) {
      // Prevent default Link behavior temporarily to test programmatic navigation
      e.preventDefault();
      
      // Use programmatic navigation as a more reliable method
      navigate(item.href);
    }
  };

  // Render badge if present
  const renderBadge = () => {
    if (!item.badge) return null;
    return (
      <span className="inline-flex items-center justify-center px-2 py-1 text-xs font-bold leading-none text-white bg-theme-error rounded-full">
        {item.badge}
      </span>
    );
  };

  const itemClasses = `
    ${isActive
      ? 'bg-theme-surface-selected border-theme-focus text-theme-link'
      : 'border-transparent text-theme-secondary hover:bg-theme-surface-hover hover:text-theme-primary'
    } 
    group flex items-center 
    ${isCollapsed ? 'justify-center px-3 py-3' : 'px-3 py-2'} 
    text-sm font-medium border-l-4 rounded-md transition-all duration-150
    ${level > 0 ? 'ml-4' : ''}
  `;

  const content = (
    <>
      <span className={`sidebar-icon-transition ${isCollapsed ? '' : 'mr-3'}`}>
        {renderIcon()}
      </span>
      {!isCollapsed && (
        <span className="sidebar-content-transition flex-1">{item.name}</span>
      )}
      {!isCollapsed && item.isExternal && (
        <ExternalLink className="w-4 h-4 ml-2 text-theme-tertiary" />
      )}
      {!isCollapsed && renderBadge()}
    </>
  );

  // Tooltip for collapsed state
  const tooltip = isCollapsed && showTooltip && hoveredItem === item.id && (
    <div className="absolute left-full top-0 ml-2 px-2 py-1 bg-theme-surface-pressed text-theme-inverse text-xs rounded-md whitespace-nowrap z-50 pointer-events-none shadow-md">
      {item.name}
      {item.description && (
        <div className="text-xs opacity-75 mt-1">{item.description}</div>
      )}
      <div className="absolute left-0 top-1/2 transform -translate-y-1/2 -translate-x-1 border-4 border-transparent border-r-gray-900 dark:border-r-gray-100"></div>
    </div>
  );

  return (
    <div
      className="relative"
      onMouseEnter={() => setHoveredItem(item.id)}
      onMouseLeave={() => setHoveredItem(null)}
    >
      {item.isExternal ? (
        <a
          href={item.href}
          className={itemClasses}
          title={isCollapsed ? item.name : undefined}
          target="_blank"
          rel="noopener noreferrer"
          onClick={handleClick}
        >
          {content}
        </a>
      ) : (
        <Link
          to={item.href}
          className={itemClasses}
          title={isCollapsed ? item.name : undefined}
          onClick={handleClick}
        >
          {content}
        </Link>
      )}
      {tooltip}
    </div>
  );
};

export default NavigationItem;