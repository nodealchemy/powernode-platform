/**
 * Marketplace Type Filter
 *
 * Simple toggle buttons to filter marketplace items by type.
 * Supports All, Apps, Plugins, and Templates.
 */


import type { MarketplaceItemType } from '../types/unified';

interface TypeFilterProps {
  selectedTypes: MarketplaceItemType[];
  onChange: (types: MarketplaceItemType[]) => void;
}

const ALL_TYPES: MarketplaceItemType[] = ['app', 'plugin', 'template'];

export const TypeFilter: React.FC<TypeFilterProps> = ({ selectedTypes, onChange }) => {
  const isAllSelected = selectedTypes.length === 0 || selectedTypes.length === ALL_TYPES.length;

  const handleTypeToggle = (type: MarketplaceItemType) => {
    if (selectedTypes.includes(type)) {
      const newTypes = selectedTypes.filter((t) => t !== type);
      onChange(newTypes.length === 0 ? ALL_TYPES : newTypes);
    } else {
      onChange([...selectedTypes, type]);
    }
  };

  const handleAllClick = () => {
    onChange(ALL_TYPES);
  };

  const getButtonClass = (isActive: boolean) => {
    return `px-4 py-2 rounded-lg font-medium transition-colors ${
      isActive
        ? 'bg-theme-info text-white'
        : 'bg-theme-surface text-theme-tertiary hover:bg-theme-surface-hover border border-theme'
    }`;
  };

  return (
    <div className="flex items-center gap-2">
      <span className="text-sm text-theme-tertiary mr-2">Filter by type:</span>

      <button
        onClick={handleAllClick}
        className={getButtonClass(isAllSelected)}
      >
        All
      </button>

      <button
        onClick={() => handleTypeToggle('app')}
        className={getButtonClass(selectedTypes.includes('app') && !isAllSelected)}
      >
        Apps
      </button>

      <button
        onClick={() => handleTypeToggle('plugin')}
        className={getButtonClass(selectedTypes.includes('plugin') && !isAllSelected)}
      >
        Plugins
      </button>

      <button
        onClick={() => handleTypeToggle('template')}
        className={getButtonClass(selectedTypes.includes('template') && !isAllSelected)}
      >
        Templates
      </button>
    </div>
  );
};
