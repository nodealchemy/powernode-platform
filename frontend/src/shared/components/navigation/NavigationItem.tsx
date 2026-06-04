// Navigation Item Component
import React, { useState, useMemo } from 'react';
import { Link, useLocation } from 'react-router-dom';
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
  const { hasPermission, config } = useNavigation();
  const [hoveredItem, setHoveredItem] = useState<string | null>(null);

  // Collect all sibling nav hrefs for "more specific match" checks.
  // Computed before the permission gate below so every hook runs
  // unconditionally on every render (Rules of Hooks).
  const allNavHrefs = useMemo(() => {
    const hrefs = new Set<string>();
    config?.items?.forEach(i => hrefs.add(i.href));
    config?.sections?.forEach(s => s.items.forEach(i => hrefs.add(i.href)));
    return hrefs;
  }, [config]);

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
    // unless activeMatch is explicitly set to 'prefix' (e.g., Trading hub)
    const hrefSegments = item.href.split('/').filter(Boolean);
    if (hrefSegments.length === 2 && hrefSegments[0] === 'app' && item.activeMatch !== 'prefix') {
      return false;
    }

    // For deeper paths, check if this is a prefix match
    // Only match if pathname starts with href followed by '/' or end
    if (pathname.startsWith(item.href)) {
      const nextChar = pathname.charAt(item.href.length);
      if (nextChar === '/' || nextChar === '') {
        // Yield to a more specific sibling nav item that also matches this path.
        // E.g., /app/trading (prefix) should NOT stay active when on /app/trading/portfolio
        // because /app/trading/portfolio is its own nav item.
        const hasMoreSpecificMatch = Array.from(allNavHrefs).some(href =>
          href !== item.href
          && href.length > item.href.length
          && href.startsWith(item.href)
          && (pathname === href || pathname.startsWith(href + '/'))
        );
        if (hasMoreSpecificMatch) {
          return false;
        }

        if (nextChar === '/') {
          const remainingPath = pathname.slice(item.href.length);
          const knownSubRoutes = ['/templates', '/monitoring', '/import'];
          const hasKnownSubRoute = knownSubRoutes.some(route =>
            remainingPath === route || remainingPath.startsWith(route + '/')
          );
          return !hasKnownSubRoute;
        }
        return true;
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

  // Handle special actions — regular navigation is handled natively by <Link>
  const handleClick = (e: React.MouseEvent) => {
    if (item.id === 'logout') {
      e.preventDefault();
      return;
    }

    if (item.action === 'open-chat') {
      e.preventDefault();
      window.dispatchEvent(new CustomEvent('powernode:open-chat-maximized'));
      return;
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