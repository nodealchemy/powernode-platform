// Navigation Item Component
import React, { useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { ExternalLink, icons } from 'lucide-react';
import { NavigationItem as NavItem } from '@/shared/types/navigation';
import { useNavigation } from '@/shared/hooks/NavigationContext';

interface NavigationItemProps {
  item: NavItem;
  level?: number;
  isCollapsed?: boolean;
  showTooltip?: boolean;
}

export const NavigationItem: React.FC<NavigationItemProps> = ({ 
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

  // Check if item is active - exact match or most specific prefix match
  const isActive = (() => {
    const pathname = location.pathname;

    // Exact match is always active
    if (pathname === item.href) {
      return true;
    }

    // Dashboard must be exact match only
    if (item.href === '/app') {
      return false;
    }

    // Section overview pages (like /app/ai, /app/business) - exact match only
    const hrefSegments = item.href.split('/').filter(Boolean);
    if (hrefSegments.length === 2 && hrefSegments[0] === 'app') {
      return false;
    }

    // For deeper paths, check if this is a prefix match
    // Only match if pathname starts with href followed by '/' or end
    // This prevents /app/ai/workflows from matching when on /app/ai/workflows/templates
    // if templates is its own nav item
    if (pathname.startsWith(item.href)) {
      const nextChar = pathname.charAt(item.href.length);
      // Only match if this is a parent path (next char is /) but NOT if
      // the next segment is also a named route in navigation
      // Check if it's a direct child route (like /123, /edit) vs another nav item (/templates)
      if (nextChar === '/') {
        const remainingPath = pathname.slice(item.href.length);
        // Don't match if the remaining path matches another known nav route
        // Common nav sub-routes to exclude
        const knownSubRoutes = ['/templates', '/monitoring', '/import'];
        const hasKnownSubRoute = knownSubRoutes.some(route =>
          remainingPath === route || remainingPath.startsWith(route + '/')
        );
        return !hasKnownSubRoute;
      }
    }

    return false;
  })();

  // Render icon — supports both React components and Lucide icon name strings
  const renderIcon = () => {
    if (typeof item.icon === 'string') {
      const LucideIcon = icons[item.icon as keyof typeof icons];
      if (LucideIcon) {
        return <LucideIcon className="w-5 h-5" />;
      }
      return <icons.Puzzle className="w-5 h-5" />;
    }
    const IconComponent = item.icon as React.ComponentType<{ className?: string }>;
    return <IconComponent className="w-5 h-5" />;
  };

  // Handle special actions and provide fallback navigation
  const handleClick = (e: React.MouseEvent) => {
    if (item.id === 'logout') {
      e.preventDefault();
      // Handle logout logic here
      return;
    }

    // Handle custom actions (e.g., open-chat dispatches CustomEvent instead of navigating)
    if (item.action === 'open-chat') {
      e.preventDefault();
      window.dispatchEvent(new CustomEvent('powernode:open-chat-maximized'));
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
      ? 'bg-theme-surface-selected text-theme-link'
        + (isCollapsed ? ' ring-2 ring-theme-focus ring-inset' : ' border-theme-focus')
      : 'text-theme-secondary hover:bg-theme-surface-hover hover:text-theme-primary'
        + (isCollapsed ? '' : ' border-transparent')
    }
    group flex items-center
    ${isCollapsed ? 'justify-center px-3 py-3' : 'px-3 py-2 border-l-4'}
    text-sm font-medium rounded-md transition-colors duration-150
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