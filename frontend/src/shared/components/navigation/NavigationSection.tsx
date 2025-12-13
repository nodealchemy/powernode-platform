// Navigation Section Component
import React from 'react';
import { ChevronDown } from 'lucide-react';
import { NavigationSection as NavSection } from '@/shared/types/navigation';
import { NavigationItem } from './NavigationItem';
import { useNavigation } from '@/shared/hooks/NavigationContext';

interface NavigationSectionProps {
  section: NavSection;
  isCollapsed?: boolean;
}

export const NavigationSection: React.FC<NavigationSectionProps> = ({ 
  section, 
  isCollapsed = false 
}) => {
  const { state, updateState, hasPermission } = useNavigation();

  // Check section permissions - ONLY use permissions, ignore roles
  if (!hasPermission(section.permissions)) {
    return null;
  }

  // Filter items by permissions - ONLY use permissions, ignore roles
  const visibleItems = section.items.filter(item => 
    hasPermission(item.permissions)
  );

  // Don't render if no visible items
  if (visibleItems.length === 0) {
    return null;
  }

  const isExpanded = state.expandedSections.includes(section.id);

  const handleToggleSection = () => {
    if (section.collapsible !== false) {
      const newExpandedSections = isExpanded
        ? state.expandedSections.filter(id => id !== section.id)
        : [...state.expandedSections, section.id];

      updateState({
        expandedSections: newExpandedSections
      });
    }
  };

  return (
    <div className="space-y-1">
      {/* Section Header */}
      {!isCollapsed && (
        <div 
          className={`flex items-center justify-between px-3 py-2 ${
            section.collapsible !== false ? 'cursor-pointer hover:bg-theme-surface-hover rounded-md' : ''
          }`}
          onClick={section.collapsible !== false ? handleToggleSection : undefined}
        >
          <p className="text-xs font-semibold text-theme-tertiary uppercase tracking-wider">
            {section.name}
          </p>
          {section.collapsible !== false && (
            <ChevronDown 
              className={`w-4 h-4 text-theme-tertiary transition-transform duration-200 ${
                isExpanded ? 'rotate-180' : ''
              }`}
            />
          )}
        </div>
      )}

      {/* Section Items */}
      {(isCollapsed || isExpanded || section.collapsible === false) && (
        <div className="space-y-1">
          {visibleItems.map((item) => (
            <NavigationItem
              key={item.id}
              item={item}
              isCollapsed={isCollapsed}
              showTooltip={isCollapsed}
            />
          ))}
        </div>
      )}

      {/* Separator */}
      {!isCollapsed && section.id !== 'main' && (
        <div className="border-t border-theme my-2"></div>
      )}
    </div>
  );
};

export default NavigationSection;