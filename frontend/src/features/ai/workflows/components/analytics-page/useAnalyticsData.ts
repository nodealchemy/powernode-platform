import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { workflowsApi, WorkflowStatistics } from '@/shared/services/ai';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { logger } from '@/shared/utils/logger';
import { WorkflowExecutionStats } from '@/shared/types/workflow';

interface AnalyticsData {
  statistics: WorkflowStatistics;
  executionMetrics: {
    metrics: WorkflowExecutionStats;
    period: {
      startDate: string;
      endDate: string;
      totalDays: number;
    };
  };
}

export function useAnalyticsData() {
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();

  const [analyticsData, setAnalyticsData] = useState<AnalyticsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [startDate, setStartDate] = useState(new Date(Date.now() - 30 * 24 * 60 * 60 * 1000));
  const [endDate, setEndDate] = useState(new Date());
  const [selectedPeriod, setSelectedPeriod] = useState('30');

  const canViewAnalytics = currentUser?.permissions?.includes('ai.analytics.read') ||
                          currentUser?.permissions?.includes('ai.workflows.read') ||
                          currentUser?.permissions?.includes('ai.workflows.manage') || false;

  const dateStrings = useMemo(() => ({
    start: startDate.toISOString().split('T')[0],
    end: endDate.toISOString().split('T')[0]
  }), [startDate, endDate]);

  const loadAnalyticsData = useRef<(() => Promise<void>) | undefined>(undefined);

  loadAnalyticsData.current = async () => {
    try {
      setLoading(true);
      const statisticsResponse = await workflowsApi.getWorkflowStatistics();
      const metricsResponse = await workflowsApi.getExecutionMetrics(dateStrings.start, dateStrings.end);
      setAnalyticsData({
        statistics: statisticsResponse.statistics,
        executionMetrics: metricsResponse
      });
    } catch (error) {
      logger.error('Failed to load analytics data', error);
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      addNotification({
        type: 'error',
        title: 'Analytics Error',
        message: `Failed to load analytics data: ${errorMessage}`
      });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (canViewAnalytics && loadAnalyticsData.current) {
      loadAnalyticsData.current();
    }
  }, [canViewAnalytics, dateStrings.start, dateStrings.end]);

  const handlePeriodChange = useCallback((period: string) => {
    setSelectedPeriod(period);
    const days = parseInt(period);
    const newEndDate = new Date();
    const newStartDate = new Date(newEndDate.getTime() - days * 24 * 60 * 60 * 1000);
    setStartDate(newStartDate);
    setEndDate(newEndDate);
  }, []);

  const formatDuration = (ms: number) => {
    if (ms < 1000) return `${ms}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    return `${(ms / 60000).toFixed(1)}m`;
  };

  const formatPercentage = (value: number) => `${value.toFixed(1)}%`;

  const handleExportData = useCallback(() => {
    if (!analyticsData) return;
    const exportData = {
      generated_at: new Date().toISOString(),
      period: { start: dateStrings.start, end: dateStrings.end },
      statistics: analyticsData?.statistics || {},
      execution_metrics: analyticsData?.executionMetrics?.metrics || {}
    };
    const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `workflow-analytics-${dateStrings.start}-to-${dateStrings.end}.json`;
    a.click();
    URL.revokeObjectURL(url);
    addNotification({ type: 'success', title: 'Export Complete', message: 'Analytics data has been exported successfully.' });
  }, [analyticsData, dateStrings, addNotification]);

  return {
    analyticsData,
    loading,
    startDate,
    setStartDate,
    endDate,
    setEndDate,
    selectedPeriod,
    canViewAnalytics,
    handlePeriodChange,
    formatDuration,
    formatPercentage,
    handleExportData,
  };
}
