/**
 * Marketplace Item Detail Page
 *
 * Single detail page for all marketplace item types (apps, plugins, templates).
 * Adapts content based on item type.
 */

import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, Star, Download, CheckCircle } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Card } from '@/shared/components/ui/Card';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { unifiedMarketplaceApi } from '@/features/marketplace/services/unifiedMarketplaceApi';
import type { MarketplaceItem, MarketplaceItemType } from '@/features/marketplace/types/unified';

export const ItemDetailPage: React.FC = () => {
  const { type, id } = useParams<{ type: MarketplaceItemType; id: string }>();
  const navigate = useNavigate();
  const { addNotification } = useNotifications();

  const [item, setItem] = useState<MarketplaceItem | null>(null);
  const [loading, setLoading] = useState(true);
  const [installing, setInstalling] = useState(false);

  useEffect(() => {
    const loadItem = async () => {
      if (!type || !id) return;

      try {
        setLoading(true);
        const response = await unifiedMarketplaceApi.getItem(type, id);
        setItem(response.data);
      } catch (error) {
        console.error('Failed to load item:', error);
        addNotification({
          type: 'error',
          title: 'Error',
          message: 'Failed to load item details. Please try again.'
        });
        navigate('/app/marketplace');
      } finally {
        setLoading(false);
      }
    };

    loadItem();
  }, [type, id, addNotification, navigate]);

  const handleInstall = async () => {
    if (!item || !type || !id) return;

    try {
      setInstalling(true);
      await unifiedMarketplaceApi.install(type, id);

      addNotification({
        type: 'success',
        title: 'Installation Started',
        message: `${item.name} is being installed.`
      });

      // Navigate back to marketplace
      navigate('/app/marketplace');
    } catch (error) {
      console.error('Failed to install item:', error);
      addNotification({
        type: 'error',
        title: 'Installation Failed',
        message: 'Failed to install item. Please try again.'
      });
    } finally {
      setInstalling(false);
    }
  };

  const handleBack = () => {
    navigate('/app/marketplace');
  };

  if (loading) {
    return (
      <PageContainer title="Loading...">
        <LoadingSpinner className="py-12" />
      </PageContainer>
    );
  }

  if (!item) {
    return null;
  }

  const getTypeLabel = (type: string) => {
    return type.charAt(0).toUpperCase() + type.slice(1);
  };

  return (
    <PageContainer
      title={item.name}
      description={item.description}
      actions={[
        {
          label: 'Back to Marketplace',
          onClick: handleBack,
          variant: 'outline' as const,
          icon: ArrowLeft
        },
        {
          label: installing ? 'Installing...' : 'Install',
          onClick: handleInstall,
          variant: 'primary' as const,
          disabled: installing
        }
      ]}
    >
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Main content */}
        <div className="lg:col-span-2 space-y-6">
          {/* Header card */}
          <Card className="p-6">
            <div className="flex items-start gap-4">
              {/* Icon */}
              <div className="h-16 w-16 bg-theme-surface rounded-lg flex items-center justify-center border border-theme flex-shrink-0">
                {item.icon ? (
                  <img src={item.icon} alt={item.name} className="h-12 w-12 object-contain" />
                ) : (
                  <CheckCircle className="h-8 w-8 text-theme-tertiary" />
                )}
              </div>

              {/* Title and stats */}
              <div className="flex-1">
                <div className="flex items-start justify-between mb-2">
                  <h2 className="text-2xl font-bold text-theme-primary">{item.name}</h2>
                  {item.is_verified && (
                    <div className="flex items-center gap-1 text-theme-info" title="Verified">
                      <CheckCircle className="h-5 w-5" />
                      <span className="text-sm font-medium">Verified</span>
                    </div>
                  )}
                </div>

                <p className="text-theme-tertiary mb-4">{item.description}</p>

                <div className="flex items-center gap-6">
                  <div className="flex items-center gap-2">
                    <Star className="h-5 w-5 text-theme-warning fill-current" />
                    <span className="font-medium">{item.rating.toFixed(1)}</span>
                  </div>

                  <div className="flex items-center gap-2">
                    <Download className="h-5 w-5 text-theme-tertiary" />
                    <span>{item.install_count.toLocaleString()} installs</span>
                  </div>

                  <span className="px-3 py-1 bg-theme-surface text-theme-primary text-sm rounded border border-theme">
                    v{item.version}
                  </span>
                </div>
              </div>
            </div>
          </Card>

          {/* Description card */}
          <Card className="p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">
              About this {getTypeLabel(item.type)}
            </h3>
            <div className="prose prose-sm max-w-none text-theme-secondary">
              <p>{item.description}</p>
            </div>
          </Card>
        </div>

        {/* Sidebar */}
        <div className="space-y-6">
          {/* Details card */}
          <Card className="p-6">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">Details</h3>
            <dl className="space-y-3">
              <div>
                <dt className="text-sm text-theme-tertiary">Type</dt>
                <dd className="text-sm font-medium text-theme-primary">{getTypeLabel(item.type)}</dd>
              </div>

              <div>
                <dt className="text-sm text-theme-tertiary">Category</dt>
                <dd className="text-sm font-medium text-theme-primary">{item.category}</dd>
              </div>

              <div>
                <dt className="text-sm text-theme-tertiary">Version</dt>
                <dd className="text-sm font-medium text-theme-primary">{item.version}</dd>
              </div>

              <div>
                <dt className="text-sm text-theme-tertiary">Status</dt>
                <dd className="text-sm font-medium text-theme-primary capitalize">{item.status}</dd>
              </div>
            </dl>
          </Card>

          {/* Tags card */}
          {item.tags && item.tags.length > 0 && (
            <Card className="p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">Tags</h3>
              <div className="flex flex-wrap gap-2">
                {item.tags.map((tag, index) => (
                  <span
                    key={index}
                    className="px-3 py-1 bg-theme-surface text-theme-tertiary text-sm rounded border border-theme"
                  >
                    {tag}
                  </span>
                ))}
              </div>
            </Card>
          )}
        </div>
      </div>
    </PageContainer>
  );
};
