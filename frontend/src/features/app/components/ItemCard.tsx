/**
 * Marketplace Item Card
 *
 * Polymorphic card component that displays apps, plugins, templates, or integrations
 * with a consistent interface across all marketplace item types.
 */


import { Link } from 'react-router-dom';
import { Package, Star, CheckCircle, Users, Workflow, GitBranch, Puzzle, MessageSquare } from 'lucide-react';
import type { MarketplaceItem, MarketplaceItemType } from '../types/marketplace';
import { getTypeBadgeColor, getTypeDisplayName } from '../types/marketplace';
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
  // Get icon component for template type
  const getTypeIconComponent = (type: MarketplaceItemType) => {
    switch (type) {
      case 'workflow_template':
        return <Workflow className="h-6 w-6 text-theme-info" />;
      case 'pipeline_template':
        return <GitBranch className="h-6 w-6 text-theme-success" />;
      case 'integration_template':
        return <Puzzle className="h-6 w-6 text-theme-primary" />;
      case 'prompt_template':
        return <MessageSquare className="h-6 w-6 text-theme-warning" />;
      default:
        return <Package className="h-6 w-6 text-theme-tertiary" />;
    }
  };

  const handleSubscribe = (e: React.MouseEvent) => {
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
              getTypeIconComponent(item.type)
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
              {getTypeDisplayName(item.type)}
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

            {/* Subscriber count */}
            <div className="flex items-center gap-1">
              <Users className="h-4 w-4" />
              <span>{item.install_count.toLocaleString()}</span>
            </div>

            {/* Version */}
            <span className="text-xs">v{item.version}</span>
          </div>

          {/* Action buttons */}
          <div className="flex items-center gap-2">
            <Link
              to={`/app/marketplace/${item.type}/${item.id}`}
              onClick={(e) => e.stopPropagation()}
              className="px-3 py-1.5 text-xs font-medium rounded-lg border border-theme bg-theme-surface text-theme-primary hover:bg-theme-surface-hover transition-colors"
            >
              View
            </Link>

            {showInstallButton && onInstall && (
              <Button
                size="sm"
                onClick={handleSubscribe}
                className="text-xs"
              >
                Subscribe
              </Button>
            )}
          </div>
        </div>
      </div>
    </Card>
  );
};
