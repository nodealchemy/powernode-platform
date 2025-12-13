
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { App } from '../../types';
import { ViewMode } from '../../types/search';
import { getAppStatusBadgeVariant, formatPriceCents, formatBillingInterval } from '../../utils/themeHelpers';
import { Star, Download, Eye, ShoppingCart, ExternalLink, Clock, Users, Tag } from 'lucide-react';

export interface AppMetrics {
  rating?: number;
  totalRatings?: number;
  installations?: number;
}

interface AppCardEnhancedProps {
  app: App;
  viewMode?: ViewMode;
  showSubscription?: boolean;
  showManagement?: boolean;
  isOwner?: boolean;
  onSubscribe?: (app: App) => void;
  onViewDetails?: (app: App) => void;
  onManage?: (app: App) => void;
  onComparePlans?: (app: App) => void;
  className?: string;
  metrics?: AppMetrics;
}

export const AppCardEnhanced: React.FC<AppCardEnhancedProps> = ({
  app,
  viewMode = 'grid',
  showSubscription = false,
  showManagement = false,
  isOwner: _isOwner = false,
  onSubscribe,
  onViewDetails,
  onManage,
  onComparePlans,
  className = '',
  metrics
}) => {

  // Get the cheapest plan for pricing display
  const plans = app.plans || [];
  const cheapestPlan = plans
    .filter(plan => plan.is_active)
    .sort((a, b) => a.price_cents - b.price_cents)[0];

  const freePlan = plans.find(plan => plan.price_cents === 0 && plan.is_active);
  const hasFreePlan = !!freePlan;

  // Use metrics from props with defaults
  const rating = metrics?.rating ?? 0;
  const totalRatings = metrics?.totalRatings ?? 0;
  const installations = metrics?.installations ?? 0;
  const lastUpdated = app.updated_at || app.created_at;

  const renderPricing = () => {
    if (!plans.length) return null;

    if (hasFreePlan && plans.length === 1) {
      return (
        <div className="flex items-center space-x-2">
          <Badge variant="success" className="text-xs">Free</Badge>
        </div>
      );
    }

    if (hasFreePlan) {
      return (
        <div className="flex items-center space-x-2">
          <span className="text-sm font-medium text-theme-primary">Free</span>
          <span className="text-xs text-theme-tertiary">•</span>
          <span className="text-xs text-theme-secondary">Paid plans available</span>
        </div>
      );
    }

    if (cheapestPlan) {
      return (
        <div className="flex items-center space-x-1">
          <span className="text-sm font-medium text-theme-primary">
            From {formatPriceCents(cheapestPlan.price_cents)}
          </span>
          <span className="text-xs text-theme-secondary">
            {formatBillingInterval(cheapestPlan.billing_interval)}
          </span>
        </div>
      );
    }

    return (
      <Badge variant="secondary" className="text-xs">
        Contact for pricing
      </Badge>
    );
  };

  const renderActions = () => {
    const actions = [];

    if (onViewDetails) {
      actions.push(
        <Button
          key="details"
          variant="outline"
          size="sm"
          onClick={() => onViewDetails(app)}
          className="flex items-center space-x-1"
        >
          <Eye className="w-4 h-4" />
          <span>Details</span>
        </Button>
      );
    }

    if (showManagement && onManage) {
      actions.push(
        <Button
          key="manage"
          variant="outline" 
          size="sm"
          onClick={() => onManage(app)}
          className="flex items-center space-x-1"
        >
          <ExternalLink className="w-4 h-4" />
          <span>Manage</span>
        </Button>
      );
    }

    if (showSubscription && onSubscribe) {
      actions.push(
        <Button
          key="subscribe"
          variant="primary"
          size="sm"
          onClick={() => onSubscribe(app)}
          className="flex items-center space-x-1"
        >
          <ShoppingCart className="w-4 h-4" />
          <span>{hasFreePlan ? 'Install' : 'Subscribe'}</span>
        </Button>
      );
    }

    if (onComparePlans && plans.length > 1) {
      actions.push(
        <Button
          key="compare"
          variant="outline"
          size="sm"
          onClick={() => onComparePlans(app)}
          className="flex items-center space-x-1"
        >
          <Tag className="w-4 h-4" />
          <span>Compare</span>
        </Button>
      );
    }

    return actions;
  };

  // Grid view (default)
  if (viewMode === 'grid') {
    return (
      <Card className={`p-6 hover:shadow-lg transition-all duration-200 ${className}`}>
        <div className="space-y-4">
          {/* App Icon and Basic Info */}
          <div className="flex items-start space-x-4">
            <div className="w-16 h-16 bg-theme-interactive-primary rounded-lg flex items-center justify-center text-white text-2xl flex-shrink-0">
              {app.icon || '📱'}
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-start justify-between">
                <div>
                  <h3 className="font-semibold text-lg text-theme-primary truncate">{app.name}</h3>
                  <p className="text-sm text-theme-secondary">{app.category}</p>
                </div>
                <Badge variant={getAppStatusBadgeVariant(app.status)}>
                  {app.status}
                </Badge>
              </div>
            </div>
          </div>

          {/* Description */}
          <p className="text-sm text-theme-secondary line-clamp-3">
            {app.short_description || app.description}
          </p>

          {/* Tags */}
          {app.tags && app.tags.length > 0 && (
            <div className="flex flex-wrap gap-1">
              {app.tags.slice(0, 3).map((tag, index) => (
                <Badge key={index} variant="secondary" className="text-xs">
                  {tag}
                </Badge>
              ))}
              {app.tags.length > 3 && (
                <Badge variant="secondary" className="text-xs">
                  +{app.tags.length - 3}
                </Badge>
              )}
            </div>
          )}

          {/* Metrics */}
          <div className="flex items-center space-x-4 text-sm text-theme-tertiary">
            <div className="flex items-center space-x-1">
              <Star className="w-4 h-4 text-theme-warning fill-current" />
              <span>{rating.toFixed(1)}</span>
              <span>({totalRatings})</span>
            </div>
            <div className="flex items-center space-x-1">
              <Download className="w-4 h-4" />
              <span>{installations.toLocaleString()}</span>
            </div>
            <div className="flex items-center space-x-1">
              <Clock className="w-4 h-4" />
              <span>{new Date(lastUpdated).toLocaleDateString()}</span>
            </div>
          </div>

          {/* Pricing */}
          <div className="flex items-center justify-between">
            {renderPricing()}
          </div>

          {/* Actions */}
          <div className="flex items-center justify-between space-x-2">
            <div className="flex flex-wrap gap-2">
              {renderActions()}
            </div>
          </div>
        </div>
      </Card>
    );
  }

  // List view
  if (viewMode === 'list') {
    return (
      <Card className={`p-4 hover:shadow-md transition-all duration-200 ${className}`}>
        <div className="flex items-center space-x-4">
          {/* App Icon */}
          <div className="w-12 h-12 bg-theme-interactive-primary rounded-lg flex items-center justify-center text-white text-lg flex-shrink-0">
            {app.icon || '📱'}
          </div>

          {/* App Info */}
          <div className="flex-1 min-w-0">
            <div className="flex items-start justify-between mb-2">
              <div className="flex-1">
                <div className="flex items-center space-x-3 mb-1">
                  <h3 className="font-semibold text-theme-primary">{app.name}</h3>
                  <Badge variant={getAppStatusBadgeVariant(app.status)} className="text-xs">
                    {app.status}
                  </Badge>
                </div>
                <p className="text-sm text-theme-secondary line-clamp-2">
                  {app.short_description || app.description}
                </p>
              </div>
            </div>

            <div className="flex items-center justify-between">
              {/* Metrics and Pricing */}
              <div className="flex items-center space-x-4 text-sm text-theme-tertiary">
                <div className="flex items-center space-x-1">
                  <Star className="w-3 h-3 text-theme-warning fill-current" />
                  <span>{rating.toFixed(1)}</span>
                </div>
                <div className="flex items-center space-x-1">
                  <Users className="w-3 h-3" />
                  <span>{installations.toLocaleString()}</span>
                </div>
                <div>
                  {renderPricing()}
                </div>
              </div>

              {/* Actions */}
              <div className="flex items-center space-x-2">
                {renderActions()}
              </div>
            </div>
          </div>
        </div>
      </Card>
    );
  }

  // Compact view
  if (viewMode === 'compact') {
    return (
      <Card className={`p-3 hover:shadow-sm transition-all duration-200 ${className}`}>
        <div className="flex items-center space-x-3">
          {/* Minimal Icon */}
          <div className="w-8 h-8 bg-theme-interactive-primary rounded flex items-center justify-center text-white text-sm flex-shrink-0">
            {app.icon || '📱'}
          </div>

          {/* Compact Info */}
          <div className="flex-1 min-w-0">
            <div className="flex items-center space-x-2 mb-1">
              <h4 className="font-medium text-theme-primary truncate">{app.name}</h4>
              <Badge variant={getAppStatusBadgeVariant(app.status)} className="text-xs">
                {app.status}
              </Badge>
            </div>
            <div className="flex items-center space-x-3 text-xs text-theme-tertiary">
              <div className="flex items-center space-x-1">
                <Star className="w-3 h-3 text-theme-warning fill-current" />
                <span>{rating.toFixed(1)}</span>
              </div>
              <span>{app.category}</span>
              <div>
                {renderPricing()}
              </div>
            </div>
          </div>

          {/* Quick Actions */}
          <div className="flex items-center space-x-1 flex-shrink-0">
            {showSubscription && onSubscribe && (
              <Button
                variant="primary"
                size="sm"
                onClick={() => onSubscribe(app)}
                className="px-3"
              >
                {hasFreePlan ? 'Install' : 'Subscribe'}
              </Button>
            )}
            {onViewDetails && (
              <Button
                variant="outline"
                size="sm"
                onClick={() => onViewDetails(app)}
                className="px-2"
              >
                <Eye className="w-4 h-4" />
              </Button>
            )}
          </div>
        </div>
      </Card>
    );
  }

  return null;
};