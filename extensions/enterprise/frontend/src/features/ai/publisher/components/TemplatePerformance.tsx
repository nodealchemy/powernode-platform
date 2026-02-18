import React from 'react';
import { Link } from 'react-router-dom';
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts';
import type { TemplatePerformanceData, TemplateSummary } from '../types';

interface TemplatePerformanceProps {
  templates: TemplateSummary[] | TemplatePerformanceData[];
  showChart?: boolean;
}

const formatCurrency = (value: number): string => {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: 'USD',
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(value);
};

const formatNumber = (value: number): string => {
  return new Intl.NumberFormat('en-US').format(value);
};

export const TemplatePerformance: React.FC<TemplatePerformanceProps> = ({
  templates,
  showChart = true,
}) => {
  const isPerformanceData = (item: TemplateSummary | TemplatePerformanceData): item is TemplatePerformanceData => {
    return 'revenue' in item;
  };

  const chartData = templates.slice(0, 10).map((template) => ({
    name: template.name.length > 15 ? template.name.substring(0, 15) + '...' : template.name,
    revenue: isPerformanceData(template) ? template.revenue : 0,
    installations: isPerformanceData(template) ? template.installations : template.installation_count,
  }));

  const getStatusBadge = (status: string) => {
    const styles: Record<string, string> = {
      published: 'bg-theme-success-background text-theme-success',
      draft: 'bg-theme-bg-tertiary text-theme-text-secondary',
      pending_review: 'bg-theme-warning-background text-theme-warning',
      rejected: 'bg-theme-error-background text-theme-error',
      archived: 'bg-theme-bg-tertiary text-theme-text-tertiary',
    };
    return (
      <span className={`px-2 py-1 rounded-full text-xs font-medium ${styles[status] || 'bg-theme-bg-tertiary text-theme-text-secondary'}`}>
        {status.replace('_', ' ').charAt(0).toUpperCase() + status.slice(1).replace('_', ' ')}
      </span>
    );
  };

  const getRatingStars = (rating: number | null) => {
    if (rating === null) return <span className="text-theme-text-secondary text-sm">No ratings</span>;

    const fullStars = Math.floor(rating);
    const hasHalfStar = rating % 1 >= 0.5;

    return (
      <div className="flex items-center gap-1">
        {[...Array(5)].map((_, i) => (
          <svg
            key={i}
            className={`w-4 h-4 ${
              i < fullStars
                ? 'text-theme-warning'
                : i === fullStars && hasHalfStar
                ? 'text-theme-warning'
                : 'text-theme-text-tertiary'
            }`}
            fill="currentColor"
            viewBox="0 0 20 20"
          >
            <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
          </svg>
        ))}
        <span className="text-sm text-theme-text-secondary ml-1">
          ({rating.toFixed(1)})
        </span>
      </div>
    );
  };

  return (
    <div className="space-y-6">
      {/* Chart Section */}
      {showChart && chartData.length > 0 && (
        <div className="bg-theme-bg-primary rounded-lg p-4 border border-theme-border">
          <h3 className="text-lg font-semibold text-theme-text-primary mb-4">
            Template Performance
          </h3>
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={chartData} layout="vertical">
              <CartesianGrid strokeDasharray="3 3" className="stroke-theme-border" />
              <XAxis type="number" tickFormatter={formatNumber} />
              <YAxis
                dataKey="name"
                type="category"
                width={120}
                tick={{ fontSize: 12 }}
              />
              <Tooltip
                formatter={(value, name) =>
                  name === 'revenue' ? formatCurrency(Number(value)) : formatNumber(Number(value))
                }
                contentStyle={{
                  backgroundColor: 'var(--theme-bg-secondary)',
                  border: '1px solid var(--theme-border)',
                  borderRadius: '8px',
                }}
              />
              <Bar
                dataKey="installations"
                name="Installations"
                fill="var(--theme-primary)"
                radius={[0, 4, 4, 0]}
              />
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}

      {/* Templates Table */}
      <div className="bg-theme-bg-primary rounded-lg border border-theme-border overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-theme-bg-secondary">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-text-secondary uppercase tracking-wider">
                  Template
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-text-secondary uppercase tracking-wider">
                  Status
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-text-secondary uppercase tracking-wider">
                  Price
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-text-secondary uppercase tracking-wider">
                  Installs
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-text-secondary uppercase tracking-wider">
                  Rating
                </th>
                {isPerformanceData(templates[0]) && (
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-text-secondary uppercase tracking-wider">
                    Revenue
                  </th>
                )}
              </tr>
            </thead>
            <tbody className="divide-y divide-theme-border">
              {templates.map((template) => (
                <tr key={template.id} className="hover:bg-theme-bg-secondary">
                  <td className="px-6 py-4">
                    <div className="flex items-center">
                      <div>
                        <Link
                          to={`/ai/marketplace/templates/${template.id}`}
                          className="font-medium text-theme-text-primary hover:text-theme-primary"
                        >
                          {template.name}
                        </Link>
                        {!isPerformanceData(template) && template.is_featured && (
                          <span className="ml-2 px-2 py-0.5 bg-theme-warning-background text-theme-warning text-xs rounded">
                            Featured
                          </span>
                        )}
                        {!isPerformanceData(template) && template.is_verified && (
                          <span className="ml-2 px-2 py-0.5 bg-theme-interactive-primary/10 text-theme-interactive-primary text-xs rounded">
                            Verified
                          </span>
                        )}
                      </div>
                    </div>
                  </td>
                  <td className="px-6 py-4">
                    {!isPerformanceData(template) && getStatusBadge(template.status)}
                  </td>
                  <td className="px-6 py-4 text-theme-text-primary">
                    {!isPerformanceData(template) ? (
                      template.pricing_type === 'free' ? (
                        <span className="text-theme-success font-medium">Free</span>
                      ) : (
                        formatCurrency(template.price_usd || 0)
                      )
                    ) : (
                      '-'
                    )}
                  </td>
                  <td className="px-6 py-4 text-theme-text-primary">
                    {formatNumber(
                      isPerformanceData(template)
                        ? template.installations
                        : template.installation_count
                    )}
                  </td>
                  <td className="px-6 py-4">
                    {getRatingStars(
                      isPerformanceData(template)
                        ? template.rating
                        : template.average_rating
                    )}
                  </td>
                  {isPerformanceData(template) && (
                    <td className="px-6 py-4 text-theme-text-primary font-medium">
                      {formatCurrency(template.revenue)}
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {templates.length === 0 && (
        <div className="text-center py-12 bg-theme-bg-primary rounded-lg border border-theme-border">
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
              d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"
            />
          </svg>
          <h3 className="mt-2 text-sm font-medium text-theme-text-primary">
            No templates
          </h3>
          <p className="mt-1 text-sm text-theme-text-secondary">
            Get started by publishing your first template.
          </p>
        </div>
      )}
    </div>
  );
};

export default TemplatePerformance;
