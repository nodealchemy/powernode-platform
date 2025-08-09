import React from 'react';
import { format, parseISO } from 'date-fns';

interface CohortChartProps {
  data: Array<{
    cohort_date: string;
    cohort_size: number;
    retention_rates: Array<{
      month: number;
      retention_rate: number;
      retained_customers: number;
    }>;
  }>;
  summary?: {
    total_cohorts: number;
    average_first_month_retention: number;
    average_six_month_retention: number;
  };
  title: string;
}

export const CohortChart: React.FC<CohortChartProps> = ({ 
  data, 
  summary,
  title
}) => {
  const formatDate = (dateString: string) => {
    try {
      return format(parseISO(dateString + '-01'), 'MMM yyyy');
    } catch {
      return dateString;
    }
  };

  const formatPercentage = (value: number) => {
    return `${Math.round(value)}%`;
  };

  const getRetentionColor = (rate: number) => {
    if (rate >= 80) return 'bg-green-600 text-white';
    if (rate >= 60) return 'bg-green-500 text-white';
    if (rate >= 40) return 'bg-yellow-500 text-white';
    if (rate >= 20) return 'bg-orange-500 text-white';
    if (rate > 0) return 'bg-red-500 text-white';
    return 'bg-gray-200 text-gray-500';
  };

  const getIntensity = (rate: number) => {
    return Math.min(rate / 100, 1);
  };

  // Prepare data for the cohort table
  const maxMonths = Math.max(...data.map(cohort => cohort.retention_rates.length));
  const months = Array.from({ length: maxMonths }, (_, i) => i);

  return (
    <div className="space-y-6">
      {/* Summary Metrics */}
      {summary && (
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Cohort Summary</h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div>
              <p className="text-sm text-gray-500">Total Cohorts</p>
              <p className="text-2xl font-bold text-blue-600">{summary.total_cohorts}</p>
            </div>
            <div>
              <p className="text-sm text-gray-500">Avg 1st Month Retention</p>
              <p className="text-2xl font-bold text-green-600">
                {formatPercentage(summary.average_first_month_retention)}
              </p>
            </div>
            <div>
              <p className="text-sm text-gray-500">Avg 6th Month Retention</p>
              <p className="text-2xl font-bold text-purple-600">
                {formatPercentage(summary.average_six_month_retention)}
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Cohort Retention Heatmap */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Cohort Retention Analysis</h3>
        
        {/* Legend */}
        <div className="flex items-center justify-center space-x-4 mb-6 text-sm">
          <span className="text-gray-600">Retention Rate:</span>
          <div className="flex items-center space-x-2">
            <div className="w-4 h-4 bg-red-500 rounded"></div>
            <span>0-20%</span>
          </div>
          <div className="flex items-center space-x-2">
            <div className="w-4 h-4 bg-orange-500 rounded"></div>
            <span>20-40%</span>
          </div>
          <div className="flex items-center space-x-2">
            <div className="w-4 h-4 bg-yellow-500 rounded"></div>
            <span>40-60%</span>
          </div>
          <div className="flex items-center space-x-2">
            <div className="w-4 h-4 bg-green-500 rounded"></div>
            <span>60-80%</span>
          </div>
          <div className="flex items-center space-x-2">
            <div className="w-4 h-4 bg-green-600 rounded"></div>
            <span>80%+</span>
          </div>
        </div>

        {/* Cohort Table */}
        <div className="overflow-x-auto">
          <table className="min-w-full">
            <thead>
              <tr className="border-b border-gray-200">
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Cohort
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Size
                </th>
                {months.map(month => (
                  <th key={month} className="px-3 py-3 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
                    M{month}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {data.map((cohort, cohortIndex) => (
                <tr key={cohortIndex} className={cohortIndex % 2 === 0 ? 'bg-gray-50' : 'bg-white'}>
                  <td className="px-4 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    {formatDate(cohort.cohort_date)}
                  </td>
                  <td className="px-4 py-4 whitespace-nowrap text-sm text-gray-600">
                    {cohort.cohort_size.toLocaleString()}
                  </td>
                  {months.map(monthIndex => {
                    const retentionData = cohort.retention_rates.find(r => r.month === monthIndex);
                    if (!retentionData) {
                      return (
                        <td key={monthIndex} className="px-3 py-4 text-center">
                          <div className="w-full h-8 bg-gray-100 rounded flex items-center justify-center">
                            <span className="text-xs text-gray-400">-</span>
                          </div>
                        </td>
                      );
                    }

                    const rate = retentionData.retention_rate * 100;
                    return (
                      <td key={monthIndex} className="px-3 py-4 text-center">
                        <div 
                          className={`w-full h-8 rounded flex items-center justify-center cursor-pointer ${getRetentionColor(rate)}`}
                          title={`${formatPercentage(rate)} (${retentionData.retained_customers} customers)`}
                        >
                          <span className="text-xs font-medium">
                            {formatPercentage(rate)}
                          </span>
                        </div>
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Retention Curves */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Retention Curves</h3>
        <div className="h-96">
          <svg viewBox="0 0 800 400" className="w-full h-full">
            <defs>
              {data.map((_, index) => (
                <linearGradient key={index} id={`gradient-${index}`} x1="0%" y1="0%" x2="100%" y2="0%">
                  <stop offset="0%" style={{ stopColor: `hsl(${index * 360 / data.length}, 70%, 50%)`, stopOpacity: 0.8 }} />
                  <stop offset="100%" style={{ stopColor: `hsl(${index * 360 / data.length}, 70%, 50%)`, stopOpacity: 0.3 }} />
                </linearGradient>
              ))}
            </defs>
            
            {/* Grid lines */}
            {[0, 20, 40, 60, 80, 100].map(y => (
              <line
                key={y}
                x1="50"
                y1={350 - (y * 3)}
                x2="750"
                y2={350 - (y * 3)}
                stroke="#e5e7eb"
                strokeWidth="1"
              />
            ))}
            
            {/* Y-axis labels */}
            {[0, 20, 40, 60, 80, 100].map(y => (
              <text
                key={y}
                x="35"
                y={355 - (y * 3)}
                textAnchor="end"
                fontSize="12"
                fill="#6b7280"
              >
                {y}%
              </text>
            ))}
            
            {/* X-axis labels */}
            {months.slice(0, 13).map(month => (
              <text
                key={month}
                x={50 + (month * 50)}
                y="375"
                textAnchor="middle"
                fontSize="12"
                fill="#6b7280"
              >
                M{month}
              </text>
            ))}
            
            {/* Retention curves */}
            {data.map((cohort, cohortIndex) => {
              const points = cohort.retention_rates
                .slice(0, 13)
                .map(r => ({
                  x: 50 + (r.month * 50),
                  y: 350 - (r.retention_rate * 100 * 3)
                }));
              
              const pathData = points.reduce((path, point, index) => {
                return path + (index === 0 ? `M ${point.x} ${point.y}` : ` L ${point.x} ${point.y}`);
              }, '');
              
              return (
                <g key={cohortIndex}>
                  <path
                    d={pathData}
                    fill="none"
                    stroke={`hsl(${cohortIndex * 360 / data.length}, 70%, 50%)`}
                    strokeWidth="2"
                    opacity="0.8"
                  />
                  {points.map((point, pointIndex) => (
                    <circle
                      key={pointIndex}
                      cx={point.x}
                      cy={point.y}
                      r="3"
                      fill={`hsl(${cohortIndex * 360 / data.length}, 70%, 50%)`}
                    >
                      <title>
                        {(() => {
                          const retentionData = cohort.retention_rates.find((r, idx) => idx === pointIndex);
                          return retentionData ? 
                            `${formatDate(cohort.cohort_date)} - Month ${retentionData.month}: ${formatPercentage(retentionData.retention_rate * 100)}` :
                            formatDate(cohort.cohort_date);
                        })()}
                      </title>
                    </circle>
                  ))}
                </g>
              );
            })}
          </svg>
        </div>
        
        {/* Legend */}
        <div className="mt-4 grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3">
          {data.slice(0, 12).map((cohort, index) => (
            <div key={index} className="flex items-center space-x-2 text-sm">
              <div
                className="w-3 h-3 rounded-full"
                style={{ backgroundColor: `hsl(${index * 360 / data.length}, 70%, 50%)` }}
              ></div>
              <span className="text-gray-600 truncate">
                {formatDate(cohort.cohort_date)}
              </span>
            </div>
          ))}
        </div>
      </div>

      {/* Cohort Performance Insights */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">Cohort Performance Insights</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {/* Best Performing Cohort */}
          {(() => {
            const bestCohort = data.reduce((best, cohort) => {
              const sixMonthRetention = cohort.retention_rates.find(r => r.month === 6);
              const bestSixMonth = best.retention_rates.find(r => r.month === 6);
              
              if (!sixMonthRetention) return best;
              if (!bestSixMonth) return cohort;
              
              return sixMonthRetention.retention_rate > bestSixMonth.retention_rate ? cohort : best;
            });
            
            const sixMonthRetention = bestCohort.retention_rates.find(r => r.month === 6);
            
            return (
              <div className="p-4 bg-green-50 border border-green-200 rounded-lg">
                <h4 className="font-medium text-green-800 mb-2">🏆 Best Performing Cohort</h4>
                <p className="text-sm text-green-700">
                  {formatDate(bestCohort.cohort_date)} with{' '}
                  {sixMonthRetention ? formatPercentage(sixMonthRetention.retention_rate * 100) : 'N/A'} 
                  {' '}6-month retention
                </p>
                <p className="text-xs text-green-600 mt-1">
                  Cohort size: {bestCohort.cohort_size.toLocaleString()}
                </p>
              </div>
            );
          })()}

          {/* Largest Cohort */}
          {(() => {
            const largestCohort = data.reduce((largest, cohort) => 
              cohort.cohort_size > largest.cohort_size ? cohort : largest
            );
            
            return (
              <div className="p-4 bg-blue-50 border border-blue-200 rounded-lg">
                <h4 className="font-medium text-blue-800 mb-2">📈 Largest Cohort</h4>
                <p className="text-sm text-blue-700">
                  {formatDate(largestCohort.cohort_date)} with{' '}
                  {largestCohort.cohort_size.toLocaleString()} customers
                </p>
                {(() => {
                  const sixMonthRetention = largestCohort.retention_rates.find(r => r.month === 6);
                  return sixMonthRetention ? (
                    <p className="text-xs text-blue-600 mt-1">
                      6-month retention: {formatPercentage(sixMonthRetention.retention_rate * 100)}
                    </p>
                  ) : null;
                })()}
              </div>
            );
          })()}

          {/* Average Retention Trend */}
          <div className="p-4 bg-purple-50 border border-purple-200 rounded-lg">
            <h4 className="font-medium text-purple-800 mb-2">📊 Retention Trend</h4>
            <p className="text-sm text-purple-700">
              {data.length > 1 && (() => {
                const firstCohort = data[data.length - 1];
                const lastCohort = data[0];
                const firstRetention = firstCohort.retention_rates.find(r => r.month === 3);
                const lastRetention = lastCohort.retention_rates.find(r => r.month === 3);
                
                if (!firstRetention || !lastRetention) return 'Insufficient data';
                
                const trend = lastRetention.retention_rate - firstRetention.retention_rate;
                return trend > 0 
                  ? `📈 Improving by ${formatPercentage(Math.abs(trend) * 100)}`
                  : trend < 0
                  ? `📉 Declining by ${formatPercentage(Math.abs(trend) * 100)}`
                  : '➡️ Stable retention';
              })()}
            </p>
            <p className="text-xs text-purple-600 mt-1">
              3-month retention comparison
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};