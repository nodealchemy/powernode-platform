import React, { useState, useEffect } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { useNotification } from '@/shared/contexts/NotificationContext';
import predictiveAnalyticsApi from '../services/predictiveAnalyticsApi';
import { ForecastChart } from '../components/ForecastChart';
import type { RevenueForecast } from '../types/predictive';

const formatCurrency = (value: number): string => {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(value);
};

export const RevenueForecastPage: React.FC = () => {
  const { showNotification } = useNotification();
  const [forecasts, setForecasts] = useState<RevenueForecast[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isGenerating, setIsGenerating] = useState(false);
  const [period, setPeriod] = useState<'monthly' | 'quarterly'>('monthly');

  const fetchData = async () => {
    setIsLoading(true);
    try {
      const response = await predictiveAnalyticsApi.getRevenueForecasts({
        platform_wide: true,
        period: period,
        future_only: true,
      });
      setForecasts(response.data);
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : 'Failed to load forecasts';
      showNotification('error', message);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, [period]);

  const handleGenerateForecast = async () => {
    setIsGenerating(true);
    try {
      const response = await predictiveAnalyticsApi.generateForecast({
        months_ahead: 12,
        period: period,
      });
      showNotification('success', response.message);
      fetchData();
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : 'Failed to generate forecast';
      showNotification('error', message);
    } finally {
      setIsGenerating(false);
    }
  };

  const getTotals = () => {
    if (forecasts.length === 0) return null;

    const nextMonth = forecasts[0];
    const threeMonths = forecasts.slice(0, 3).reduce(
      (acc, f) => ({
        mrr: acc.mrr + f.projections.mrr,
        newRevenue: acc.newRevenue + f.projections.new_revenue,
        churned: acc.churned + f.projections.churned_revenue,
      }),
      { mrr: 0, newRevenue: 0, churned: 0 }
    );
    const twelveMonths = forecasts.slice(0, 12).reduce(
      (acc, f) => ({
        mrr: acc.mrr + f.projections.mrr,
        newRevenue: acc.newRevenue + f.projections.new_revenue,
        churned: acc.churned + f.projections.churned_revenue,
      }),
      { mrr: 0, newRevenue: 0, churned: 0 }
    );

    return { nextMonth, threeMonths, twelveMonths };
  };

  const totals = getTotals();

  if (isLoading) {
    return (
      <PageContainer title="Revenue Forecast">
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary" />
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Revenue Forecast"
      actions={
        <div className="flex gap-3">
          <select
            value={period}
            onChange={(e) => setPeriod(e.target.value as 'monthly' | 'quarterly')}
            className="bg-theme-bg-secondary border border-theme-border rounded-lg px-4 py-2 text-theme-text-primary"
          >
            <option value="monthly">Monthly</option>
            <option value="quarterly">Quarterly</option>
          </select>
          <Button variant="primary" onClick={handleGenerateForecast} isLoading={isGenerating}>
            Generate Forecast
          </Button>
        </div>
      }
    >
      {/* Summary Cards */}
      {totals && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
            <p className="text-sm font-medium text-theme-text-secondary">Next Month MRR</p>
            <p className="mt-2 text-3xl font-bold text-theme-text-primary">
              {formatCurrency(totals.nextMonth.projections.mrr)}
            </p>
            <p className="mt-1 text-sm text-theme-text-secondary">
              {formatCurrency(totals.nextMonth.projections.mrr * 12)} ARR
            </p>
          </div>
          <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
            <p className="text-sm font-medium text-theme-text-secondary">3-Month Projection</p>
            <p className="mt-2 text-3xl font-bold text-theme-text-primary">
              {formatCurrency(totals.threeMonths.mrr / 3)}
            </p>
            <p className="mt-1 text-sm text-green-600">
              +{formatCurrency(totals.threeMonths.newRevenue)} new
            </p>
          </div>
          <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
            <p className="text-sm font-medium text-theme-text-secondary">12-Month Projection</p>
            <p className="mt-2 text-3xl font-bold text-theme-text-primary">
              {formatCurrency(totals.twelveMonths.mrr / 12)}
            </p>
            <p className="mt-1 text-sm text-theme-text-secondary">
              avg monthly
            </p>
          </div>
          <div className="bg-theme-bg-primary rounded-lg p-6 border border-theme-border">
            <p className="text-sm font-medium text-theme-text-secondary">Projected Churn</p>
            <p className="mt-2 text-3xl font-bold text-red-600">
              {formatCurrency(totals.twelveMonths.churned)}
            </p>
            <p className="mt-1 text-sm text-theme-text-secondary">
              12-month total
            </p>
          </div>
        </div>
      )}

      {/* Forecast Chart */}
      {forecasts.length > 0 ? (
        <ForecastChart forecasts={forecasts} height={400} showConfidenceInterval />
      ) : (
        <div className="bg-theme-bg-primary rounded-lg p-12 border border-theme-border text-center">
          <svg
            className="mx-auto h-12 w-12 text-theme-text-secondary"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
            />
          </svg>
          <h3 className="mt-2 text-sm font-medium text-theme-text-primary">
            No forecasts available
          </h3>
          <p className="mt-1 text-sm text-theme-text-secondary">
            Generate a forecast to see revenue projections.
          </p>
          <Button
            variant="primary"
            className="mt-4"
            onClick={handleGenerateForecast}
            isLoading={isGenerating}
          >
            Generate Forecast
          </Button>
        </div>
      )}

      {/* Forecast Details Table */}
      {forecasts.length > 0 && (
        <div className="mt-6 bg-theme-bg-primary rounded-lg border border-theme-border overflow-hidden">
          <div className="px-6 py-4 border-b border-theme-border">
            <h3 className="text-lg font-semibold text-theme-text-primary">Forecast Details</h3>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-theme-bg-secondary">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-text-secondary uppercase">
                    Period
                  </th>
                  <th className="px-6 py-3 text-right text-xs font-medium text-theme-text-secondary uppercase">
                    Projected MRR
                  </th>
                  <th className="px-6 py-3 text-right text-xs font-medium text-theme-text-secondary uppercase">
                    New Revenue
                  </th>
                  <th className="px-6 py-3 text-right text-xs font-medium text-theme-text-secondary uppercase">
                    Expansion
                  </th>
                  <th className="px-6 py-3 text-right text-xs font-medium text-theme-text-secondary uppercase">
                    Churned
                  </th>
                  <th className="px-6 py-3 text-right text-xs font-medium text-theme-text-secondary uppercase">
                    Confidence
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-theme-border">
                {forecasts.slice(0, 12).map((forecast) => (
                  <tr key={forecast.id}>
                    <td className="px-6 py-4 text-theme-text-primary">
                      {new Date(forecast.forecast_date).toLocaleDateString('en-US', {
                        month: 'short',
                        year: 'numeric',
                      })}
                    </td>
                    <td className="px-6 py-4 text-right font-medium text-theme-text-primary">
                      {formatCurrency(forecast.projections.mrr)}
                    </td>
                    <td className="px-6 py-4 text-right text-green-600">
                      +{formatCurrency(forecast.projections.new_revenue)}
                    </td>
                    <td className="px-6 py-4 text-right text-blue-600">
                      +{formatCurrency(forecast.projections.expansion_revenue)}
                    </td>
                    <td className="px-6 py-4 text-right text-red-600">
                      -{formatCurrency(forecast.projections.churned_revenue)}
                    </td>
                    <td className="px-6 py-4 text-right text-theme-text-secondary">
                      {forecast.confidence.level.toFixed(0)}%
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </PageContainer>
  );
};

export default RevenueForecastPage;
