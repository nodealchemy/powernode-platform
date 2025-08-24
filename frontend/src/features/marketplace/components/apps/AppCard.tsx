import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Card } from '@/shared/components/ui/Card';
import { App, AppStatus } from '../../types';
import { 
  Settings, 
  Globe, 
  Users, 
  Star, 
  Plus, 
  ChevronDown, 
  ChevronUp,
  Calendar,
  Code,
  Webhook,
  Clock
} from 'lucide-react';

interface AppCardProps {
  app: App;
  isOwner?: boolean;
  showSubscription?: boolean;
  onSubscribe?: (app: App) => void;
  onManage?: (app: App) => void;
  onCardClick?: (app: App) => void;
  expanded?: boolean;
  onToggleExpansion?: (app: App) => void;
}

export const AppCard: React.FC<AppCardProps> = ({
  app,
  isOwner = false,
  showSubscription = false,
  onSubscribe,
  onManage,
  onCardClick,
  expanded = false,
  onToggleExpansion
}) => {
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState<'overview' | 'features' | 'reviews'>('overview');
  const getStatusBadgeVariant = (status: AppStatus): 'success' | 'warning' | 'danger' | 'secondary' => {
    switch (status) {
      case 'published': return 'success';
      case 'draft': return 'secondary';
      case 'under_review': return 'warning';
      case 'inactive': return 'danger';
      default: return 'secondary';
    }
  };

  const formatStatus = (status: string) => {
    return status.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase());
  };

  const handleCardClick = (e: React.MouseEvent) => {
    // Prevent expansion if clicking on buttons or links
    if (e.target instanceof HTMLElement) {
      const isClickableElement = e.target.closest('button, a, [data-clickable="false"]');
      if (isClickableElement) return;
    }

    if (onToggleExpansion) {
      onToggleExpansion(app);
    } else if (onCardClick) {
      onCardClick(app);
    } else {
      // Default behavior: navigate to app detail page
      navigate(`/app/marketplace/apps/${app.id}`);
    }
  };

  // Mock data for expanded view
  const mockFeatures = [
    { name: 'API Integration', description: 'Connect with external services', icon: '🔌' },
    { name: 'Real-time Updates', description: 'Live data synchronization', icon: '⚡' },
    { name: 'Custom Webhooks', description: 'Event-driven notifications', icon: '🔔' },
    { name: 'Analytics Dashboard', description: 'Comprehensive reporting', icon: '📊' }
  ];

  const mockReviews = [
    { id: '1', user: 'John Smith', rating: 5, comment: 'Excellent app! Easy to integrate and very reliable.', date: '2024-01-15' },
    { id: '2', user: 'Sarah Johnson', rating: 4, comment: 'Great functionality, could use better documentation.', date: '2024-01-10' }
  ];

  const averageRating = mockReviews.reduce((sum, review) => sum + review.rating, 0) / mockReviews.length;

  const renderExpandedContent = () => {
    const tabs = [
      { id: 'overview' as const, label: 'Overview', icon: '📋' },
      { id: 'features' as const, label: 'Features', icon: '⚙️' },
      { id: 'reviews' as const, label: 'Reviews', icon: '⭐' }
    ];

    const renderOverviewTab = () => (
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <Card className="p-4">
          <h5 className="text-md font-semibold text-theme-primary mb-3">App Information</h5>
          <div className="space-y-2">
            <div className="flex items-center space-x-2">
              <Globe className="w-4 h-4 text-theme-secondary" />
              <span className="text-sm text-theme-secondary">Category: {app.category}</span>
            </div>
            <div className="flex items-center space-x-2">
              <Calendar className="w-4 h-4 text-theme-secondary" />
              <span className="text-sm text-theme-secondary">
                Updated: {new Date(app.updated_at).toLocaleDateString()}
              </span>
            </div>
            <div className="flex items-center space-x-2">
              <Clock className="w-4 h-4 text-theme-secondary" />
              <span className="text-sm text-theme-secondary">
                Published: {app.published_at ? new Date(app.published_at).toLocaleDateString() : 'Not published'}
              </span>
            </div>
          </div>
        </Card>

        <Card className="p-4">
          <h5 className="text-md font-semibold text-theme-primary mb-3">Technical Details</h5>
          <div className="space-y-2">
            <div className="flex items-center space-x-2">
              <Code className="w-4 h-4 text-theme-secondary" />
              <span className="text-sm text-theme-secondary">12 API endpoints</span>
            </div>
            <div className="flex items-center space-x-2">
              <Webhook className="w-4 h-4 text-theme-secondary" />
              <span className="text-sm text-theme-secondary">5 webhook events</span>
            </div>
            <div className="flex items-center space-x-2">
              <Star className="w-4 h-4 text-yellow-400 fill-current" />
              <span className="text-sm text-theme-secondary">{averageRating.toFixed(1)} rating ({mockReviews.length} reviews)</span>
            </div>
          </div>
        </Card>
      </div>
    );

    const renderFeaturesTab = () => (
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {mockFeatures.map((feature, index) => (
          <Card key={index} className="p-4">
            <div className="flex items-start space-x-3">
              <div className="text-xl">{feature.icon}</div>
              <div>
                <h6 className="font-medium text-theme-primary mb-1">{feature.name}</h6>
                <p className="text-sm text-theme-secondary">{feature.description}</p>
              </div>
            </div>
          </Card>
        ))}
      </div>
    );

    const renderReviewsTab = () => (
      <div className="space-y-3">
        {mockReviews.map((review) => (
          <Card key={review.id} className="p-4">
            <div className="flex items-start justify-between mb-2">
              <div className="flex items-center space-x-2">
                <div className="w-8 h-8 bg-theme-interactive-primary rounded-full flex items-center justify-center text-white text-sm font-semibold">
                  {review.user.charAt(0)}
                </div>
                <div>
                  <div className="font-medium text-theme-primary text-sm">{review.user}</div>
                  <div className="flex items-center space-x-1">
                    {[1, 2, 3, 4, 5].map((star) => (
                      <Star
                        key={star}
                        className={`w-3 h-3 ${
                          star <= review.rating ? 'text-yellow-400 fill-current' : 'text-gray-300'
                        }`}
                      />
                    ))}
                  </div>
                </div>
              </div>
              <div className="text-xs text-theme-tertiary">
                {new Date(review.date).toLocaleDateString()}
              </div>
            </div>
            <p className="text-sm text-theme-secondary">{review.comment}</p>
          </Card>
        ))}
      </div>
    );

    return (
      <div className="mt-6 pt-6 border-t border-theme space-y-4">
        {/* Tabs */}
        <div className="flex space-x-6">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={(e) => {
                e.stopPropagation();
                setActiveTab(tab.id);
              }}
              className={`flex items-center space-x-2 py-1 px-2 text-sm font-medium ${
                activeTab === tab.id
                  ? 'text-theme-interactive-primary border-b-2 border-theme-interactive-primary'
                  : 'text-theme-secondary hover:text-theme-primary'
              }`}
              data-clickable="false"
            >
              <span>{tab.icon}</span>
              <span>{tab.label}</span>
            </button>
          ))}
        </div>

        {/* Tab Content */}
        <div className="min-h-[200px]">
          {activeTab === 'overview' && renderOverviewTab()}
          {activeTab === 'features' && renderFeaturesTab()}
          {activeTab === 'reviews' && renderReviewsTab()}
        </div>
      </div>
    );
  };

  return (
    <Card 
      className={`p-6 hover:shadow-lg transition-all duration-200 cursor-pointer ${
        expanded ? 'shadow-lg ring-1 ring-theme-interactive-primary/20' : ''
      }`} 
      onClick={handleCardClick}
    >
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center space-x-3">
          <div className="w-12 h-12 bg-theme-interactive-primary rounded-lg flex items-center justify-center text-white text-xl">
            {app.icon || '📱'}
          </div>
          <div>
            <h3 className="text-lg font-semibold text-theme-primary mb-1">
              {isOwner ? (
                <Link 
                  to={`/app/marketplace/apps/${app.id}`}
                  className="hover:text-theme-interactive-primary transition-colors"
                  data-clickable="false"
                >
                  {app.name}
                </Link>
              ) : (
                <span>{app.name}</span>
              )}
            </h3>
            <div className="flex items-center space-x-2">
              <Badge variant={getStatusBadgeVariant(app.status)}>
                {formatStatus(app.status)}
              </Badge>
              <span className="text-sm text-theme-tertiary">v{app.version}</span>
            </div>
          </div>
        </div>

        <div className="flex items-center space-x-2">
          {isOwner && (
            <Button
              variant="outline"
              size="sm"
              onClick={(e) => {
                e.stopPropagation();
                onManage?.(app);
              }}
              className="flex items-center space-x-1"
              data-clickable="false"
            >
              <Settings className="w-4 h-4" />
              <span>Manage</span>
            </Button>
          )}
          
          {onToggleExpansion && (
            <Button
              variant="ghost"
              size="sm"
              onClick={(e) => {
                e.stopPropagation();
                onToggleExpansion(app);
              }}
              className="flex items-center space-x-1"
              data-clickable="false"
            >
              {expanded ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
            </Button>
          )}
        </div>
      </div>

      <p className="text-theme-secondary text-sm mb-4 line-clamp-3">
        {app.short_description || app.description}
      </p>

      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center space-x-4 text-sm text-theme-tertiary">
          <div className="flex items-center space-x-1">
            <Globe className="w-4 h-4" />
            <span>{app.category}</span>
          </div>
          <div className="flex items-center space-x-1">
            <Users className="w-4 h-4" />
            <span>1.2k</span>
          </div>
          <div className="flex items-center space-x-1">
            <Star className="w-4 h-4 text-yellow-400 fill-current" />
            <span>{averageRating.toFixed(1)}</span>
          </div>
        </div>
      </div>

      {app.tags && app.tags.length > 0 && (
        <div className="flex flex-wrap gap-2 mb-4">
          {app.tags.slice(0, 3).map((tag) => (
            <Badge key={tag} variant="outline" className="text-xs">
              {tag}
            </Badge>
          ))}
          {app.tags.length > 3 && (
            <Badge variant="outline" className="text-xs">
              +{app.tags.length - 3} more
            </Badge>
          )}
        </div>
      )}

      <div className="flex items-center justify-between">
        <div className="text-sm text-theme-tertiary">
          Updated {new Date(app.updated_at).toLocaleDateString()}
        </div>

        {showSubscription && !isOwner && (
          <Button
            variant="primary"
            size="sm"
            onClick={(e) => {
              e.stopPropagation();
              onSubscribe?.(app);
            }}
            className="flex items-center space-x-2"
            data-clickable="false"
          >
            <Plus className="w-4 h-4" />
            <span>Subscribe</span>
          </Button>
        )}
      </div>

      <div className="mt-4 pt-4 border-t border-theme">
        <div className="flex items-center justify-between text-sm text-theme-secondary">
          <span>📡 12 API endpoints</span>
          <span>🔗 5 webhooks</span>
        </div>
      </div>

      {/* Expanded Content */}
      {expanded && renderExpandedContent()}
    </Card>
  );
};