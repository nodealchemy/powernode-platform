/**
 * Marketplace Type Filter
 *
 * Simple toggle buttons to filter marketplace items by type.
 * Supports All, Workflows, Pipelines, Integrations, and Prompts.
 */


import type { MarketplaceItemType } from '../types/marketplace';
import { ALL_MARKETPLACE_TYPES, getTypeDisplayName } from '../types/marketplace';

interface TypeFilterProps {
  selectedTypes: MarketplaceItemType[];
  onChange: (types: MarketplaceItemType[]) => void;
}

const ALL_TYPES = ALL_MARKETPLACE_TYPES;

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
    <div className="flex items-center gap-2 flex-wrap category-filter" data-testid="category-filter">
      <span className="text-sm text-theme-tertiary mr-2">Filter by type:</span>

      <button
        onClick={handleAllClick}
        className={getButtonClass(isAllSelected)}
      >
        All
      </button>

      {ALL_TYPES.map((type) => (
        <button
          key={type}
          onClick={() => handleTypeToggle(type)}
          className={getButtonClass(selectedTypes.includes(type) && !isAllSelected)}
        >
          {getTypeDisplayName(type)}s
        </button>
      ))}
    </div>
  );
};
