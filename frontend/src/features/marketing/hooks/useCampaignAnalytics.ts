import { useState, useEffect, useCallback } from 'react';
import { analyticsApi } from '../services/analyticsApi';
import type {
  AnalyticsOverview,
  CampaignStatistics,
  ChannelAnalytics,
  TopPerformer,
  CampaignMetric,
  Pagination,
} from '../types';

interface UseAnalyticsOptions {
  periodStart?: string;
  periodEnd?: string;
}

export function useAnalyticsOverview(options: UseAnalyticsOptions = {}) {
  const [overview, setOverview] = useState<AnalyticsOverview | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchOverview = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await analyticsApi.overview({
        period_start: options.periodStart,
        period_end: options.periodEnd,
      });
      setOverview(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch analytics overview');
    } finally {
      setLoading(false);
    }
  }, [options.periodStart, options.periodEnd]);

  useEffect(() => {
    fetchOverview();
  }, [fetchOverview]);

  return { overview, loading, error, refresh: fetchOverview };
}

export function useChannelAnalytics(options: UseAnalyticsOptions = {}) {
  const [channels, setChannels] = useState<ChannelAnalytics[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchChannels = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await analyticsApi.channels({
        period_start: options.periodStart,
        period_end: options.periodEnd,
      });
      setChannels(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch channel analytics');
    } finally {
      setLoading(false);
    }
  }, [options.periodStart, options.periodEnd]);

  useEffect(() => {
    fetchChannels();
  }, [fetchChannels]);

  return { channels, loading, error, refresh: fetchChannels };
}

export function useRoiAnalytics(options: UseAnalyticsOptions = {}) {
  const [statistics, setStatistics] = useState<CampaignStatistics | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchRoi = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await analyticsApi.roi({
        period_start: options.periodStart,
        period_end: options.periodEnd,
      });
      setStatistics(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch ROI analytics');
    } finally {
      setLoading(false);
    }
  }, [options.periodStart, options.periodEnd]);

  useEffect(() => {
    fetchRoi();
  }, [fetchRoi]);

  return { statistics, loading, error, refresh: fetchRoi };
}

export function useTopPerformers(options: UseAnalyticsOptions & { limit?: number } = {}) {
  const [performers, setPerformers] = useState<TopPerformer[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchPerformers = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const result = await analyticsApi.topPerformers({
        period_start: options.periodStart,
        period_end: options.periodEnd,
        limit: options.limit,
      });
      setPerformers(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch top performers');
    } finally {
      setLoading(false);
    }
  }, [options.periodStart, options.periodEnd, options.limit]);

  useEffect(() => {
    fetchPerformers();
  }, [fetchPerformers]);

  return { performers, loading, error, refresh: fetchPerformers };
}

export function useCampaignMetrics(campaignId: string | null, options: UseAnalyticsOptions = {}) {
  const [metrics, setMetrics] = useState<CampaignMetric[]>([]);
  const [pagination, setPagination] = useState<Pagination | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchMetrics = useCallback(async () => {
    if (!campaignId) return;
    try {
      setLoading(true);
      setError(null);
      const result = await analyticsApi.campaignDetail(campaignId, {
        period_start: options.periodStart,
        period_end: options.periodEnd,
      });
      setMetrics(result.metrics);
      setPagination(result.pagination);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch campaign metrics');
    } finally {
      setLoading(false);
    }
  }, [campaignId, options.periodStart, options.periodEnd]);

  useEffect(() => {
    fetchMetrics();
  }, [fetchMetrics]);

  return { metrics, pagination, loading, error, refresh: fetchMetrics };
}
