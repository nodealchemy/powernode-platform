/**
 * Unified Marketplace Item Card
 *
 * Polymorphic card component that displays apps, plugins, or templates
 * with a consistent interface across all marketplace item types.
 */


import { Package, Star, CheckCircle, Download } from 'lucide-react';
import type { MarketplaceItem } from '../types/unified';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';

interface ItemCardProps {
  item: MarketplaceItem;
  showInstallButton?: boolean;
  onViewDetails: (itemId: string) => void;
  onInstall?: (itemId: string) => void;
}

export const ItemCard: React.FC<ItemCardProps> = ({
  item,
  showInstallButton = true,
  onViewDetails,
  onInstall
}) => {
  const getTypeBadgeColor = (type: string) => {
    switch (type) {
      case 'app':
        return 'bg-theme-info bg-opacity-10 text-theme-info';
      case 'plugin':
        return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'template':
        return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      default:
        return 'bg-theme-surface text-theme-primary';
    }
  };

  const handleInstall = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (onInstall) {
      onInstall(item.id);
    }
  };

  const handleViewDetails = () => {
    onViewDetails(item.id);
  };

  return (
    <Card
      className="hover:border-theme-primary transition-all duration-200 cursor-pointer h-full flex flex-col"
      onClick={handleViewDetails}
    >
      <div className="p-4 flex-1 flex flex-col">
        {/* Header with icon and type badge */}
        <div className="flex items-start justify-between mb-3">
          <div className="h-12 w-12 bg-theme-surface rounded-lg flex items-center justify-center border border-theme flex-shrink-0">
            {item.icon ? (
              <img
                src={item.icon}
                alt={item.name}
                className="h-8 w-8 object-contain"
              />
            ) : (
              <Package className="h-6 w-6 text-theme-tertiary" />
            )}
          </div>

          <div className="flex items-center gap-2">
            {/* Verified badge */}
            {item.is_verified && (
              <div className="flex items-center gap-1 text-theme-info" title="Verified">
                <CheckCircle className="h-4 w-4" />
              </div>
            )}

            {/* Type badge */}
            <span
              className={`px-2 py-1 rounded text-xs font-medium ${getTypeBadgeColor(item.type)}`}
            >
              {item.type.charAt(0).toUpperCase() + item.type.slice(1)}
            </span>
          </div>
        </div>

        {/* Title and description */}
        <div className="flex-1">
          <h3 className="text-lg font-semibold text-theme-primary mb-1 line-clamp-1">
            {item.name}
          </h3>

          <p className="text-sm text-theme-tertiary mb-3 line-clamp-2">
            {item.description}
          </p>

          {/* Tags */}
          {item.tags && item.tags.length > 0 && (
            <div className="flex flex-wrap gap-1 mb-3">
              {item.tags.slice(0, 3).map((tag, index) => (
                <span
                  key={index}
                  className="px-2 py-0.5 bg-theme-surface text-theme-tertiary text-xs rounded border border-theme"
                >
                  {tag}
                </span>
              ))}
              {item.tags.length > 3 && (
                <span className="px-2 py-0.5 text-theme-tertiary text-xs">
                  +{item.tags.length - 3} more
                </span>
              )}
            </div>
          )}
        </div>

        {/* Footer with stats and actions */}
        <div className="flex items-center justify-between mt-auto pt-3 border-t border-theme">
          {/* Stats */}
          <div className="flex items-center gap-4 text-sm text-theme-tertiary">
            {/* Rating */}
            <div className="flex items-center gap-1">
              <Star className="h-4 w-4 text-theme-warning fill-current" />
              <span>{item.rating.toFixed(1)}</span>
            </div>

            {/* Install count */}
            <div className="flex items-center gap-1">
              <Download className="h-4 w-4" />
              <span>{item.install_count.toLocaleString()}</span>
            </div>

            {/* Version */}
            <span className="text-xs">v{item.version}</span>
          </div>

          {/* Action buttons */}
          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={handleViewDetails}
              className="text-xs"
            >
              Details
            </Button>

            {showInstallButton && onInstall && (
              <Button
                size="sm"
                onClick={handleInstall}
                className="text-xs"
              >
                Install
              </Button>
            )}
          </div>
        </div>
      </div>
    </Card>
  );
};
