/**
 * Marketplace Page
 *
 * Feature template marketplace showing workflow, pipeline, integration, and prompt templates.
 * Users can browse, subscribe to, and create instances from templates.
 */

import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { Package } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { Button } from '@/shared/components/ui/Button';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { marketplaceApi } from '@/features/app/services/marketplaceApi';
import { ItemCard, TypeFilter, SearchInput } from '@/features/app/components';
import type { MarketplaceItem, MarketplaceItemType, MarketplaceFilters } from '@/features/app/types/marketplace';
import { ALL_MARKETPLACE_TYPES } from '@/features/app/types/marketplace';

const ALL_TYPES: MarketplaceItemType[] = ALL_MARKETPLACE_TYPES;

export const MarketplacePage: React.FC = () => {
  const navigate = useNavigate();
  const { addNotification } = useNotifications();

  const [items, setItems] = useState<MarketplaceItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedTypes, setSelectedTypes] = useState<MarketplaceItemType[]>(ALL_TYPES);

  // Load marketplace items
  useEffect(() => {
    const loadItems = async () => {
      try {
        setLoading(true);

        const filters: MarketplaceFilters = {
          types: selectedTypes.length === ALL_TYPES.length ? undefined : selectedTypes,
          search: searchQuery || undefined
        };

        const response = await marketplaceApi.getItems(filters);
        setItems(response.data || []);
      } catch (error) {
        console.error('Failed to load marketplace items:', error);
        addNotification({
          type: 'error',
          title: 'Error',
          message: 'Failed to load marketplace items. Please try again.'
        });
      } finally {
        setLoading(false);
      }
    };

    loadItems();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedTypes, searchQuery]);

  const handleViewDetails = useCallback((itemId: string) => {
    const item = items.find((i) => i.id === itemId);
    if (item) {
      navigate(`/app/marketplace/${item.type}/${itemId}`);
    }
  }, [items, navigate]);

  const handleSubscribe = useCallback(async (itemId: string) => {
    const item = items.find((i) => i.id === itemId);
    if (!item) return;

    try {
      await marketplaceApi.subscribe(item.type, itemId);

      addNotification({
        type: 'success',
        title: 'Subscription Started',
        message: `You are now subscribed to ${item.name}.`
      });

      // Refresh items by updating search (triggers useEffect)
      setSearchQuery(prev => prev); // Trigger re-fetch
    } catch (error) {
      console.error('Failed to subscribe to item:', error);
      addNotification({
        type: 'error',
        title: 'Subscription Failed',
        message: 'Failed to subscribe to item. Please try again.'
      });
    }
  }, [items, addNotification]);

  if (loading) {
    return (
      <PageContainer
        title="Marketplace"
        description="Browse and subscribe to workflow, pipeline, integration, and prompt templates"
      >
        <LoadingSpinner className="py-12" />
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Marketplace"
      description="Browse and subscribe to workflow, pipeline, integration, and prompt templates"
    >
      {/* Search and Filters */}
      <div className="mb-6 space-y-4">
        <SearchInput
          value={searchQuery}
          onChange={setSearchQuery}
          placeholder="Search by name or description..."
        />

        <TypeFilter
          selectedTypes={selectedTypes}
          onChange={setSelectedTypes}
        />
      </div>

      {/* Items Grid */}
      {items.length === 0 ? (
        <EmptyState
          icon={Package}
          title="No items found"
          description="Try adjusting your search or filters"
          action={
            <Button onClick={() => { setSearchQuery(''); setSelectedTypes(ALL_TYPES); }}>
              Clear Filters
            </Button>
          }
        />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {items.map((item) => (
            <ItemCard
              key={item.id}
              item={item}
              showInstallButton={true}
              onViewDetails={handleViewDetails}
              onInstall={handleSubscribe}
            />
          ))}
        </div>
      )}
    </PageContainer>
  );
};
