import { useState, useEffect, useCallback } from 'react';
import { marketplaceListingsApi } from '../services/marketplaceApi';
import { MarketplaceListing, MarketplaceFilters, MarketplaceCategory } from '../types';
import { useNotifications } from '@/shared/hooks/useNotifications';

export const useMarketplaceListings = (filters: MarketplaceFilters = {}) => {
  const [listings, setListings] = useState<MarketplaceListing[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [pagination, setPagination] = useState({
    current_page: 1,
    total_pages: 1,
    total_count: 0,
    per_page: 20
  });
  
  // Removed unused showNotification

  const loadListings = useCallback(async (newFilters: MarketplaceFilters = {}) => {
    setLoading(true);
    setError(null);
    
    try {
      const response = await marketplaceListingsApi.getMarketplaceListings({ ...filters, ...newFilters });
      
      if (response.success) {
        setListings(response.data);
        setPagination(response.pagination);
      } else {
        setError('Failed to load marketplace listings');
      }
    } catch (error) {
      setError('Failed to load marketplace listings');
      // Error handled by state
    } finally {
      setLoading(false);
    }
  }, [filters]);

  useEffect(() => {
    loadListings();
  }, [
    filters.status, 
    filters.featured, 
    filters.category, 
    filters.tags, 
    filters.search, 
    filters.sort, 
    filters.page,
    loadListings
  ]);

  const refresh = () => loadListings();

  return {
    listings,
    loading,
    error,
    pagination,
    refresh,
    loadListings
  };
};

export const useMarketplaceListing = (id: string) => {
  const [listing, setListing] = useState<MarketplaceListing | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  
  const { showNotification } = useNotifications();

  const loadListing = useCallback(async () => {
    setLoading(true);
    setError(null);
    
    try {
      const response = await marketplaceListingsApi.getMarketplaceListing(id);
      
      if (response.success) {
        setListing(response.data);
      } else {
        setError(response.error || 'Failed to load marketplace listing');
      }
    } catch (error) {
      setError('Failed to load marketplace listing');
      // Error handled by state
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (id) {
      loadListing();
    }
  }, [id, loadListing]);

  const submitForReview = async (appId: string) => {
    try {
      const response = await marketplaceListingsApi.submitForReview(appId);
      
      if (response.success) {
        showNotification(response.message || 'Listing submitted for review successfully', 'success');
        await loadListing();
        return response.data;
      } else {
        showNotification(response.error || 'Failed to submit listing for review', 'error');
        return null;
      }
    } catch (error) {
      showNotification('Failed to submit listing for review', 'error');
      // Error handled by notification
      return null;
    }
  };

  const approveListing = async (appId: string, notes?: string) => {
    try {
      const response = await marketplaceListingsApi.approveListing(appId, notes);
      
      if (response.success) {
        showNotification(response.message || 'Listing approved successfully', 'success');
        await loadListing();
        return response.data;
      } else {
        showNotification(response.error || 'Failed to approve listing', 'error');
        return null;
      }
    } catch (error) {
      showNotification('Failed to approve listing', 'error');
      // Error handled by notification
      return null;
    }
  };

  const rejectListing = async (appId: string, notes: string) => {
    try {
      const response = await marketplaceListingsApi.rejectListing(appId, notes);
      
      if (response.success) {
        showNotification(response.message || 'Listing rejected', 'success');
        await loadListing();
        return response.data;
      } else {
        showNotification(response.error || 'Failed to reject listing', 'error');
        return null;
      }
    } catch (error) {
      showNotification('Failed to reject listing', 'error');
      // Error handled by notification
      return null;
    }
  };

  const featureListing = async (appId: string) => {
    try {
      const response = await marketplaceListingsApi.featureListing(appId);
      
      if (response.success) {
        showNotification(response.message || 'Listing featured successfully', 'success');
        await loadListing();
        return response.data;
      } else {
        showNotification(response.error || 'Failed to feature listing', 'error');
        return null;
      }
    } catch (error) {
      showNotification('Failed to feature listing', 'error');
      // Error handled by notification
      return null;
    }
  };

  const unfeatureListing = async (appId: string) => {
    try {
      const response = await marketplaceListingsApi.unfeatureListing(appId);
      
      if (response.success) {
        showNotification(response.message || 'Listing unfeatured successfully', 'success');
        await loadListing();
        return response.data;
      } else {
        showNotification(response.error || 'Failed to unfeature listing', 'error');
        return null;
      }
    } catch (error) {
      showNotification('Failed to unfeature listing', 'error');
      // Error handled by notification
      return null;
    }
  };

  const refresh = () => loadListing();

  return {
    listing,
    loading,
    error,
    submitForReview,
    approveListing,
    rejectListing,
    featureListing,
    unfeatureListing,
    refresh
  };
};

export const useMarketplaceCategories = () => {
  const [categories, setCategories] = useState<MarketplaceCategory[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadCategories = async () => {
    setLoading(true);
    setError(null);
    
    try {
      const response = await marketplaceListingsApi.getCategories();
      
      if (response.success) {
        setCategories(response.data);
      } else {
        setError(response.error || 'Failed to load categories');
      }
    } catch (error) {
      setError('Failed to load categories');
      // Error handled by state
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadCategories();
  }, []);

  const refresh = () => loadCategories();

  return {
    categories,
    loading,
    error,
    refresh
  };
};